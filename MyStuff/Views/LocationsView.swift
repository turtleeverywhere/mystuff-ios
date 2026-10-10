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
    @State private var searchText = ""
    @FocusState private var searchFocused: Bool
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
            .safeAreaInset(edge: .bottom) {
                if !viewModel.locations.isEmpty {
                    searchBar
                }
            }
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
                ToolbarItemGroup(placement: .topBarLeading) {
                    if QRScannerView.isSupported {
                        Button {
                            showingScanner = true
                        } label: {
                            Image(systemName: "qrcode.viewfinder")
                        }
                    }
                    NFCScanButton { target in
                        openScanned(target)
                    } label: { scanning in
                        Group {
                            if scanning {
                                ProgressView()
                            } else {
                                Image(systemName: "wave.3.right")
                            }
                        }
                        .frame(width: 20)
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
                    openScanned(target)
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
            .confirmLocationDeletion($locationToDelete, viewModel: viewModel)
        }
        .containerBackground(LinearGradient.appBackground, for: .navigation)
    }

    // MARK: - Scanning

    /// Shared by the QR and NFC buttons: both resolve to the same target kinds,
    /// so they navigate (locations) or open a quick update (items) identically.
    private func openScanned(_ target: AppLink.Target) {
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

    /// One `List` for both modes on purpose: swapping the whole content view when
    /// search text appears tears down the bottom `safeAreaInset` with the text field
    /// in it, which drops keyboard focus after the first character.
    private var locationsList: some View {
        List {
            if trimmedSearch.isEmpty {
                treeRows
            } else {
                searchRows
            }
        }
        .overlay {
            if !trimmedSearch.isEmpty && searchResults.isEmpty {
                ContentUnavailableView.search(text: trimmedSearch)
            }
        }
    }

    private var treeRows: some View {
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
                        rowLabel(for: entry.location)
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

    /// Row content shared by the tree and the search results. `subtitle` carries the
    /// ancestor path in search results, where the tree indentation is gone.
    private func rowLabel(for location: Location, subtitle: String? = nil) -> some View {
        HStack {
            Text(location.emoji ?? "📍")
                .font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(location.name)
                        .font(.body)
                        .foregroundStyle(.primary)
                    if viewModel.isSharedWithMe(location) {
                        SharedBadge(iconOnly: true, ownerName: viewModel.friend(forUid: location.ownerId ?? "")?.displayName)
                    } else if viewModel.isShared(location) {
                        SharedBadge(iconOnly: true)
                    }
                    if !location.pairedTags.isEmpty {
                        NFCBadge(iconOnly: true)
                    }
                }
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
            Spacer()
            Text("\(viewModel.recursiveItemCount(for: location)) items")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial, in: Capsule())
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    // MARK: - Search

    private var trimmedSearch: String {
        searchText.trimmingCharacters(in: .whitespaces)
    }

    /// Flat, name-matched results — a tree filtered in place would hide matches
    /// sitting under collapsed parents.
    private var searchResults: [Location] {
        let query = trimmedSearch
        guard !query.isEmpty else { return [] }
        return viewModel.locations
            .filter { $0.name.localizedCaseInsensitiveContains(query) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var searchRows: some View {
        ForEach(searchResults) { location in
            Button {
                path.append(location)
            } label: {
                rowLabel(for: location, subtitle: ancestorPath(for: location))
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button {
                    addingSublocationParent = location
                } label: {
                    Label("Add Sub-location", systemImage: "plus")
                }
                Button {
                    movingLocation = location
                } label: {
                    Label("Move", systemImage: "folder")
                }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                    locationToDelete = location
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    /// "Home > Garage" for a location's parents — empty for a root.
    private func ancestorPath(for location: Location) -> String {
        viewModel.locationPath(for: location).dropLast().map(\.name).joined(separator: " > ")
    }

    /// Sits in the bottom safe area, above the tab bar.
    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search locations", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($searchFocused)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    searchFocused = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.secondary.opacity(0.25), lineWidth: 1))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
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
                    LocationPickerRow(
                        viewModel: viewModel,
                        label: "Parent",
                        pickerTitle: "Choose Parent",
                        emptyLabel: "None (Root)",
                        excluding: location?.id,
                        selection: Binding(
                            get: { selectedParentId == Self.noParentSentinel ? nil : selectedParentId },
                            set: { selectedParentId = $0 ?? Self.noParentSentinel }
                        )
                    )
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
                        HStack(spacing: 10) {
                            Image(systemName: "house")
                                .foregroundStyle(.secondary)
                            Text("Root (top level)")
                            Spacer()
                            if location.parentId == nil { LocationPickerCheckmark() }
                        }
                    }
                    .tint(.primary)
                } header: {
                    Text("Move \"\(location.name)\" to…")
                } footer: {
                    Text("Moving into a shared location shares this location and its contents with the same people.")
                }

                LocationTreeSections(
                    viewModel: viewModel,
                    selectedId: location.parentId,
                    excluding: location.id
                ) { parentId in
                    select(parentId: parentId)
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
