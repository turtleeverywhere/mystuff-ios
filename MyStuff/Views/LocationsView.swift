import SwiftUI

struct LocationsView: View {
    @Bindable var viewModel: StuffViewModel
    @State private var showingAddSheet = false
    @State private var locationToDelete: Location?
    @State private var expandedIds: Set<String> = []
    @State private var path: [Location] = []
    @State private var showingScanner = false
    @State private var scannedItem: Item?
    @State private var addingSublocationParent: Location?
    @State private var movingLocation: Location?
    /// Scanned code resolved to an id we no longer hold — surface it instead of
    /// dismissing the scanner with nothing happening.
    @State private var unknownScan = false

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if viewModel.locations.isEmpty {
                    emptyState
                } else {
                    locationsList
                }
            }
            .navigationTitle("Locations")
            .navigationDestination(for: Location.self) { loc in
                LocationDetailView(location: loc, viewModel: viewModel)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    if QRScannerView.isSupported {
                        Button {
                            showingScanner = true
                        } label: {
                            Image(systemName: "qrcode.viewfinder")
                        }
                    }
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                LocationFormSheet(
                    viewModel: viewModel,
                    onSave: { result in
                        Task {
                            await viewModel.addLocation(id: result.id, name: result.name, emoji: result.emoji, parentId: result.parentId)
                            guard viewModel.locations.contains(where: { $0.id == result.id }) else { return }
                            await viewModel.applyStagedTags(result.nfcTags, to: .location(result.id))
                        }
                    }
                )
            }
            .sheet(isPresented: $showingScanner) {
                QRScannerSheet { target in
                    switch target {
                    case .location(let id):
                        if let loc = viewModel.locations.first(where: { $0.id == id }) {
                            path.append(loc)
                        } else {
                            unknownScan = true
                        }
                    case .item(let id):
                        if let item = viewModel.items.first(where: { $0.id == id }) {
                            scannedItem = item
                        } else {
                            unknownScan = true
                        }
                    }
                }
            }
            .sheet(item: $scannedItem) { item in
                ItemQuickUpdateSheet(item: item, viewModel: viewModel)
            }
            .sheet(item: $addingSublocationParent) { parent in
                LocationFormSheet(
                    initialParentId: parent.id,
                    viewModel: viewModel,
                    onSave: { result in
                        Task {
                            await viewModel.addLocation(id: result.id, name: result.name, emoji: result.emoji, parentId: result.parentId)
                            guard viewModel.locations.contains(where: { $0.id == result.id }) else { return }
                            await viewModel.applyStagedTags(result.nfcTags, to: .location(result.id))
                        }
                        if let parentId = result.parentId { expandedIds.insert(parentId) }
                    }
                )
            }
            .sheet(item: $movingLocation) { location in
                MoveLocationSheet(
                    location: location,
                    viewModel: viewModel,
                    onMove: { newParentId in
                        Task { await viewModel.moveLocation(location, toParentId: newParentId) }
                        if let newParentId { expandedIds.insert(newParentId) }
                    }
                )
            }
            .alert("Not found", isPresented: $unknownScan) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("That code points to something that no longer exists.")
            }
            .alert("Delete Location?", isPresented: Binding(
                get: { locationToDelete != nil },
                set: { if !$0 { locationToDelete = nil } }
            )) {
                Button("Delete", role: .destructive) {
                    if let loc = locationToDelete {
                        let hasChildren = !viewModel.childLocations(for: loc).isEmpty
                        Task {
                            await viewModel.deleteLocation(loc)
                            _ = hasChildren // suppress unused warning
                        }
                    }
                }
                Button("Cancel", role: .cancel) { locationToDelete = nil }
            } message: {
                if let loc = locationToDelete, !viewModel.childLocations(for: loc).isEmpty {
                    Text("Sub-locations will be moved up one level. Items at this location will be unassigned.")
                } else {
                    Text("Items at this location will be unassigned.")
                }
            }
        }
        .containerBackground(LinearGradient.appBackground, for: .navigation)
    }

    // MARK: - Locations List

    /// Visible locations based on expanded state. Locations whose parent isn't visible to the
    /// current user (e.g. a shared sub-location whose parent wasn't shared) are treated as roots
    /// so they still appear — mirrors StuffViewModel.rootLocations (used by the Home tab).
    private var visibleEntries: [(location: Location, depth: Int)] {
        let visibleIds = Set(viewModel.locations.map(\.id))
        var result: [(Location, Int)] = []
        func children(of parentId: String) -> [Location] {
            viewModel.locations
                .filter { $0.parentId == parentId }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        func walk(_ location: Location, depth: Int) {
            result.append((location, depth))
            if expandedIds.contains(location.id) {
                for child in children(of: location.id) {
                    walk(child, depth: depth + 1)
                }
            }
        }
        let roots = viewModel.locations
            .filter { loc in
                guard let pid = loc.parentId else { return true }
                return !visibleIds.contains(pid)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        for root in roots {
            walk(root, depth: 0)
        }
        return result
    }

    private var locationsList: some View {
        List {
            ForEach(visibleEntries, id: \.location.id) { entry in
                let hasChildren = !viewModel.childLocations(for: entry.location).isEmpty
                HStack(spacing: 0) {
                    // Expand/collapse button
                    if hasChildren {
                        Button {
                            withAnimation {
                                if expandedIds.contains(entry.location.id) {
                                    expandedIds.remove(entry.location.id)
                                } else {
                                    expandedIds.insert(entry.location.id)
                                }
                            }
                        } label: {
                            Image(systemName: expandedIds.contains(entry.location.id) ? "chevron.down" : "chevron.right")
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    } else {
                        Spacer().frame(width: 44)
                    }

                    // Location label -> detail. A plain Button with programmatic
                    // navigation (not a row-level NavigationLink) so the leading
                    // chevron stays tappable and long-press opens the context menu
                    // on iPad — a NavigationLink swallows both there.
                    Button {
                        path.append(entry.location)
                    } label: {
                        HStack {
                            Text(entry.location.emoji ?? "📍")
                                .font(.title2)
                            Text(entry.location.name)
                                .font(.body)
                                .foregroundStyle(.primary)
                            if viewModel.isSharedWithMe(entry.location) {
                                SharedBadge(iconOnly: true, ownerName: viewModel.friend(forUid: entry.location.ownerId ?? "")?.displayName)
                            } else if viewModel.isShared(entry.location) {
                                SharedBadge(iconOnly: true)
                            }
                            if !entry.location.pairedTags.isEmpty {
                                NFCBadge(iconOnly: true)
                            }
                            Spacer()
                            Text("\(viewModel.recursiveItemCount(for: entry.location)) items")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(.ultraThinMaterial, in: Capsule())
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .contextMenu {
                    Button {
                        addingSublocationParent = entry.location
                    } label: {
                        Label("Add Sub-location", systemImage: "plus")
                    }
                    Button {
                        movingLocation = entry.location
                    } label: {
                        Label("Move", systemImage: "folder")
                    }
                }
                .padding(.leading, CGFloat(entry.depth) * 24)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        locationToDelete = entry.location
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Locations Yet", systemImage: "mappin.circle")
        } description: {
            Text("Add locations like \"Living Room\", \"Garage\", or \"Car\" to start organizing your stuff.")
        } actions: {
            Button("Add Location") {
                showingAddSheet = true
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

// MARK: - Location Form Sheet

/// Everything `LocationFormSheet` hands back on Save. Mirrors `ItemFormResult`.
struct LocationFormResult {
    let id: String
    let name: String
    let emoji: String?
    let parentId: String?
    let nfcTags: [NFCTag]
}

struct LocationFormSheet: View {
    let location: Location?
    let viewModel: StuffViewModel
    let onSave: (LocationFormResult) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var emoji: String
    @State private var selectedParentId: String
    /// Pre-allocated so codes can be paired and printed against a draft that
    /// has not been saved yet. MUST be `@State`: SwiftUI recreates the view
    /// struct on every render, so a plain `let` would mint a fresh UUID each
    /// pass and a paired tag would point at an id that never reaches Firestore.
    @State private var draftId: String
    /// Tag edits are buffered here and applied on Save.
    @State private var stagedTags: [NFCTag]
    @State private var showCodes = false

    private static let noParentSentinel = "__none__"
    private let popularEmojis = ["🏠", "🚗", "📦", "🏢", "🛋️", "🖥️", "🚙", "🏠", "🔧", "🏕️", "🎒", "🗄️"]

    /// `initialParentId` pre-selects a parent when creating a NEW location
    /// (e.g. "Add Sub-location" from a long-press); ignored when editing.
    init(location: Location? = nil, initialParentId: String? = nil, viewModel: StuffViewModel, onSave: @escaping (LocationFormResult) -> Void) {
        self.location = location
        self.viewModel = viewModel
        self.onSave = onSave
        _name = State(initialValue: location?.name ?? "")
        _emoji = State(initialValue: location?.emoji ?? "")
        _selectedParentId = State(initialValue: location?.parentId ?? initialParentId ?? Self.noParentSentinel)
        _draftId = State(initialValue: location?.id ?? UUID().uuidString)
        _stagedTags = State(initialValue: location?.pairedTags ?? [])
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Location name", text: $name)
                    TextField("Emoji icon (optional)", text: $emoji)
                        .textInputAutocapitalization(.never)
                }

                Section("Parent Location") {
                    Picker("Parent", selection: $selectedParentId) {
                        Text("None (Root)").tag(Self.noParentSentinel)
                        ForEach(viewModel.flattenedLocationTree(excluding: location?.id), id: \.location.id) { entry in
                            Text(String(repeating: "  ", count: entry.depth) + (entry.location.emoji ?? "📍") + " " + entry.location.name)
                                .tag(entry.location.id)
                        }
                    }
                }

                Section("Quick Pick") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(popularEmojis, id: \.self) { e in
                            Button {
                                emoji = e
                            } label: {
                                Text(e)
                                    .font(.title2)
                                    .padding(8)
                                    .background(
                                        emoji == e ? Color.accentColor.opacity(0.2) : Color.clear,
                                        in: RoundedRectangle(cornerRadius: 8)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                codesSection
            }
            .navigationTitle(location == nil ? "New Location" : "Edit Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let parentId = selectedParentId == Self.noParentSentinel ? nil : selectedParentId
                        onSave(LocationFormResult(
                            id: draftId,
                            name: name,
                            emoji: emoji.isEmpty ? nil : emoji,
                            parentId: parentId,
                            nfcTags: stagedTags
                        ))
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .sheet(isPresented: $showCodes) {
                CodesSheet(
                    subject: QRSubject(
                        target: .location(draftId),
                        name: name,
                        icon: emoji.isEmpty ? "📍" : emoji
                    ),
                    tags: stagedTags,
                    onPair: { serial in
                        guard !stagedTags.contains(where: { $0.uid == serial }) else { return }
                        stagedTags.append(NFCTag(uid: serial))
                    },
                    onRemove: { serial in
                        stagedTags.removeAll { $0.uid == serial }
                    },
                    onRename: { serial, label in
                        guard let index = stagedTags.firstIndex(where: { $0.uid == serial }) else { return }
                        let trimmed = label?.trimmingCharacters(in: .whitespacesAndNewlines)
                        stagedTags[index].label = (trimmed?.isEmpty ?? true) ? nil : trimmed
                    },
                    viewModel: viewModel
                )
            }
        }
    }

    /// Extracted so the `Form`'s `body` type-checks in reasonable time.
    private var codesSection: some View {
        Section {
            Button {
                showCodes = true
            } label: {
                CodesRow(tags: stagedTags)
            }
            .tint(.primary)
        } header: {
            Text("Codes")
        } footer: {
            if location == nil {
                Text("Codes activate when you save this location.")
            }
        }
    }
}

// MARK: - Move Location Sheet

struct MoveLocationSheet: View {
    let location: Location
    let viewModel: StuffViewModel
    let onMove: (String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        // Detents are ignored in regular width (iPad form sheet); use page sizing there instead.
        if horizontalSizeClass == .regular {
            content.presentationSizing(.page)
        } else {
            content.presentationDetents([.medium])
        }
    }

    private func select(parentId: String?) {
        onMove(parentId)
        dismiss()
    }

    private var content: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        select(parentId: nil)
                    } label: {
                        Label("Root (top level)", systemImage: "house")
                    }
                    .tint(location.parentId == nil ? .accentColor : .primary)

                    ForEach(viewModel.flattenedLocationTree(excluding: location.id), id: \.location.id) { entry in
                        Button {
                            select(parentId: entry.location.id)
                        } label: {
                            Label {
                                Text(entry.location.name)
                            } icon: {
                                Text(entry.location.emoji ?? "📍")
                            }
                        }
                        .tint(entry.location.id == location.parentId ? .accentColor : .primary)
                        .padding(.leading, CGFloat(entry.depth) * 20)
                    }
                } header: {
                    Text("Move \"\(location.name)\" to…")
                } footer: {
                    Text("Moving into a shared location shares this location and its contents with the same people.")
                }
            }
            .navigationTitle("Move Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    ContentView(authService: AuthService())
}
