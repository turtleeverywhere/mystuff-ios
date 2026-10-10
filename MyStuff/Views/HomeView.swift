import PhotosUI
import SwiftUI

struct HomeView: View {
    @Bindable var viewModel: StuffViewModel
    var onProfileTap: (() -> Void)? = nil
    var pendingRequestCount: Int = 0
    @State private var selectedItem: Item?
    @State private var detailItem: Item?
    @State private var itemToPromptPhoto: Item?
    @State private var previewItem: Item?
    @State private var photoSourceItem: Item?
    @State private var showPhotoSource = false
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var homeSearchText = ""
    @State private var filter = ItemFilter()
    @State private var showFilters = false
    @State private var showItemScan = false
    @State private var itemToDelete: Item?
    @AppStorage("homeViewMode") private var viewMode = "list"
    @AppStorage("galleryColumns") private var galleryColumns = 2
    /// Newline-separated ids of root location cards the user collapsed.
    @AppStorage("homeCollapsedLocations") private var collapsedLocationsRaw = ""
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isGallery: Bool { viewMode == "gallery" }

    // MARK: - Collapse State

    /// Key used for the "Unassigned" card, which has no location id.
    private static let unassignedKey = "__unassigned__"

    private var collapsedLocations: Set<String> {
        Set(collapsedLocationsRaw.split(separator: "\n").map(String.init))
    }

    private func isCollapsed(_ key: String) -> Bool {
        collapsedLocations.contains(key)
    }

    private func toggleCollapsed(_ key: String) {
        var set = collapsedLocations
        if set.contains(key) { set.remove(key) } else { set.insert(key) }
        collapsedLocationsRaw = set.sorted().joined(separator: "\n")
    }

    /// Every root-level card key currently on screen.
    private var collapsibleKeys: [String] {
        var keys = viewModel.rootLocations.map(\.id)
        if !filtered(viewModel.unassignedItems).isEmpty {
            keys.append(Self.unassignedKey)
        }
        return keys
    }

    private var allCollapsed: Bool {
        let keys = collapsibleKeys
        guard !keys.isEmpty else { return false }
        let collapsed = collapsedLocations
        return keys.allSatisfy { collapsed.contains($0) }
    }

    private func toggleAll() {
        collapsedLocationsRaw = allCollapsed ? "" : collapsibleKeys.sorted().joined(separator: "\n")
    }

    /// Items matching current search + filters
    private var homeFilteredItems: Set<String> {
        Set(visibleItems.map(\.id))
    }

    private var visibleItems: [Item] {
        filter.apply(to: viewModel.items, searchText: homeSearchText, viewModel: viewModel)
    }

    private var isFiltering: Bool {
        !homeSearchText.isEmpty || filter.isActive
    }

    private func filtered(_ items: [Item]) -> [Item] {
        guard isFiltering else { return items }
        return items.filter { homeFilteredItems.contains($0.id) }
    }

    /// What "Put All Back" acts on: everything currently visible that is misplaced.
    private var putBackTargets: [Item] {
        guard filter.misplacedOnly else { return [] }
        return visibleItems
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.items.isEmpty && viewModel.locations.isEmpty && viewModel.categories.isEmpty {
                    emptyState
                } else {
                    mainContent
                }
            }
            .navigationTitle("My Stuff")
            .searchable(text: $homeSearchText, prompt: "Search items")
            .toolbar {
                if let onProfileTap {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(action: onProfileTap) {
                            Image(systemName: "person.circle.fill")
                                .font(.title3)
                                .symbolRenderingMode(.hierarchical)
                                .overlay(alignment: .topTrailing) {
                                    if pendingRequestCount > 0 {
                                        Circle()
                                            .fill(Color.red)
                                            .frame(width: 10, height: 10)
                                            .offset(x: 3, y: -2)
                                    }
                                }
                        }
                    }
                }
                if isGallery && horizontalSizeClass == .regular {
                    ToolbarItem(placement: .primaryAction) {
                        GalleryColumnSlider()
                    }
                }
                if viewModel.selectedGrouping == .location && !collapsibleKeys.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            withAnimation(.snappy) { toggleAll() }
                        } label: {
                            Image(systemName: allCollapsed
                                  ? "rectangle.expand.vertical"
                                  : "rectangle.compress.vertical")
                        }
                        .accessibilityLabel(allCollapsed ? "Expand all locations" : "Collapse all locations")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showItemScan = true
                    } label: {
                        Image(systemName: "camera.viewfinder")
                    }
                    .accessibilityLabel("Scan items")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        withAnimation { viewMode = isGallery ? "list" : "gallery" }
                    } label: {
                        Image(systemName: isGallery ? "list.bullet" : "square.grid.2x2")
                    }
                }
            }
            .fullScreenCover(isPresented: $showItemScan) {
                ItemScanView(viewModel: viewModel)
            }
            .confirmItemDeletion($itemToDelete, viewModel: viewModel)
            .sheet(item: $selectedItem) { item in
                MoveItemSheet(
                    item: item,
                    viewModel: viewModel,
                    onMove: { locationId in
                        Task {
                            await viewModel.moveItem(item, toLocationId: locationId)
                            if item.hasLocationPhoto {
                                itemToPromptPhoto = item
                            }
                        }
                    }
                )
            }
            .sheet(item: $detailItem) { item in
                ItemDetailSheet(item: item, viewModel: viewModel)
            }
            .confirmationDialog(
                "Update photo for new location?",
                isPresented: Binding(
                    get: { itemToPromptPhoto != nil },
                    set: { if !$0 { itemToPromptPhoto = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Update Photo") {
                    detailItem = itemToPromptPhoto
                    itemToPromptPhoto = nil
                }
                Button("Later", role: .cancel) {
                    itemToPromptPhoto = nil
                }
            }
            .fullScreenCover(item: $previewItem) { item in
                PhotoPreviewViewer(item: item, kind: .location, viewModel: viewModel)
            }
            .sheet(isPresented: $showPhotoSource) {
                PhotoSourceSheet(
                    onCamera: { showCamera = true },
                    onLibrary: { showPhotoPicker = true }
                )
            }
            .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhoto, matching: .images)
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { data in
                    guard let item = photoSourceItem else { return }
                    Task {
                        await viewModel.setPhoto(for: item, imageData: data)
                        photoSourceItem = nil
                    }
                }
                .ignoresSafeArea()
            }
            .onChange(of: selectedPhoto) {
                guard let selectedPhoto, let item = photoSourceItem else { return }
                Task {
                    if let data = try? await selectedPhoto.loadTransferable(type: Data.self) {
                        await viewModel.setPhoto(for: item, imageData: data)
                    }
                    self.selectedPhoto = nil
                    photoSourceItem = nil
                }
            }
        }
        .containerBackground(LinearGradient.appBackground, for: .navigation)
    }

    // MARK: - Main Content

    private var mainContent: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                // Grouping picker
                Picker("Group by", selection: $viewModel.selectedGrouping) {
                    ForEach(StuffViewModel.GroupingMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                ItemFilterBar(
                    filter: $filter,
                    isExpanded: $showFilters,
                    viewModel: viewModel,
                    isFiltering: isFiltering,
                    putBackTargets: putBackTargets,
                    onPutAllBack: {
                        let targets = putBackTargets
                        Task { await viewModel.putBackItems(targets) }
                    },
                    onClearAll: {
                        filter = ItemFilter()
                        homeSearchText = ""
                    }
                )

                switch viewModel.selectedGrouping {
                case .location:
                    locationGrouping
                case .category:
                    categoryGrouping
                }
            }
            .padding()
        }
    }

    // MARK: - Location Grouping

    private var locationGrouping: some View {
        Group {
            ForEach(viewModel.rootLocations) { location in
                let card = locationCardContent(location)
                if card.totalCount > 0 || !isFiltering {
                    locationCard(location, directItems: card.directItems, descendantEntries: card.descendantEntries, totalCount: card.totalCount)
                }
            }
            let unassigned = filtered(viewModel.unassignedItems)
            if !unassigned.isEmpty {
                unassignedLocationCard(items: unassigned)
            }
        }
    }

    private struct LocationCardContent {
        let directItems: [Item]
        let descendantEntries: [(sublocation: Location, items: [Item])]
        var totalCount: Int {
            directItems.count + descendantEntries.reduce(0) { $0 + $1.items.count }
        }
    }

    private func locationCardContent(_ location: Location) -> LocationCardContent {
        let direct = filtered(viewModel.items(for: location))
        let descendants = viewModel.flattenedDescendantItems(for: location).compactMap { entry -> (sublocation: Location, items: [Item])? in
            let items = filtered(entry.items)
            return items.isEmpty ? nil : (entry.sublocation, items)
        }
        return LocationCardContent(directItems: direct, descendantEntries: descendants)
    }

    // MARK: - Category Grouping

    private var categoryGrouping: some View {
        Group {
            ForEach(viewModel.categories) { category in
                let items = filtered(viewModel.items(for: category))
                if !items.isEmpty || !isFiltering {
                    categoryCard(category, items: items)
                }
            }
            let uncategorized = filtered(viewModel.uncategorizedItems)
            if !uncategorized.isEmpty {
                uncategorizedCard(items: uncategorized)
            }
        }
    }

    // MARK: - Location Card

    private func locationCard(_ location: Location, directItems: [Item], descendantEntries: [(sublocation: Location, items: [Item])], totalCount: Int) -> some View {
        let collapsed = isCollapsed(location.id)
        return VStack(alignment: .leading, spacing: 12) {
            cardHeader(
                emoji: location.emoji ?? "📍",
                title: location.name,
                count: totalCount,
                collapsed: collapsed
            ) {
                toggleCollapsed(location.id)
            }

            if !collapsed {
                if directItems.isEmpty && descendantEntries.isEmpty {
                    Text("No items here")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, 4)
                } else if isGallery {
                    galleryGrid(directItems)

                    ForEach(descendantEntries, id: \.sublocation.id) { entry in
                        sublocationHeader(entry.sublocation, relativeTo: location)
                        galleryGrid(entry.items)
                    }
                } else {
                    ForEach(directItems) { item in
                        itemRow(item, tag: categoryTag(for: item))
                    }

                    ForEach(descendantEntries, id: \.sublocation.id) { entry in
                        sublocationHeader(entry.sublocation, relativeTo: location)
                        ForEach(entry.items) { item in
                            itemRow(item, tag: categoryTag(for: item))
                                .padding(.leading, 8)
                        }
                    }
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    /// Tappable card header with a collapse chevron.
    private func cardHeader(emoji: String, title: String, count: Int, collapsed: Bool, onTap: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.snappy) { onTap() }
        } label: {
            HStack {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(collapsed ? 0 : 90))
                Text(emoji)
                    .font(.title2)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(count) items")
        .accessibilityHint(collapsed ? "Expand" : "Collapse")
    }

    private func sublocationHeader(_ sublocation: Location, relativeTo root: Location) -> some View {
        let path = viewModel.locationPath(for: sublocation)
        // Build relative path: drop everything up to and including root
        let relativePath: String
        if let rootIdx = path.firstIndex(where: { $0.id == root.id }) {
            relativePath = path.suffix(from: path.index(after: rootIdx)).map(\.name).joined(separator: " > ")
        } else {
            relativePath = sublocation.name
        }
        return VStack(alignment: .leading, spacing: 8) {
            Divider()
                .opacity(0.5)
            HStack(spacing: 6) {
                Text(sublocation.emoji ?? "📍")
                    .font(.subheadline)
                Text(relativePath)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 6)
    }

    // MARK: - Unassigned Location Card

    private func unassignedLocationCard(items: [Item]) -> some View {
        let collapsed = isCollapsed(Self.unassignedKey)
        return VStack(alignment: .leading, spacing: 12) {
            cardHeader(
                emoji: "❓",
                title: "Unassigned",
                count: items.count,
                collapsed: collapsed
            ) {
                toggleCollapsed(Self.unassignedKey)
            }

            if !collapsed {
                if isGallery {
                    galleryGrid(items)
                } else {
                    ForEach(items) { item in
                        itemRow(item, tag: categoryTag(for: item))
                    }
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Category Card

    private func categoryCard(_ category: Category, items: [Item]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(category.name)
                    .font(.headline)
                Spacer()
                Text("\(items.count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule())
            }

            if items.isEmpty {
                Text("No items here")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 4)
            } else if isGallery {
                galleryGrid(items)
            } else {
                ForEach(items) { item in
                    itemRow(item, tag: locationTag(for: item))
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Uncategorized Card

    private func uncategorizedCard(items: [Item]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Uncategorized")
                    .font(.headline)
                Spacer()
                Text("\(items.count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule())
            }

            if isGallery {
                galleryGrid(items)
            } else {
                ForEach(items) { item in
                    itemRow(item, tag: locationTag(for: item))
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Gallery Grid

    private func galleryGrid(_ items: [Item]) -> some View {
        ItemGalleryGrid(
            items: items,
            isMisplaced: { viewModel.isMisplaced($0) },
            kind: .location,
            columns: horizontalSizeClass == .regular ? galleryColumns : 2,
            onTap: { detailItem = $0 },
            onAddPhoto: { item in
                photoSourceItem = item
                showPhotoSource = true
            },
            onDoubleTap: { previewItem = $0 },
            tileMenu: { item in
                itemMenuItems(item)
            }
        )
    }

    @ViewBuilder
    private func itemMenuItems(_ item: Item) -> some View {
        PutBackMenuButton(item: item, viewModel: viewModel)
        Button {
            selectedItem = item
        } label: {
            Label("Move to Location", systemImage: "arrow.right.circle")
        }
        Button {
            photoSourceItem = item
            showPhotoSource = true
        } label: {
            Label("Change Photo", systemImage: "camera")
        }
        Button {
            detailItem = item
        } label: {
            Label("Details", systemImage: "info.circle")
        }
        if viewModel.canManageSharing(of: item) {
            Button(role: .destructive) {
                itemToDelete = item
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Item Row

    private func itemRow(_ item: Item, tag: some View) -> some View {
        itemRowBody(item, tag: tag)
            .itemTapGestures(
                previewEnabled: item.hasLocationPhoto,
                onPreview: { previewItem = item },
                onOpen: { detailItem = item }
            )
    }

    private func itemRowBody(_ item: Item, tag: some View) -> some View {
        HStack {
            itemThumbnail(item)

            VStack(alignment: .leading) {
                Text(item.name)
                    .font(.subheadline)
                if let notes = item.notes {
                    Text(notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let changedAt = item.locationChangedAt {
                    Text("Stored \(changedAt, format: .relative(presentation: .named))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()
            if viewModel.isMisplaced(item) {
                MisplacedBadge(iconOnly: true)
            }
            if !item.pairedTags.isEmpty {
                NFCBadge(iconOnly: true)
            }
            tag

            Button {
                selectedItem = item
            } label: {
                Image(systemName: "arrow.right.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityAddTraits(.isButton)
        .contextMenu {
            itemMenuItems(item)
        }
    }

    @ViewBuilder
    private func itemThumbnail(_ item: Item) -> some View {
        if item.hasLocationPhoto {
            PhotoView(item: item, kind: .location, size: .thumbnail(84)) { image in
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: 28, height: 28)
                    .clipShape(Circle())
            } placeholder: {
                Image(systemName: "photo.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.tertiary)
            }
            .onTapGesture {
                previewItem = item
            }
        } else {
            Image(systemName: "photo.circle.fill")
                .font(.system(size: 24))
                .foregroundStyle(.tertiary)
                .onTapGesture {
                    photoSourceItem = item
                    showPhotoSource = true
                }
        }
    }

    // MARK: - Tags

    private func categoryTag(for item: Item) -> some View {
        Group {
            if let category = viewModel.category(for: item) {
                Text(category.name)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule())
            }
        }
    }

    private func locationTag(for item: Item) -> some View {
        Group {
            if let location = viewModel.location(for: item) {
                HStack(spacing: 4) {
                    Text(location.emoji ?? "📍")
                        .font(.caption)
                    Text(location.name)
                        .font(.caption)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial, in: Capsule())
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Welcome to MyStuff", systemImage: "shippingbox.fill")
        } description: {
            Text("Start by adding some locations and items.\nYou'll never lose track of your stuff again!")
        }
    }
}

// MARK: - Move Item Sheet

struct MoveItemSheet: View {
    let item: Item
    let viewModel: StuffViewModel
    let onMove: (String?) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var showingScanner = false
    @State private var unknownScan = false
    @State private var pendingMove: (locationId: String, location: Location, missing: [String])?

    var body: some View {
        // Detents are ignored in regular width (iPad form sheet); use page sizing there instead.
        if horizontalSizeClass == .regular {
            content.presentationSizing(.page)
        } else {
            content.presentationDetents([.medium])
        }
    }

    /// Shared by both scanners: QR and NFC resolve to the same target.
    private func selectScanned(_ target: AppLink.Target) {
        let locationId = target.entityId
        if viewModel.locations.contains(where: { $0.id == locationId }) {
            selectMove(toLocationId: locationId)
        } else {
            unknownScan = true
        }
    }

    private func selectMove(toLocationId locationId: String?) {
        // Unassigned or non-shared item → move straight away.
        let liveItem = viewModel.items.first(where: { $0.id == item.id }) ?? item
        let itemMembers = viewModel.sharedMembers(of: liveItem)
        guard let locationId,
              viewModel.canManageSharing(of: liveItem),
              !itemMembers.isEmpty,
              let location = viewModel.locations.first(where: { $0.id == locationId }) else {
            onMove(locationId)
            dismiss()
            return
        }
        let missing = viewModel.membersMissing(from: location, forItemMembers: itemMembers)
        if missing.isEmpty {
            onMove(locationId)
            dismiss()
        } else {
            pendingMove = (locationId, location, missing)
        }
    }

    private var content: some View {
        NavigationStack {
            List {
                if QRScannerView.isSupported || CoreNFCService.readingAvailable {
                    Section {
                        if QRScannerView.isSupported {
                            Button {
                                showingScanner = true
                            } label: {
                                Label("Scan location QR", systemImage: "qrcode.viewfinder")
                            }
                        }

                        NFCScanButton(accepts: .location) { target in
                            selectScanned(target)
                        } label: { scanning in
                            Label(scanning ? "Hold near tag…" : "Scan location NFC tag",
                                  systemImage: "wave.3.right")
                        }
                    }
                }

                Section("Move \"\(item.name)\" to…") {
                    Button {
                        selectMove(toLocationId: nil)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "questionmark.circle")
                                .foregroundStyle(.secondary)
                            Text("Unassigned")
                            Spacer()
                            if item.locationId == nil { LocationPickerCheckmark() }
                        }
                    }
                    .tint(.primary)
                }

                LocationTreeSections(viewModel: viewModel, selectedId: item.locationId) { locationId in
                    selectMove(toLocationId: locationId)
                }
            }
            .navigationTitle("Move Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showingScanner) {
                QRScannerSheet(accepts: .location) { target in
                    selectScanned(target)
                }
            }
            .alert("Location not found", isPresented: $unknownScan) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("That code points to a location that no longer exists.")
            }
            .confirmationDialog(
                pendingMove.map { "\"\(item.name)\" is shared, but \($0.location.name) isn't." } ?? "",
                isPresented: Binding(
                    get: { pendingMove != nil },
                    set: { if !$0 { pendingMove = nil } }
                ),
                titleVisibility: .visible
            ) {
                if let pending = pendingMove {
                    Button("Share \(pending.location.name) too") {
                        Task {
                            await viewModel.addMembers(pending.missing, toLocation: pending.location)
                            onMove(pending.locationId)
                            pendingMove = nil
                            dismiss()
                        }
                    }
                    Button("Make item private", role: .destructive) {
                        let liveItem = viewModel.items.first(where: { $0.id == item.id }) ?? item
                        Task {
                            await viewModel.makeItemPrivate(liveItem)
                            onMove(pending.locationId)
                            pendingMove = nil
                            dismiss()
                        }
                    }
                    Button("Cancel", role: .cancel) { pendingMove = nil }
                }
            }
        }
    }
}

#Preview {
    ContentView(authService: AuthService())
}
