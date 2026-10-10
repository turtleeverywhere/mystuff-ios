import SwiftUI

/// Camera-driven bulk move: choose a destination, capture items one at a time,
/// then confirm a single review list. Item and location QR codes seen by the
/// camera count too. Nothing is written until the review sheet.
struct ItemScanView: View {
    let viewModel: StuffViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var session: ScanSessionModel
    @State private var showDestinationPicker = false
    @State private var showReview = false
    @State private var showDiscardConfirm = false
    /// Transient one-line message above the tray.
    @State private var banner: String?

    init(viewModel: StuffViewModel, destinationId: String? = nil) {
        self.viewModel = viewModel
        _session = State(initialValue: ScanSessionModel(
            embedder: viewModel.recognition.embedder,
            store: viewModel.recognition,
            destinationId: destinationId,
            items: { viewModel.items },
            locations: { viewModel.locations }
        ))
    }

    private var destination: Location? {
        viewModel.locations.first { $0.id == session.destinationId }
    }

    private var trayItems: [Item] {
        session.trayItemIds.compactMap { id in viewModel.items.first { $0.id == id } }
    }

    /// Drives the match card. Swiping the card away drops an undecided capture.
    private var pendingCapture: Binding<ScanSessionModel.Capture?> {
        Binding(
            get: { session.captures.first { $0.id == session.pendingCaptureId } },
            set: { if $0 == nil { session.closePending() } }
        )
    }

    var body: some View {
        NavigationStack {
            ScanCaptureStage(isBusy: session.isProcessing, onCode: handleCode, onPhoto: handlePhoto) {
                VStack(spacing: 10) {
                    statusLine
                    if !trayItems.isEmpty { tray }
                }
            }
            .safeAreaInset(edge: .top) { destinationBar }
            .navigationTitle("Scan Items")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if trayItems.isEmpty { dismiss() } else { showDiscardConfirm = true }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Review (\(trayItems.count))") { showReview = true }
                        .disabled(trayItems.isEmpty)
                }
            }
        }
        .task {
            await viewModel.recognition.syncItemPhotos(for: viewModel.items)
        }
        .sheet(isPresented: $showDestinationPicker) {
            LocationSearchSheet(
                viewModel: viewModel,
                title: "Destination",
                selectedId: session.destinationId,
                unassignedLabel: nil
            ) { session.destinationId = $0 }
        }
        .sheet(item: pendingCapture) { capture in
            ScanMatchCard(
                capture: capture,
                viewModel: viewModel,
                onPick: { session.resolve(capture.id, to: $0) },
                onCreate: { createItem(named: $0, from: capture) },
                onRemove: {
                    if let itemId = capture.itemId {
                        session.removeFromTray(itemId)
                    } else {
                        session.discard(capture.id)
                    }
                }
            )
        }
        .sheet(isPresented: $showReview) {
            ScanReviewSheet(session: session, viewModel: viewModel) { dismiss() }
        }
        .confirmationDialog("Discard this scan?", isPresented: $showDiscardConfirm, titleVisibility: .visible) {
            Button("Discard \(trayItems.count) item\(trayItems.count == 1 ? "" : "s")", role: .destructive) { dismiss() }
            Button("Keep Scanning", role: .cancel) { }
        }
    }

    // MARK: - Pieces

    private var destinationBar: some View {
        Button {
            showDestinationPicker = true
        } label: {
            HStack(spacing: 8) {
                Text(destination?.emoji ?? "📍")
                Text(destination.map { viewModel.displayPath(for: $0) } ?? "Choose location")
                    .fontWeight(.semibold)
                    .lineLimit(1)
                Image(systemName: "chevron.down").font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
        }
        .tint(.primary)
        .padding(.top, 8)
    }

    private var statusText: String {
        if let banner { return banner }
        if let progress = viewModel.recognition.syncProgress {
            return "Preparing recognition \(progress.done)/\(progress.total)"
        }
        if session.isProcessing { return "Recognizing…" }
        return trayItems.isEmpty ? "Hold one item in the frame, then tap the shutter" : "Next item"
    }

    private var statusLine: some View {
        HStack(spacing: 10) {
            Text(statusText)
                .font(.callout)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
            if CoreNFCService.readingAvailable {
                NFCScanButton(accepts: .any) { target in
                    handleTarget(target)
                } label: { _ in
                    Image(systemName: "wave.3.right")
                        .padding(10)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .tint(.primary)
                .accessibilityLabel("Scan NFC tag")
            }
        }
        .padding(.horizontal)
    }

    private var tray: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(trayItems) { item in
                    Button {
                        session.pendingCaptureId = session.latestCaptureId(for: item.id)
                    } label: {
                        HStack(spacing: 6) {
                            PhotoView(item: item, kind: .item, size: .thumbnail(84)) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                Image(systemName: "shippingbox.fill").font(.caption)
                            }
                            .frame(width: 28, height: 28)
                            .clipShape(Circle())
                            Text(item.name).font(.subheadline).lineLimit(1)
                        }
                        .padding(.leading, 6)
                        .padding(.trailing, 12)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                    }
                    .tint(.primary)
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Actions

    private func handlePhoto(_ data: Data) {
        Task {
            switch await session.capture(imageData: data) {
            case .confident(let match, let alternatives):
                HapticManager.success()
                showDistances(of: match, runnerUp: alternatives.first)
            case .ambiguous, .noMatch:
                HapticManager.light()
            case nil:
                if let error = session.lastError { show(error) }
            }
        }
    }

    /// Threshold tuning aid for DEBUG builds — see `ItemMatcher`'s constants.
    private func showDistances(of match: ItemMatch, runnerUp: ItemMatch?) {
        #if DEBUG
        let next = runnerUp.map { String(format: "%.2f", $0.distance) } ?? "–"
        show(String(format: "Matched at %.2f (next %@)", match.distance, next))
        #endif
    }

    private func handleCode(_ payload: String) {
        guard let url = URL(string: payload), let target = AppLink.parse(url) else {
            show("Not a MyStuff code")
            return
        }
        handleTarget(target)
    }

    private func handleTarget(_ target: AppLink.Target) {
        switch session.handle(target) {
        case .addedItem, .setDestination:
            HapticManager.success()
        case .alreadyInTray:
            show("Already scanned")
        case .unknown:
            show("That code points to something that no longer exists")
        }
    }

    /// Creates the item right away (not undone by cancelling the session) and
    /// uses the captured photo as its item photo.
    private func createItem(named name: String, from capture: ScanSessionModel.Capture) {
        Task {
            let id = UUID().uuidString
            await viewModel.addItem(id: id, name: name, notes: nil, locationId: session.destinationId, categoryId: nil)
            guard let item = viewModel.items.first(where: { $0.id == id }) else {
                show("Couldn't create the item")
                return
            }
            if let photo = capture.photo {
                await viewModel.setItemPhoto(for: item, imageData: photo)
            }
            session.resolve(capture.id, to: id, origin: .created)
        }
    }

    private func show(_ message: String) {
        banner = message
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            if banner == message { banner = nil }
        }
    }
}
