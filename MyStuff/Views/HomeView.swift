import PhotosUI
import SwiftUI

struct HomeView: View {
    @Bindable var viewModel: StuffViewModel
    var onProfileTap: (() -> Void)? = nil
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
    @State private var filterCategoryIds: Set<String> = []
    @State private var filterLocationIds: Set<String> = []
    @State private var showFilters = false
    @AppStorage("homeViewMode") private var viewMode = "list"

    private var isGallery: Bool { viewMode == "gallery" }

    /// Items matching current search + filters
    private var homeFilteredItems: Set<String> {
        var result = viewModel.items
        if !homeSearchText.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(homeSearchText)
                || ($0.notes?.localizedCaseInsensitiveContains(homeSearchText) ?? false)
            }
        }
        if !filterCategoryIds.isEmpty {
            result = result.filter { filterCategoryIds.contains($0.categoryId ?? "") }
        }
        if !filterLocationIds.isEmpty {
            // Include items at selected locations OR any of their descendants
            let allIds = filterLocationIds.reduce(into: filterLocationIds) { acc, id in
                acc.formUnion(viewModel.allDescendantIds(of: id))
            }
            result = result.filter { allIds.contains($0.locationId ?? "") }
        }
        return Set(result.map(\.id))
    }

    private var isFiltering: Bool {
        !homeSearchText.isEmpty || !filterCategoryIds.isEmpty || !filterLocationIds.isEmpty
    }

    private func filtered(_ items: [Item]) -> [Item] {
        guard isFiltering else { return items }
        return items.filter { homeFilteredItems.contains($0.id) }
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
                        }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        withAnimation { viewMode = isGallery ? "list" : "gallery" }
                    } label: {
                        Image(systemName: isGallery ? "list.bullet" : "square.grid.2x2")
                    }
                }
            }
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
                .presentationDetents([.medium])
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
            .sheet(item: $previewItem) { item in
                LocationPhotoPreviewSheet(item: item, viewModel: viewModel)
                    .presentationDetents([.medium, .large])
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

                filterBar

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

    // MARK: - Filter Bar

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation { showFilters.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "line.3.horizontal.decrease")
                    Text("Filters")
                        .font(.subheadline)
                    if isFiltering {
                        let count = (filterCategoryIds.isEmpty ? 0 : 1) + (filterLocationIds.isEmpty ? 0 : 1)
                        if count > 0 {
                            Text("\(count)")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor, in: Capsule())
                                .foregroundStyle(.white)
                        }
                    }
                    Spacer()
                    Image(systemName: showFilters ? "chevron.up" : "chevron.down")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            if showFilters {
                // Category filters
                if !viewModel.categories.isEmpty {
                    Text("Categories")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(viewModel.categories) { category in
                                filterChip(
                                    label: category.name,
                                    isSelected: filterCategoryIds.contains(category.id)
                                ) {
                                    if filterCategoryIds.contains(category.id) {
                                        filterCategoryIds.remove(category.id)
                                    } else {
                                        filterCategoryIds.insert(category.id)
                                    }
                                }
                            }
                        }
                    }
                }

                // Location filters
                if !viewModel.locations.isEmpty {
                    Text("Locations")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(viewModel.flattenedLocationTree(), id: \.location.id) { entry in
                                filterChip(
                                    label: String(repeating: "  ", count: entry.depth) + (entry.location.emoji ?? "📍") + " " + entry.location.name,
                                    isSelected: filterLocationIds.contains(entry.location.id)
                                ) {
                                    if filterLocationIds.contains(entry.location.id) {
                                        filterLocationIds.remove(entry.location.id)
                                    } else {
                                        filterLocationIds.insert(entry.location.id)
                                    }
                                }
                            }
                        }
                    }
                }

                if isFiltering {
                    Button("Clear All") {
                        filterCategoryIds.removeAll()
                        filterLocationIds.removeAll()
                        homeSearchText = ""
                    }
                    .font(.caption)
                }
            }
        }
    }

    private func filterChip(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor.opacity(0.2) : .clear, in: Capsule())
                .overlay(Capsule().stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(location.emoji ?? "📍")
                    .font(.title2)
                Text(location.name)
                    .font(.headline)
                Spacer()
                Text("\(totalCount)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule())
            }

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
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
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
        return HStack(spacing: 4) {
            Text(sublocation.emoji ?? "📍")
                .font(.caption)
            Text(relativePath)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }

    // MARK: - Unassigned Location Card

    private func unassignedLocationCard(items: [Item]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("❓")
                    .font(.title2)
                Text("Unassigned")
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
                    itemRow(item, tag: categoryTag(for: item))
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
            kind: .location,
            onTap: { detailItem = $0 },
            onAddPhoto: { item in
                photoSourceItem = item
                showPhotoSource = true
            },
            tileMenu: { item in
                itemMenuItems(item)
            }
        )
    }

    @ViewBuilder
    private func itemMenuItems(_ item: Item) -> some View {
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
    }

    // MARK: - Item Row

    private func itemRow(_ item: Item, tag: some View) -> some View {
        HStack {
            itemThumbnail(item)

            Button {
                detailItem = item
            } label: {
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
            }
            .buttonStyle(.plain)

            Spacer()
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

    var body: some View {
        NavigationStack {
            List {
                Section("Move \"\(item.name)\" to…") {
                    Button {
                        onMove(nil)
                        dismiss()
                    } label: {
                        Label("Unassigned", systemImage: "questionmark.circle")
                    }
                    .tint(item.locationId == nil ? .accentColor : .primary)

                    ForEach(viewModel.flattenedLocationTree(), id: \.location.id) { entry in
                        Button {
                            onMove(entry.location.id)
                            dismiss()
                        } label: {
                            Label {
                                Text(entry.location.name)
                            } icon: {
                                Text(entry.location.emoji ?? "📍")
                            }
                        }
                        .tint(item.locationId == entry.location.id ? .accentColor : .primary)
                        .padding(.leading, CGFloat(entry.depth) * 20)
                    }
                }
            }
            .navigationTitle("Move Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Location Photo Preview Sheet

struct LocationPhotoPreviewSheet: View {
    let item: Item
    @Bindable var viewModel: StuffViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let liveItem = viewModel.items.first(where: { $0.id == item.id }) ?? item
        NavigationStack {
            Group {
                if liveItem.hasLocationPhoto {
                    PhotoView(item: liveItem, kind: .location, size: .full) { image in
                        image
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .padding()
                    } placeholder: {
                        ProgressView()
                    }
                } else {
                    ContentUnavailableView("No photo", systemImage: "photo")
                }
            }
            .navigationTitle(item.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    ContentView(authService: AuthService())
}
