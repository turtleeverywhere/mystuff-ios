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
    /// A location code seen by the camera that differs from the chosen destination.
    @State private var conflictingDestinationId: String?
    /// Locations the user declined to switch to; their codes are ignored from then on.
    @State private var declinedDestinationIds: Set<String> = []

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

    /// True while something covers the viewfinder. The scanner keeps running
    /// underneath, and codes it sees then must not change the session unseen.
    private var isCovered: Bool {
        showReview || showDestinationPicker || showDiscardConfirm
            || session.pendingCaptureId != nil || conflictingDestinationId != nil
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
        .confirmationDialog(
            destinationConflictTitle,
            isPresented: Binding(
                get: { conflictingDestinationId != nil },
                set: { if !$0 { conflictingDestinationId = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let id = conflictingDestinationId {
                Button("Switch to \(locationName(id))") {
                    apply(.location(id), replacingDestination: true)
                }
                Button("Keep \(destination?.name ?? "current")", role: .cancel) {
                    declinedDestinationIds.insert(id)
                }
            }
        }
    }

    private var destinationConflictTitle: String {
        guard let id = conflictingDestinationId else { return "" }
        return "The camera saw the code for \(locationName(id)). Move the items there instead?"
    }

    private func locationName(_ id: String) -> String {
        viewModel.locations.first { $0.id == id }?.name ?? "that location"
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
                // Holding the phone to a tag is deliberate, unlike a code drifting
                // into frame, so it may replace the destination outright.
                NFCScanButton(accepts: .any) { target in
                    apply(target, replacingDestination: true)
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
        ScrollViewReader { proxy in
            trayStrip
                // Keep the newest chip in view so every match is seen landing.
                .onChange(of: session.trayItemIds.last) { _, newest in
                    guard let newest else { return }
                    withAnimation { proxy.scrollTo(newest, anchor: .trailing) }
                }
        }
    }

    private var trayStrip: some View {
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
                    .id(item.id)
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
                // Always say what it was taken for — an unseen wrong match would be
                // moved, and then learned, on Confirm.
                show("Matched: \(itemName(match.itemId))" + distanceNote(of: match, runnerUp: alternatives.first))
            case .ambiguous, .noMatch:
                HapticManager.light()
            case nil:
                if let error = session.lastError { show(error) }
            }
        }
    }

    /// Threshold tuning aid for DEBUG builds — see `ItemMatcher`'s constants.
    private func distanceNote(of match: ItemMatch, runnerUp: ItemMatch?) -> String {
        #if DEBUG
        let next = runnerUp.map { String(format: "%.2f", $0.distance) } ?? "–"
        return String(format: " · %.2f (next %@)", match.distance, next)
        #else
        return ""
        #endif
    }

    private func itemName(_ id: String) -> String {
        viewModel.items.first { $0.id == id }?.name ?? "item"
    }

    /// A QR code in the viewfinder. Ignored while a sheet or dialog covers it.
    private func handleCode(_ payload: String) {
        guard !isCovered else { return }
        guard let url = URL(string: payload), let target = AppLink.parse(url) else {
            show("Not a MyStuff code")
            return
        }
        apply(target, replacingDestination: false)
    }

    private func apply(_ target: AppLink.Target, replacingDestination: Bool) {
        let previousDestination = session.destinationId
        switch session.handle(target, replacingDestination: replacingDestination) {
        case .addedItem(let id):
            HapticManager.success()
            show("Added: \(itemName(id))")
        case .setDestination(let id):
            // The same code re-read (tracking flicker) is not news.
            guard id != previousDestination else { return }
            HapticManager.success()
            show("Destination: \(locationName(id))")
        case .destinationConflict(let id):
            guard !declinedDestinationIds.contains(id) else { return }
            conflictingDestinationId = id
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
                session.discard(capture.id)
                show("Couldn't create the item")
                return
            }
            // Resolve before the photo: that closes the card at once, so a second
            // tap can't create the item twice while the photo is being embedded.
            session.resolve(capture.id, to: id, origin: .created)
            if let photo = capture.photo {
                await viewModel.setItemPhoto(for: item, imageData: photo)
            }
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
