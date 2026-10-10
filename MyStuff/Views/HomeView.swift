import PhotosUI
import SwiftUI

struct HomeView: View {
    @Bindable var viewModel: StuffViewModel
    var onProfileTap: (() -> Void)? = nil
    var pendingRequestCount: Int = 0
    @State private var showingAddSheet = false
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
                if viewModel.isLoading && viewModel.items.isEmpty {
                    ProgressView("Finding your stuff…")
                } else if viewModel.items.isEmpty && viewModel.locations.isEmpty && viewModel.categories.isEmpty {
                    emptyState
                } else {
                    mainContent
                }
            }
            .background(LinearGradient.appBackground)
            .navigationTitle("My Stuff")
            .searchable(text: $homeSearchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search items")
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
                        .accessibilityLabel(pendingRequestCount > 0 ? "Profile, \(pendingRequestCount) friend requests" : "Profile")
                    }
                }
                if isGallery && horizontalSizeClass == .regular {
                    ToolbarItem(placement: .primaryAction) {
                        GalleryColumnSlider()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { showingAddSheet = true } label: { Label("Add item", systemImage: "plus") }
                        Button { showItemScan = true } label: { Label("Scan items", systemImage: "camera.viewfinder") }
                        Divider()
                        Button { viewMode = isGallery ? "list" : "gallery" } label: {
                            Label(isGallery ? "List view" : "Gallery view", systemImage: isGallery ? "list.bullet" : "square.grid.2x2")
                        }
                        if viewModel.selectedGrouping == .location && !collapsibleKeys.isEmpty {
                            Button {
                                withAnimation(reduceMotion ? nil : .snappy) { toggleAll() }
                            } label: {
                                Label(allCollapsed ? "Expand all locations" : "Collapse all locations",
                                      systemImage: allCollapsed ? "rectangle.expand.vertical" : "rectangle.compress.vertical")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel("View options")
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                ItemFormSheet(viewModel: viewModel) { result in
                    Task {
                        await viewModel.addItem(id: result.id, name: result.name, notes: result.notes,
                                                locationId: result.locationId, categoryId: result.categoryId,
                                                homeLocationId: result.homeLocationId)
                        guard let item = viewModel.items.first(where: { $0.id == result.id }) else { return }
                        if let data = result.itemPhotoData { await viewModel.setItemPhoto(for: item, imageData: data) }
                        if let data = result.locationPhotoData {
                            let refreshed = viewModel.items.first(where: { $0.id == item.id }) ?? item
                            await viewModel.setPhoto(for: refreshed, imageData: data)
                        }
                        for uid in result.shareWith { await viewModel.shareItem(item, withFriend: uid) }
                        await viewModel.applyStagedTags(result.nfcTags, to: .item(result.id))
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
            LazyVStack(spacing: 20) {
                if !isFiltering { overviewCard }
                AppSectionHeading(
                    title: isFiltering ? "Search results" : "Everything in its place",
                    subtitle: isFiltering
                        ? "\(visibleItems.count) of \(viewModel.items.count) items"
                        : "Browse your stuff by location or category."
                )
                if dynamicTypeSize.isAccessibilitySize {
                    groupingPicker.pickerStyle(.menu)
                } else {
                    groupingPicker.pickerStyle(.segmented)
                }

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

                if isFiltering && visibleItems.isEmpty {
                    ContentUnavailableView {
                        Label("No matching items", systemImage: "magnifyingglass")
                    } description: {
                        Text("Try another search or clear your filters.")
                    } actions: {
                        Button("Clear search & filters") { filter = ItemFilter(); homeSearchText = "" }
                            .buttonStyle(.bordered)
                    }
                    .appCard()
                } else {
                    switch viewModel.selectedGrouping {
                    case .location: locationGrouping
                    case .category: categoryGrouping
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var groupingPicker: some View {
        Picker("Group by", selection: $viewModel.selectedGrouping) {
            ForEach(StuffViewModel.GroupingMode.allCases, id: \.self) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
    }

    private var overviewCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            if dynamicTypeSize.isAccessibilitySize {
                Text("Overview").font(.headline)
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(viewModel.items.count) items")
                    Text("\(viewModel.locations.count) locations")
                    Text("\(viewModel.categories.count) categories")
                }
                .font(.body)
                VStack(alignment: .leading, spacing: 12) { overviewActions }
            } else {
                Label("YOUR PERSONAL INVENTORY", systemImage: "shippingbox")
                    .font(.caption.weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(Color.appHeroSecondary)
                Text("Your stuff, at a glance.")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 24) { overviewStats }
                    VStack(alignment: .leading, spacing: 12) { overviewStats }
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { overviewActions }.fixedSize(horizontal: true, vertical: false)
                    VStack(alignment: .leading, spacing: 12) { overviewActions }
                }
            }
            if !viewModel.unassignedItems.isEmpty {
                Label("\(viewModel.unassignedItems.count) items still need a location", systemImage: "mappin.slash")
                    .font(.subheadline)
                    .foregroundStyle(Color.appHeroSecondary)
            }
        }
        .foregroundStyle(Color.appOnHero)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appHero, in: RoundedRectangle(cornerRadius: 28))
    }

    @ViewBuilder private var overviewStats: some View {
        stat(value: viewModel.items.count, label: "Items")
        stat(value: viewModel.locations.count, label: "Locations")
        stat(value: viewModel.categories.count, label: "Categories")
    }

    private func stat(value: Int, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(value)")
                .font(.system(.title2, design: .rounded, weight: .bold))
                .monospacedDigit()
            Text(label).font(.subheadline).foregroundStyle(Color.appHeroSecondary)
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var overviewActions: some View {
        Button { showingAddSheet = true } label: {
            Label("Add item", systemImage: "plus").font(.headline).fixedSize(horizontal: false, vertical: true).padding(.vertical, 4)
        }
        .buttonStyle(.borderedProminent)
        .tint(Color.appOnHero)
        .foregroundStyle(Color.appHero)
        .controlSize(.large)
        Button { showItemScan = true } label: {
            Label("Scan items", systemImage: "camera.viewfinder").font(.headline).fixedSize(horizontal: false, vertical: true).padding(.vertical, 4)
        }
        .buttonStyle(.bordered)
        .tint(Color.appOnHero)
        .controlSize(.large)
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
                emoji: location.emoji,
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
                        .foregroundStyle(Color.appTertiary)
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
        .appCard()
    }

    /// Tappable card header with a collapse chevron.
    private func cardHeader(emoji: String?, title: String, count: Int, collapsed: Bool, onTap: @escaping () -> Void) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : .snappy) { onTap() }
        } label: {
            HStack {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(collapsed ? 0 : 90))
                LocationIcon(emoji: emoji, symbol: title == "Unassigned" ? "tray" : "mappin.and.ellipse")
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.appSurfaceMuted, in: Capsule())
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(collapsed ? "Collapsed" : "Expanded")
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
                Image(systemName: "folder")
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
                emoji: nil,
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
        .appCard()
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
                    .background(Color.appSurfaceMuted, in: Capsule())
            }

            if items.isEmpty {
                Text("No items here")
                    .font(.subheadline)
                    .foregroundStyle(Color.appTertiary)
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
        .appCard()
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
                    .background(Color.appSurfaceMuted, in: Capsule())
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
        .appCard()
    }

    // MARK: - Gallery Grid

    private func galleryGrid(_ items: [Item]) -> some View {
        ItemGalleryGrid(
            items: items,
            isMisplaced: { viewModel.isMisplaced($0) },
            kind: .location,
            columns: dynamicTypeSize.isAccessibilitySize ? 1 : (horizontalSizeClass == .regular ? galleryColumns : 2),
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
        if item.hasLocationPhoto {
            Button { previewItem = item } label: { Label("Preview photo", systemImage: "photo") }
        }
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
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens item details")
            .itemTapGestures(
                previewEnabled: item.hasLocationPhoto,
                onPreview: { previewItem = item },
                onOpen: { detailItem = item }
            )
    }

    private func itemRowBody(_ item: Item, tag: some View) -> some View {
        HStack(alignment: .top, spacing: 12) {
            itemThumbnail(item)
            VStack(alignment: .leading, spacing: 6) {
                Text(item.name).font(.body.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                if let notes = item.notes, !notes.isEmpty {
                    Text(notes).font(.subheadline).foregroundStyle(Color.appTertiary).lineLimit(2)
                }
                tag
                if let changedAt = item.locationChangedAt {
                    Text("Stored \(changedAt, format: .relative(presentation: .named))")
                        .font(.caption).foregroundStyle(Color.appTertiary)
                }
                HStack(spacing: 8) {
                    if viewModel.isMisplaced(item) { MisplacedBadge() }
                    if !item.pairedTags.isEmpty { NFCBadge(iconOnly: true) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button { selectedItem = item } label: {
                Image(systemName: "arrow.right.circle")
                    .font(.title3).foregroundStyle(Color.appPrimary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Move \(item.name)")
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .accessibilityAddTraits(.isButton)
        .contextMenu { itemMenuItems(item) }
    }

    @ViewBuilder
    private func itemThumbnail(_ item: Item) -> some View {
        if item.hasLocationPhoto {
            PhotoView(item: item, kind: .location, size: .thumbnail(84)) { image in
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())
            } placeholder: {
                Image(systemName: "photo.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Color.appPrimary)
                    .frame(width: 44, height: 44)
            }
            .onTapGesture {
                previewItem = item
            }
        } else {
            Image(systemName: "photo.circle.fill")
                .font(.title2)
                .foregroundStyle(Color.appPrimary)
                .frame(width: 44, height: 44)
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
                    .background(Color.appSurfaceMuted, in: Capsule())
            }
        }
    }

    private func locationTag(for item: Item) -> some View {
        Group {
            if let location = viewModel.location(for: item) {
                HStack(spacing: 4) {
                    Text(location.emoji ?? "")
                        .font(.caption)
                    Text(location.name)
                        .font(.caption)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.appSurfaceMuted, in: Capsule())
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Welcome to MyStuff", systemImage: "shippingbox.fill")
        } description: {
            Text("Give your everyday things a place. Add your first item to get started.")
        } actions: {
            Button("Add your first item") { showingAddSheet = true }
                .buttonStyle(AppPrimaryButtonStyle())
                .controlSize(.large)
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
    @State private var searchText = ""
    @State private var unknownScan = false
    @State private var pendingMove: (locationId: String, location: Location, missing: [String])?

    var body: some View {
        // Detents are ignored in regular width (iPad form sheet); use page sizing there instead.
        if horizontalSizeClass == .regular {
            content.presentationSizing(.page)
        } else {
            content.presentationDetents([.medium, .large])
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

                LocationSelectionSections(viewModel: viewModel, selectedId: item.locationId, searchText: searchText) { locationId in
                    selectMove(toLocationId: locationId)
                }
            }
            .safeAreaInset(edge: .top) {
                AppSectionHeading(title: item.name, subtitle: "Choose where to store this item.")
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(Color.appBackground)
            }
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search locations")
            .tint(.appPrimary)
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
