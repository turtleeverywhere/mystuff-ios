import Foundation
import Observation

/// On-device library of recognition references, one directory per signed-in uid.
/// Each reference is a binary plist (`<id>.plist`) plus a thumbnail (`<id>.jpg`).
/// Nothing here syncs: a second device starts from item photos only.
@MainActor
@Observable
final class RecognitionStore {
    static let maxPerItem = 8
    static let maxEnrolled = 5
    /// A learned reference this close to an existing one teaches nothing new.
    static let learnedDedupeDistance: Float = 0.15

    struct SyncProgress: Equatable {
        var done: Int
        var total: Int
    }

    let embedder: ImageEmbedder
    private(set) var references: [ItemReference] = []
    /// Non-nil while `syncItemPhotos` is working.
    private(set) var syncProgress: SyncProgress?

    private let directory: URL
    private let fileManager = FileManager.default
    @ObservationIgnored private var isSyncing = false

    /// Loads every reference synchronously — a few hundred 3 KB files.
    init(directory: URL, embedder: ImageEmbedder) {
        self.directory = directory
        self.embedder = embedder
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        references = Self.load(from: directory)
    }

    /// `Application Support/Recognition/<uid>/`. Application Support is backed up,
    /// which matters: enrolled and learned references can't be rebuilt.
    static func directory(forUid uid: String) -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Recognition", isDirectory: true)
            .appendingPathComponent(uid.isEmpty ? "signed-out" : uid, isDirectory: true)
    }

    private static func load(from directory: URL) -> [ItemReference] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        let decoder = PropertyListDecoder()
        return urls
            .filter { $0.pathExtension == "plist" }
            .compactMap { url in
                // Unreadable or corrupt records are skipped, not fatal.
                (try? Data(contentsOf: url)).flatMap { try? decoder.decode(ItemReference.self, from: $0) }
            }
            .sorted { $0.createdAt < $1.createdAt }
    }

    // MARK: - Reading

    func references(for itemId: String) -> [ItemReference] {
        references.filter { $0.itemId == itemId }
    }

    func thumbnailURL(for reference: ItemReference) -> URL {
        directory.appendingPathComponent("\(reference.id).jpg")
    }

    private func recordURL(for reference: ItemReference) -> URL {
        directory.appendingPathComponent("\(reference.id).plist")
    }

    // MARK: - Writing

    /// Stores a reference, subject to the per-source rules. Returns nil when the
    /// reference was rejected (enrolled quota full, or a near-duplicate learned one).
    @discardableResult
    func add(
        _ embedding: Embedding,
        to itemId: String,
        source: ItemReference.Source,
        sourceKey: String? = nil,
        now: Date = .now
    ) -> ItemReference? {
        let comparable = references(for: itemId).filter { $0.modelID == embedder.modelID }
        switch source {
        case .itemPhoto:
            removeItemPhotoReference(itemId: itemId)
        case .enrolled:
            guard comparable.filter({ $0.source == .enrolled }).count < Self.maxEnrolled else { return nil }
        case .learned:
            let isDuplicate = comparable.contains {
                ItemMatcher.distance($0.vector, embedding.vector) < Self.learnedDedupeDistance
            }
            guard !isDuplicate else { return nil }
        }

        let reference = ItemReference(
            itemId: itemId,
            source: source,
            modelID: embedder.modelID,
            vector: embedding.vector,
            sourceKey: sourceKey,
            createdAt: now
        )
        references.append(reference)
        write(reference)
        try? embedding.thumbnail.write(to: thumbnailURL(for: reference), options: .atomic)
        evictOverflow(itemId: itemId)
        return reference
    }

    func remove(_ reference: ItemReference) {
        references.removeAll { $0.id == reference.id }
        try? fileManager.removeItem(at: recordURL(for: reference))
        try? fileManager.removeItem(at: thumbnailURL(for: reference))
    }

    func removeAll(itemId: String) {
        references(for: itemId).forEach(remove)
    }

    func removeItemPhotoReference(itemId: String) {
        references(for: itemId).filter { $0.source == .itemPhoto }.forEach(remove)
    }

    /// Embeds a photo taken through "Add angles". False when the photo is unreadable
    /// or the enrolled quota is full.
    func enroll(imageData: Data, itemId: String) async -> Bool {
        guard let embedding = try? await embedder.embed(imageData: imageData) else { return false }
        return add(embedding, to: itemId, source: .enrolled) != nil
    }

    /// Only learned references are evicted: the item photo and enrolled ones are
    /// deliberate, and together they can never exceed the cap.
    private func evictOverflow(itemId: String) {
        while references(for: itemId).count > Self.maxPerItem,
              let oldest = references(for: itemId)
                .filter({ $0.source == .learned })
                .min(by: { $0.createdAt < $1.createdAt }) {
            remove(oldest)
        }
    }

    private func write(_ reference: ItemReference) {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        guard let data = try? encoder.encode(reference) else { return }
        try? data.write(to: recordURL(for: reference), options: .atomic)
    }

    // MARK: - Item photos

    /// What an `itemPhoto` reference was derived from. Changes when the photo is
    /// replaced on another device (new remote URL).
    static func sourceKey(for item: Item) -> String? {
        item.remoteItemPhotoURL ?? item.itemPhotoURL
    }

    /// Re-derives the item-photo reference right after the photo changed on this
    /// device. Needed because the local path stays the same when a photo is
    /// replaced, so `sourceKey` alone can't see it.
    func refreshItemPhoto(for item: Item, imageData: Data) async {
        guard let embedding = try? await embedder.embed(imageData: imageData) else {
            removeItemPhotoReference(itemId: item.id)
            return
        }
        add(embedding, to: item.id, source: .itemPhoto, sourceKey: Self.sourceKey(for: item))
    }

    /// Brings item-photo references in line with `items`, and re-embeds references
    /// left over from another model. Photos that can't be loaded right now
    /// (remote-only while offline) are skipped and retried on the next call.
    func syncItemPhotos(
        for items: [Item],
        loadImageData: @MainActor (Item) async -> Data? = ItemPhotoLoader.data(for:)
    ) async {
        guard !isSyncing else { return }
        isSyncing = true
        defer {
            isSyncing = false
            syncProgress = nil
        }

        for item in items where !item.hasItemPhoto {
            removeItemPhotoReference(itemId: item.id)
        }

        let pending = items.filter { item in
            guard item.hasItemPhoto else { return false }
            let current = references.first {
                $0.itemId == item.id && $0.source == .itemPhoto && $0.modelID == embedder.modelID
            }
            return current?.sourceKey != Self.sourceKey(for: item)
        }
        let foreign = references.filter { $0.source != .itemPhoto && $0.modelID != embedder.modelID }
        guard !pending.isEmpty || !foreign.isEmpty else { return }

        syncProgress = SyncProgress(done: 0, total: pending.count + foreign.count)
        for item in pending {
            if let data = await loadImageData(item),
               let embedding = try? await embedder.embed(imageData: data) {
                add(embedding, to: item.id, source: .itemPhoto, sourceKey: Self.sourceKey(for: item))
            }
            syncProgress?.done += 1
        }
        for reference in foreign {
            await reembed(reference)
            syncProgress?.done += 1
        }
    }

    /// Moves a reference onto the current model using its stored thumbnail.
    /// A reference that can't be re-embedded is useless and is dropped.
    private func reembed(_ reference: ItemReference) async {
        guard let data = try? Data(contentsOf: thumbnailURL(for: reference)),
              let embedding = try? await embedder.embed(imageData: data),
              let index = references.firstIndex(where: { $0.id == reference.id })
        else {
            remove(reference)
            return
        }
        references[index].vector = embedding.vector
        references[index].modelID = embedder.modelID
        write(references[index])
    }
}
