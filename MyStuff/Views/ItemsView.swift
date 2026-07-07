import PhotosUI
import SwiftUI

struct ItemsView: View {
    @Bindable var viewModel: StuffViewModel
    @State private var showingAddSheet = false
    @State private var editingItem: Item?
    @State private var movingItem: Item?
    @State private var photoSourceItem: Item?
    @State private var showPhotoSource = false
    @State private var previewItem: Item?
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isUploading = false
    @AppStorage("itemsViewMode") private var viewMode = "list"

    private var isGallery: Bool { viewMode == "gallery" }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.items.isEmpty {
                    emptyState
                } else if isGallery {
                    itemsGallery
                } else {
                    itemsList
                }
            }
            .navigationTitle("Items")
            .searchable(text: $viewModel.searchText, prompt: "Search items...")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation { viewMode = isGallery ? "list" : "gallery" }
                    } label: {
                        Image(systemName: isGallery ? "list.bullet" : "square.grid.2x2")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        CategoryManagementView(viewModel: viewModel)
                    } label: {
                        Image(systemName: "folder")
                    }
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                ItemFormSheet(
                    viewModel: viewModel,
                    onSave: { name, notes, locationId, categoryId, itemPhotoData, locationPhotoData in
                        Task {
                            await viewModel.addItem(name: name, notes: notes, locationId: locationId, categoryId: categoryId)
                            if let newItem = viewModel.items.last(where: { $0.name == name }) {
                                if let itemPhotoData {
                                    await viewModel.setItemPhoto(for: newItem, imageData: itemPhotoData)
                                }
                                if let locationPhotoData {
                                    let refreshed = viewModel.items.first(where: { $0.id == newItem.id }) ?? newItem
                                    await viewModel.setPhoto(for: refreshed, imageData: locationPhotoData)
                                }
                            }
                        }
                    }
                )
            }
            .sheet(item: $editingItem) { item in
                ItemFormSheet(
                    item: item,
                    viewModel: viewModel,
                    onSave: { name, notes, locationId, categoryId, itemPhotoData, locationPhotoData in
                        var updated = item
                        updated.name = name
                        updated.notes = notes
                        updated.locationId = locationId
                        updated.categoryId = categoryId
                        Task {
                            await viewModel.updateItem(updated)
                            if let itemPhotoData {
                                await viewModel.setItemPhoto(for: updated, imageData: itemPhotoData)
                            }
                            if let locationPhotoData {
                                let refreshed = viewModel.items.first(where: { $0.id == updated.id }) ?? updated
                                await viewModel.setPhoto(for: refreshed, imageData: locationPhotoData)
                            }
                        }
                    }
                )
            }
            .sheet(item: $movingItem) { item in
                MoveItemSheet(
                    item: item,
                    viewModel: viewModel,
                    onMove: { locationId in
                        Task { await viewModel.moveItem(item, toLocationId: locationId) }
                    }
                )
            }
            .sheet(item: $previewItem) { item in
                ItemPhotoPreviewSheet(item: item, viewModel: viewModel)
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
            ForEach(viewModel.filteredItems) { item in
                HStack(spacing: 12) {
                    itemPhotoCircle(item)
                    Button {
                        editingItem = item
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.name)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                if let notes = item.notes, !notes.isEmpty {
                                    Text(notes)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                            categoryBadge(for: item)
                            locationBadge(for: item)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 2)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        Task { await viewModel.deleteItem(item) }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .contextMenu {
                    itemMenuItems(item)
                }
            }
        }
    }

    // MARK: - Items Gallery

    private var itemsGallery: some View {
        ScrollView {
            ItemGalleryGrid(
                items: viewModel.filteredItems,
                kind: .item,
                onTap: { editingItem = $0 },
                onAddPhoto: { item in
                    photoSourceItem = item
                    showPhotoSource = true
                },
                tileMenu: { item in
                    itemMenuItems(item)
                }
            )
            .padding()
        }
    }

    // MARK: - Shared Menu

    @ViewBuilder
    private func itemMenuItems(_ item: Item) -> some View {
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
            Task { await viewModel.deleteItem(item) }
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
                    .frame(width: 40, height: 40)
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
            .font(.system(size: 34))
            .foregroundStyle(.tertiary)
    }

    // MARK: - Location Badge

    private func locationBadge(for item: Item) -> some View {
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
            } else {
                Text("Unassigned")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule())
            }
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
                    .background(.ultraThinMaterial, in: Capsule())
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Items Yet", systemImage: "shippingbox")
        } description: {
            Text("Tap + to add your first item and start tracking where your stuff lives.")
        } actions: {
            Button("Add Item") {
                showingAddSheet = true
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

// MARK: - Item Photo Preview Sheet

struct ItemPhotoPreviewSheet: View {
    let item: Item
    @Bindable var viewModel: StuffViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let liveItem = viewModel.items.first(where: { $0.id == item.id }) ?? item
        NavigationStack {
            Group {
                if liveItem.hasItemPhoto {
                    PhotoView(item: liveItem, kind: .item, size: .full) { image in
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

// MARK: - Item Form Sheet

struct ItemFormSheet: View {
    let item: Item?
    @Bindable var viewModel: StuffViewModel
    let onSave: (String, String?, String?, String?, Data?, Data?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var notes: String
    @State private var selectedLocationId: String
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

    private enum PhotoTarget { case item, location }

    private let unassignedSentinel = "__unassigned__"
    private let uncategorizedSentinel = "__uncategorized__"

    init(
        item: Item? = nil,
        viewModel: StuffViewModel,
        onSave: @escaping (String, String?, String?, String?, Data?, Data?) -> Void
    ) {
        self.item = item
        self.viewModel = viewModel
        self.onSave = onSave
        _name = State(initialValue: item?.name ?? "")
        _notes = State(initialValue: item?.notes ?? "")
        _selectedLocationId = State(initialValue: item?.locationId ?? "__unassigned__")
        _selectedCategoryId = State(initialValue: item?.categoryId ?? "__uncategorized__")
        _useSameForLocation = State(initialValue: item == nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Item name", text: $name)
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
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
                    Picker("Location", selection: $selectedLocationId) {
                        Text("Unassigned").tag(unassignedSentinel)
                        ForEach(viewModel.flattenedLocationTree(), id: \.location.id) { entry in
                            Text(String(repeating: "  ", count: entry.depth) + (entry.location.emoji ?? "📍") + " " + entry.location.name)
                                .tag(entry.location.id)
                        }
                    }
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
                        let categoryId = selectedCategoryId == uncategorizedSentinel ? nil : selectedCategoryId
                        let resolvedLocationData: Data? = useSameForLocation ? photoData : locationPhotoData
                        onSave(name, notes.isEmpty ? nil : notes, locationId, categoryId, photoData, resolvedLocationData)
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

    private func assignPhotoData(_ data: Data) {
        switch photoTarget {
        case .item: photoData = data
        case .location: locationPhotoData = data
        }
    }
}

#Preview {
    ContentView(authService: AuthService())
}
