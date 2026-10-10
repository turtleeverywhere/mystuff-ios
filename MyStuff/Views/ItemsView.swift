import PhotosUI
import SwiftUI

struct ItemsView: View {
    @Bindable var viewModel: StuffViewModel
    @State private var showingAddSheet = false
    @State private var editingItem: Item?
    @State private var movingItem: Item?
    @State private var itemToDelete: Item?
    @State private var photoSourceItem: Item?
    @State private var showPhotoSource = false
    @State private var previewItem: Item?
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isUploading = false
    @State private var filter = ItemFilter()
    @State private var showFilters = false
    @AppStorage("itemsViewMode") private var viewMode = "list"
    @AppStorage("galleryColumns") private var galleryColumns = 2
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isGallery: Bool { viewMode == "gallery" }

    /// `viewModel.filteredItems` has already applied the search field, so the
    /// filter runs with an empty query to avoid searching twice.
    private var visibleItems: [Item] {
        filter.apply(to: viewModel.filteredItems, searchText: "", viewModel: viewModel)
    }

    private var isFiltering: Bool {
        !viewModel.searchText.isEmpty || filter.isActive
    }

    private var putBackTargets: [Item] {
        guard filter.misplacedOnly else { return [] }
        return visibleItems
    }

    private var filterBar: some View {
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
                viewModel.searchText = ""
            }
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.items.isEmpty {
                    ProgressView("Loading your items…")
                } else if viewModel.items.isEmpty {
                    emptyState
                } else if isGallery {
                    itemsGallery
                } else {
                    itemsList
                }
            }
            .background(LinearGradient.appBackground)
            .navigationTitle("Items")
            .searchable(text: $viewModel.searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search items...")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddSheet = true
                    } label: {
                        Label("Add item", systemImage: "plus")
                    }
                    .accessibilityLabel("Add item")
                }
                if isGallery && horizontalSizeClass == .regular {
                    ToolbarItem(placement: .topBarTrailing) {
                        GalleryColumnSlider()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation(reduceMotion ? nil : .snappy) { viewMode = isGallery ? "list" : "gallery" }
                    } label: {
                        Image(systemName: isGallery ? "list.bullet" : "square.grid.2x2")
                    }
                    .accessibilityLabel(isGallery ? "Show list" : "Show gallery")
                }
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        CategoryManagementView(viewModel: viewModel)
                    } label: {
                        Image(systemName: "folder")
                    }
                    .accessibilityLabel("Manage categories")
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                ItemFormSheet(
                    viewModel: viewModel,
                    onSave: { result in
                        Task {
                            await viewModel.addItem(
                                id: result.id,
                                name: result.name,
                                notes: result.notes,
                                locationId: result.locationId,
                                categoryId: result.categoryId,
                                homeLocationId: result.homeLocationId
                            )
                            guard let newItem = viewModel.items.first(where: { $0.id == result.id }) else { return }
                            if let data = result.itemPhotoData {
                                await viewModel.setItemPhoto(for: newItem, imageData: data)
                            }
                            if let data = result.locationPhotoData {
                                let refreshed = viewModel.items.first(where: { $0.id == result.id }) ?? newItem
                                await viewModel.setPhoto(for: refreshed, imageData: data)
                            }
                            for uid in result.shareWith {
                                await viewModel.shareItem(newItem, withFriend: uid)
                            }
                            await viewModel.applyStagedTags(result.nfcTags, to: .item(result.id))
                        }
                    }
                )
            }
            .sheet(item: $editingItem) { item in
                ItemFormSheet(
                    item: item,
                    viewModel: viewModel,
                    onSave: { result in
                        var updated = item
                        updated.name = result.name
                        updated.notes = result.notes
                        updated.locationId = result.locationId
                        updated.homeLocationId = result.homeLocationId
                        updated.categoryId = result.categoryId
                        Task {
                            await viewModel.updateItem(updated)
                            if let data = result.itemPhotoData {
                                await viewModel.setItemPhoto(for: updated, imageData: data)
                            }
                            if let data = result.locationPhotoData {
                                let refreshed = viewModel.items.first(where: { $0.id == updated.id }) ?? updated
                                await viewModel.setPhoto(for: refreshed, imageData: data)
                            }
                            await viewModel.applyStagedTags(result.nfcTags, to: .item(item.id))
                        }
                    }
                )
            }
            .confirmItemDeletion($itemToDelete, viewModel: viewModel)
            .sheet(item: $movingItem) { item in
                MoveItemSheet(
                    item: item,
                    viewModel: viewModel,
                    onMove: { locationId in
                        Task { await viewModel.moveItem(item, toLocationId: locationId) }
                    }
                )
            }
            .fullScreenCover(item: $previewItem) { item in
                PhotoPreviewViewer(item: item, kind: .item, viewModel: viewModel)
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
                        isUploading = true
                        await viewModel.setItemPhoto(for: item, imageData: data)
                        isUploading = false
                        photoSourceItem = nil
                    }
                }
                .ignoresSafeArea()
            }
            .onChange(of: selectedPhoto) {
                guard let selectedPhoto, let item = photoSourceItem else { return }
                Task {
                    isUploading = true
                    if let data = try? await selectedPhoto.loadTransferable(type: Data.self) {
                        await viewModel.setItemPhoto(for: item, imageData: data)
                    }
                    isUploading = false
                    self.selectedPhoto = nil
                    photoSourceItem = nil
                }
            }
        }
        .containerBackground(LinearGradient.appBackground, for: .navigation)
    }

    // MARK: - Items List

    private var itemsList: some View {
        List {
            Section {
                AppSectionHeading(title: "Your collection", subtitle: "\(visibleItems.count) of \(viewModel.items.count) items")
                    .listRowBackground(Color.clear)
                filterBar
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
            }

            if visibleItems.isEmpty {
                noMatchesState
                    .listRowBackground(Color.clear)
            } else {
                ForEach(visibleItems) { item in
                    itemRow(item)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
    }

    private func itemRow(_ item: Item) -> some View {
        itemRowBody(item)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens item editor")
            .itemTapGestures(
                previewEnabled: item.hasItemPhoto,
                onPreview: { previewItem = item },
                onOpen: { editingItem = item }
            )
    }

    private func itemRowBody(_ item: Item) -> some View {
        HStack(alignment: .top, spacing: 12) {
            itemPhotoCircle(item)
            VStack(alignment: .leading, spacing: 6) {
                Text(item.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.appText)
                    .fixedSize(horizontal: false, vertical: true)
                if let notes = item.notes, !notes.isEmpty {
                    Text(notes).font(.subheadline).foregroundStyle(Color.appTertiary).lineLimit(2)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        locationBadge(for: item)
                        categoryBadge(for: item)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    VStack(alignment: .leading, spacing: 6) {
                        locationBadge(for: item)
                        categoryBadge(for: item)
                    }
                }
                HStack(spacing: 8) {
                    if viewModel.isMisplaced(item) { MisplacedBadge() }
                    if !item.pairedTags.isEmpty { NFCBadge(iconOnly: true) }
                    sharedBadge(for: item)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                .foregroundStyle(Color.appTertiary).accessibilityHidden(true)
                .padding(.top, 12)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .accessibilityAddTraits(.isButton)
        .listRowBackground(Color.appSurface)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) { itemToDelete = item } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .contextMenu { itemMenuItems(item) }
    }

    // MARK: - Items Gallery

    private var itemsGallery: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                AppSectionHeading(title: "Your collection", subtitle: "\(visibleItems.count) of \(viewModel.items.count) items")
                filterBar

                if visibleItems.isEmpty {
                    noMatchesState
                } else {
                    ItemGalleryGrid(
                        items: visibleItems,
                        isMisplaced: { viewModel.isMisplaced($0) },
                        kind: .item,
                        columns: dynamicTypeSize.isAccessibilitySize ? 1 : (horizontalSizeClass == .regular ? galleryColumns : 2),
                        onTap: { editingItem = $0 },
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
            }
            .padding(16)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - Shared Menu

    @ViewBuilder
    private func itemMenuItems(_ item: Item) -> some View {
        if item.hasItemPhoto {
            Button { previewItem = item } label: { Label("Preview photo", systemImage: "photo") }
        }
        PutBackMenuButton(item: item, viewModel: viewModel)
        Button {
            movingItem = item
        } label: {
            Label("Move to Location", systemImage: "arrow.right.circle")
        }
        Button {
            editingItem = item
        } label: {
            Label("Edit", systemImage: "pencil")
        }
        Button {
            photoSourceItem = item
            showPhotoSource = true
        } label: {
            Label("Change Photo", systemImage: "camera")
        }
        Button(role: .destructive) {
            itemToDelete = item
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    // MARK: - Item Photo Circle

    @ViewBuilder
    private func itemPhotoCircle(_ item: Item) -> some View {
        let liveItem = viewModel.items.first(where: { $0.id == item.id }) ?? item
        if liveItem.hasItemPhoto {
            PhotoView(item: liveItem, kind: .item, size: .thumbnail(120)) { image in
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: 48, height: 48)
                    .clipShape(Circle())
            } placeholder: {
                photoPlaceholderCircle
            }
            .onTapGesture {
                previewItem = liveItem
            }
        } else {
            photoPlaceholderCircle
                .onTapGesture {
                    photoSourceItem = item
                    showPhotoSource = true
                }
        }
    }

    private var photoPlaceholderCircle: some View {
        Image(systemName: "photo.circle.fill")
            .font(.title2)
            .foregroundStyle(Color.appPrimary)
            .frame(width: 48, height: 48)
            .background(Color.appSurfaceMuted, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Location Badge

    private func locationBadge(for item: Item) -> some View {
        Group {
            if let location = viewModel.location(for: item) {
                HStack(spacing: 4) {
                    Image(systemName: "mappin.and.ellipse").accessibilityHidden(true)
                    Text(location.name)
                        .font(.caption)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.appSurfaceMuted, in: Capsule())
            } else {
                Text("Unassigned")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.appSurfaceMuted, in: Capsule())
            }
        }
    }

    // MARK: - Shared Badge

    @ViewBuilder
    private func sharedBadge(for item: Item) -> some View {
        if viewModel.isSharedWithMe(item) {
            SharedBadge(ownerName: viewModel.friend(forUid: item.ownerId ?? "")?.displayName)
        } else if viewModel.isShared(item) {
            SharedBadge()
        }
    }

    // MARK: - Category Badge

    private func categoryBadge(for item: Item) -> some View {
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

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Items Yet", systemImage: "shippingbox")
        } description: {
            Text("Add the things you want to keep track of, then give each one a location.")
        } actions: {
            Button("Add Item") {
                showingAddSheet = true
            }
            .buttonStyle(AppPrimaryButtonStyle())
        }
    }

    /// Shown when items exist but none survive the active filters — the full-empty
    /// `emptyState` would wrongly suggest the user has no items at all.
    private var noMatchesState: some View {
        ContentUnavailableView {
            Label("No items match these filters", systemImage: "line.3.horizontal.decrease")
        } description: {
            Text("Try another search or clear your filters.")
        } actions: {
            Button("Clear search & filters") { filter = ItemFilter(); viewModel.searchText = "" }
                .buttonStyle(.bordered)
        }
    }
}

// MARK: - Item Form Sheet

/// Everything `ItemFormSheet` hands back on Save. Bundled rather than passed as
/// positional closure arguments — the list had already reached seven.
struct ItemFormResult {
    let id: String
    let name: String
    let notes: String?
    let locationId: String?
    let homeLocationId: String?
    let categoryId: String?
    let itemPhotoData: Data?
    let locationPhotoData: Data?
    let shareWith: Set<String>
    let nfcTags: [NFCTag]
}

struct ItemFormSheet: View {
    let item: Item?
    @Bindable var viewModel: StuffViewModel
    let onSave: (ItemFormResult) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var notes: String
    @State private var selectedLocationId: String
    @State private var selectedHomeLocationId: String
    @State private var selectedCategoryId: String
    @State private var showingNewCategory = false
    @State private var newCategoryName = ""
    @State private var photoData: Data?
    @State private var locationPhotoData: Data?
    @State private var useSameForLocation: Bool
    @State private var photoTarget: PhotoTarget = .item
    @State private var showPhotoSource = false
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var shareWith: Set<String>
    @State private var showLocationScanner = false
    @State private var unknownLocationScan = false
    /// Pre-allocated so codes can be paired and printed against a draft that
    /// has not been saved yet. MUST be `@State`: SwiftUI recreates the view
    /// struct on every render, so a plain `let` would mint a fresh UUID each
    /// pass and a paired tag would point at an id that never reaches Firestore.
    @State private var draftId: String
    /// Tag edits are buffered here and applied on Save, matching how the rest
    /// of this form treats Cancel.
    @State private var stagedTags: [NFCTag]
    @State private var showCodes = false

    private enum PhotoTarget { case item, location }

    private let unassignedSentinel = "__unassigned__"
    private let noHomeSentinel = "__nohome__"
    private let uncategorizedSentinel = "__uncategorized__"

    /// Live item from the view model (reflects immediate privacy changes), or nil in create mode.
    private var liveItem: Item? {
        guard let item else { return nil }
        return viewModel.items.first(where: { $0.id == item.id }) ?? item
    }

    init(
        item: Item? = nil,
        initialLocationId: String? = nil,
        viewModel: StuffViewModel,
        onSave: @escaping (ItemFormResult) -> Void
    ) {
        self.item = item
        self.viewModel = viewModel
        self.onSave = onSave
        _name = State(initialValue: item?.name ?? "")
        _notes = State(initialValue: item?.notes ?? "")
        _selectedLocationId = State(initialValue: item?.locationId ?? initialLocationId ?? "__unassigned__")
        // A home location that has since been deleted would leave the picker on a tag
        // no row carries: it renders blank and Save writes the stale id back.
        let storedHome = item?.homeLocationId
        let resolvedHome = viewModel.locations.contains { $0.id == storedHome } ? storedHome : nil
        _selectedHomeLocationId = State(initialValue: resolvedHome ?? "__nohome__")
        _selectedCategoryId = State(initialValue: item?.categoryId ?? "__uncategorized__")
        _useSameForLocation = State(initialValue: item == nil)
        _shareWith = State(initialValue: [])
        _draftId = State(initialValue: item?.id ?? UUID().uuidString)
        _stagedTags = State(initialValue: item?.pairedTags ?? [])
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Item name").font(.subheadline.weight(.medium)).foregroundStyle(Color.appTertiary)
                        TextField("e.g. Spare keys", text: $name)
                            .accessibilityLabel("Item name")
                    }
                    .padding(.vertical, 4)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Notes (optional)").font(.subheadline.weight(.medium)).foregroundStyle(Color.appTertiary)
                        TextField("Add a description or useful details", text: $notes, axis: .vertical)
                            .accessibilityLabel("Notes, optional")
                    }
                    .padding(.vertical, 4)
                        .lineLimit(3...6)
                }

                Section("Item Photo") {
                    if let photoData, let uiImage = UIImage(data: photoData) {
                        HStack {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 80, height: 80)
                                .clipShape(RoundedRectangle(cornerRadius: 10))

                            Spacer()

                            Button(role: .destructive) {
                                self.photoData = nil
                            } label: {
                                Image(systemName: "trash")
                            }
                        }
                    } else if let item, item.hasItemPhoto {
                        HStack {
                            PhotoView(item: item, kind: .item, size: .thumbnail(240)) { image in
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 80, height: 80)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            } placeholder: {
                                ProgressView()
                                    .frame(width: 80, height: 80)
                            }
                            Spacer()
                            Text("Current photo")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button {
                        photoTarget = .item
                        showPhotoSource = true
                    } label: {
                        Label(photoData != nil || (item?.hasItemPhoto ?? false) ? "Change Photo" : "Add Photo", systemImage: "camera")
                    }
                }

                Section("Location Photo") {
                    Toggle("Use item photo", isOn: $useSameForLocation)

                    if !useSameForLocation {
                        if let locationPhotoData, let uiImage = UIImage(data: locationPhotoData) {
                            HStack {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 80, height: 80)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))

                                Spacer()

                                Button(role: .destructive) {
                                    self.locationPhotoData = nil
                                } label: {
                                    Image(systemName: "trash")
                                }
                            }
                        } else if let item, item.hasLocationPhoto {
                            HStack {
                                PhotoView(item: item, kind: .location, size: .thumbnail(240)) { image in
                                    image
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 80, height: 80)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                } placeholder: {
                                    ProgressView()
                                        .frame(width: 80, height: 80)
                                }
                                Spacer()
                                Text("Current photo")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Button {
                            photoTarget = .location
                            showPhotoSource = true
                        } label: {
                            Label(locationPhotoData != nil || (item?.hasLocationPhoto ?? false) ? "Change Photo" : "Add Photo", systemImage: "camera")
                        }
                    }
                }

                Section("Location") {
                    LocationPickerRow(
                        viewModel: viewModel,
                        label: "Location",
                        pickerTitle: "Choose Location",
                        selection: Binding(
                            get: { selectedLocationId == unassignedSentinel ? nil : selectedLocationId },
                            set: { selectedLocationId = $0 ?? unassignedSentinel }
                        )
                    )

                    if QRScannerView.isSupported {
                        Button {
                            showLocationScanner = true
                        } label: {
                            Label("Scan Location QR", systemImage: "qrcode.viewfinder")
                        }
                    }

                    NFCScanButton(accepts: .location) { target in
                        selectScannedLocation(target)
                    } label: { scanning in
                        Label(
                            scanning ? "Hold near tag…" : "Scan Location NFC Tag",
                            systemImage: "wave.3.right"
                        )
                    }

                    LocationPickerRow(
                        viewModel: viewModel,
                        label: "Supposed location",
                        pickerTitle: "Supposed Location",
                        emptyLabel: "None",
                        selection: Binding(
                            get: { selectedHomeLocationId == noHomeSentinel ? nil : selectedHomeLocationId },
                            set: { selectedHomeLocationId = $0 ?? noHomeSentinel }
                        )
                    )

                    Button("Same as current location") {
                        selectedHomeLocationId = selectedLocationId
                    }
                    .disabled(selectedLocationId == unassignedSentinel || selectedHomeLocationId == selectedLocationId)
                }

                Section("Category") {
                    Picker("Category", selection: $selectedCategoryId) {
                        Text("Uncategorized").tag(uncategorizedSentinel)
                        ForEach(viewModel.categories) { category in
                            Text(category.name).tag(category.id)
                        }
                    }

                    Button("New Category...") {
                        showingNewCategory = true
                    }
                }

                codesSection

                // Edit-only, owner-only. Acts immediately (reuses setItemPrivate,
                // which resets to private on enable and no-ops for non-owners).
                if let liveItem, viewModel.canManageSharing(of: liveItem) {
                    Section {
                        Toggle("Always private", isOn: Binding(
                            get: { liveItem.isPrivate == true },
                            set: { newValue in
                                Task { await viewModel.setItemPrivate(liveItem, newValue) }
                            }
                        ))
                    } footer: {
                        Text("Excluded from automatic sharing.")
                    }
                }

                if item == nil && !viewModel.friends.isEmpty {
                    Section("Share with") {
                        ForEach(viewModel.friends) { friend in
                            Button {
                                if shareWith.contains(friend.uid) { shareWith.remove(friend.uid) }
                                else { shareWith.insert(friend.uid) }
                            } label: {
                                HStack {
                                    Text(friend.displayName).foregroundStyle(.primary)
                                    Spacer()
                                    if shareWith.contains(friend.uid) {
                                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle(item == nil ? "New Item" : "Edit Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let locationId = selectedLocationId == unassignedSentinel ? nil : selectedLocationId
                        let homeLocationId = selectedHomeLocationId == noHomeSentinel ? nil : selectedHomeLocationId
                        let categoryId = selectedCategoryId == uncategorizedSentinel ? nil : selectedCategoryId
                        let resolvedLocationData: Data? = useSameForLocation ? photoData : locationPhotoData
                        onSave(ItemFormResult(
                            id: draftId,
                            name: name,
                            notes: notes.isEmpty ? nil : notes,
                            locationId: locationId,
                            homeLocationId: homeLocationId,
                            categoryId: categoryId,
                            itemPhotoData: photoData,
                            locationPhotoData: resolvedLocationData,
                            shareWith: shareWith,
                            nfcTags: stagedTags
                        ))
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .alert("New Category", isPresented: $showingNewCategory) {
                TextField("Category name", text: $newCategoryName)
                Button("Add") {
                    let trimmed = newCategoryName.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty {
                        Task {
                            if let category = await viewModel.addCategory(name: trimmed) {
                                selectedCategoryId = category.id
                            }
                        }
                        newCategoryName = ""
                    }
                }
                Button("Cancel", role: .cancel) {
                    newCategoryName = ""
                }
            }
            .sheet(isPresented: $showPhotoSource) {
                PhotoSourceSheet(
                    onCamera: { showCamera = true },
                    onLibrary: { showPhotoPicker = true }
                )
            }
            .sheet(isPresented: $showLocationScanner) {
                QRScannerSheet(accepts: .location) { target in
                    selectScannedLocation(target)
                }
            }
            .alert("Location not found", isPresented: $unknownLocationScan) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("That code points to a location that no longer exists.")
            }
            .sheet(isPresented: $showCodes) {
                CodesSheet(
                    subject: QRSubject(target: .item(draftId), name: name, icon: "📦"),
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
            .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhoto, matching: .images)
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { data in
                    assignPhotoData(data)
                }
                .ignoresSafeArea()
            }
            .onChange(of: selectedPhoto) {
                guard let selectedPhoto else { return }
                Task {
                    if let data = try? await selectedPhoto.loadTransferable(type: Data.self) {
                        assignPhotoData(data)
                    }
                    self.selectedPhoto = nil
                }
            }
        }
    }

    /// Shared by both scanners: QR and NFC resolve to the same target.
    private func selectScannedLocation(_ target: AppLink.Target) {
        let locationId = target.entityId
        if viewModel.locations.contains(where: { $0.id == locationId }) {
            selectedLocationId = locationId
        } else {
            unknownLocationScan = true
        }
    }

    private func assignPhotoData(_ data: Data) {
        switch photoTarget {
        case .item: photoData = data
        case .location: locationPhotoData = data
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
            if item == nil {
                Text("Codes activate when you save this item.")
            }
        }
    }
}

#Preview {
    ContentView(authService: AuthService())
}
