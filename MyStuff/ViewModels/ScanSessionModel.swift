import Foundation
import Observation

/// State of one scan session: the destination, every capture, and what each
/// capture was resolved to. Holds no `StuffViewModel` — it reads items and
/// locations through closures and leaves Firestore writes to the views, so it
/// can be tested without Firebase.
@MainActor
@Observable
final class ScanSessionModel {

    /// One shutter tap or code scan.
    struct Capture: Identifiable {
        enum Resolution: Equatable {
            /// Waiting for the user to say which item this is.
            case pending
            case item(String)
        }

        enum Origin: Equatable {
            case camera
            /// Item QR / NFC — the fallback for near-identical items.
            case code
            /// The user created a new item from this capture.
            case created
        }

        let id = UUID()
        /// Compressed photo, kept so "New item" can use it as the item photo.
        var photo: Data?
        /// nil for code scans, which teach the matcher nothing.
        var embedding: Embedding?
        var candidates: [ItemMatch] = []
        var resolution: Resolution = .pending
        var origin: Origin = .camera
        var wasAutoAccepted = false

        var itemId: String? {
            if case .item(let id) = resolution { return id }
            return nil
        }
    }

    enum CodeResult: Equatable {
        case addedItem(String)
        case alreadyInTray(String)
        case setDestination(String)
        /// The code points at an item or location that no longer exists.
        case unknown
    }

    var destinationId: String?
    /// The capture whose match card is showing.
    var pendingCaptureId: UUID?
    private(set) var captures: [Capture] = []
    private(set) var isProcessing = false
    private(set) var lastError: String?

    private let embedder: ImageEmbedder
    private let store: RecognitionStore
    private let items: @MainActor () -> [Item]
    private let locations: @MainActor () -> [Location]

    init(
        embedder: ImageEmbedder,
        store: RecognitionStore,
        destinationId: String? = nil,
        items: @escaping @MainActor () -> [Item],
        locations: @escaping @MainActor () -> [Location]
    ) {
        self.embedder = embedder
        self.store = store
        self.destinationId = destinationId
        self.items = items
        self.locations = locations
    }

    /// Resolved item ids, unique, in first-seen order. Items deleted since they
    /// were captured (live sync) drop out.
    var trayItemIds: [String] {
        let known = Set(items().map(\.id))
        var seen: Set<String> = []
        return captures.compactMap(\.itemId).filter { known.contains($0) && seen.insert($0).inserted }
    }

    // MARK: - Capturing

    /// Embeds and matches one photo. A confident match goes straight into the
    /// tray; anything else becomes the pending capture. Returns nil when the
    /// photo couldn't be read, or when a capture is already in flight.
    @discardableResult
    func capture(imageData: Data) async -> MatchOutcome? {
        guard !isProcessing else { return nil }
        isProcessing = true
        defer { isProcessing = false }
        lastError = nil

        let photo = ImageHelper.compress(imageData) ?? imageData
        guard let embedding = try? await embedder.embed(imageData: photo) else {
            lastError = "Couldn't read that photo"
            return nil
        }

        let ranked = ItemMatcher.rank(
            embedding.vector,
            references: store.references,
            knownItemIds: Set(items().map(\.id)),
            modelID: embedder.modelID
        )
        let outcome = ItemMatcher.classify(ranked)

        var capture = Capture(photo: photo, embedding: embedding)
        switch outcome {
        case .confident(let best, let alternatives):
            capture.candidates = [best] + alternatives
            capture.resolution = .item(best.itemId)
            capture.wasAutoAccepted = true
        case .ambiguous(let candidates), .noMatch(let candidates):
            capture.candidates = candidates
        }
        captures.append(capture)
        if capture.itemId == nil { pendingCaptureId = capture.id }
        return outcome
    }

    // MARK: - Decisions

    func resolve(_ captureId: UUID, to itemId: String, origin: Capture.Origin? = nil) {
        guard let index = captures.firstIndex(where: { $0.id == captureId }) else { return }
        captures[index].resolution = .item(itemId)
        captures[index].wasAutoAccepted = false
        if let origin { captures[index].origin = origin }
        if pendingCaptureId == captureId { pendingCaptureId = nil }
    }

    func discard(_ captureId: UUID) {
        captures.removeAll { $0.id == captureId }
        if pendingCaptureId == captureId { pendingCaptureId = nil }
    }

    /// The match card was closed without a choice. An undecided capture is
    /// dropped; one that was already decided (reopened from the tray) stays.
    func closePending() {
        if let id = pendingCaptureId, captures.first(where: { $0.id == id })?.itemId == nil {
            captures.removeAll { $0.id == id }
        }
        pendingCaptureId = nil
    }

    func removeFromTray(_ itemId: String) {
        captures.removeAll { $0.itemId == itemId }
        if let id = pendingCaptureId, !captures.contains(where: { $0.id == id }) {
            pendingCaptureId = nil
        }
    }

    func latestCaptureId(for itemId: String) -> UUID? {
        captures.last { $0.itemId == itemId }?.id
    }

    // MARK: - Codes

    /// A QR or NFC code seen during the session: a location code sets the
    /// destination, an item code adds that item to the tray.
    @discardableResult
    func handle(_ target: AppLink.Target) -> CodeResult {
        switch target {
        case .location(let id):
            guard locations().contains(where: { $0.id == id }) else { return .unknown }
            destinationId = id
            return .setDestination(id)
        case .item(let id):
            guard items().contains(where: { $0.id == id }) else { return .unknown }
            guard !trayItemIds.contains(id) else { return .alreadyInTray(id) }
            captures.append(Capture(resolution: .item(id), origin: .code))
            return .addedItem(id)
        }
    }

    // MARK: - Learning

    /// Call after the move was confirmed: every photographed capture of a
    /// selected, still-existing item becomes a learned reference. Deselected and
    /// discarded captures teach nothing, so wrong matches never pollute the library.
    func saveLearnedReferences(selected: Set<String>) {
        let known = Set(items().map(\.id))
        for capture in captures {
            guard let embedding = capture.embedding,
                  let itemId = capture.itemId,
                  selected.contains(itemId),
                  known.contains(itemId)
            else { continue }
            store.add(embedding, to: itemId, source: .learned)
        }
    }
}
