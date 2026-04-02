import PhotosUI
import SwiftUI

struct ItemsView: View {
    @Bindable var viewModel: StuffViewModel
    @State private var showingAddSheet = false
    @State private var editingItem: Item?
    @State private var photoSourceItem: Item?
    @State private var showPhotoSource = false
    @State private var previewItem: Item?
    @State private var showCamera = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isUploading = false

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.items.isEmpty {
                    emptyState
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
                    onSave: { name, notes, locationId, categoryId in
                        Task { await viewModel.addItem(name: name, notes: notes, locationId: locationId, categoryId: categoryId) }
                    }
                )
            }
            .sheet(item: $editingItem) { item in
                ItemFormSheet(
                    item: item,
                    viewModel: viewModel,
                    onSave: { name, notes, locationId, categoryId in
                        var updated = item
                        updated.name = name
                        updated.notes = notes
                        updated.locationId = locationId
                        updated.categoryId = categoryId
                        Task { await viewModel.updateItem(updated) }
                    }
                )
            }
            .sheet(item: $previewItem) { item in
                ItemPhotoPreviewSheet(item: item, viewModel: viewModel)
                    .presentationDetents([.medium, .large])
            }
            .confirmationDialog("Item Photo", isPresented: $showPhotoSource) {
                Button("Take Photo") { showCamera = true }
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Text("Choose from Library")
                }
            }
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
            }
        }
    }

    // MARK: - Item Photo Circle

    @ViewBuilder
    private func itemPhotoCircle(_ item: Item) -> some View {
        let liveItem = viewModel.items.first(where: { $0.id == item.id }) ?? item
        if let photoURL = liveItem.itemPhotoURL, let url = URL(string: photoURL) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: 40, height: 40)
                        .clipShape(Circle())
                default:
                    photoPlaceholderCircle
                }
            }
            .onTapGesture {
                previewItem = liveItem
            }
            .onLongPressGesture {
                photoSourceItem = liveItem
                showPhotoSource = true
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
                if let photoURL = liveItem.itemPhotoURL, let url = URL(string: photoURL) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .padding()
                        case .failure:
                            ContentUnavailableView("Failed to load", systemImage: "exclamationmark.triangle")
                        case .empty:
                            ProgressView()
                        @unknown default:
                            ProgressView()
                        }
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
    let onSave: (String, String?, String?, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var notes: String
    @State private var selectedLocationId: String
    @State private var selectedCategoryId: String
    @State private var showingNewCategory = false
    @State private var newCategoryName = ""

    private let unassignedSentinel = "__unassigned__"
    private let uncategorizedSentinel = "__uncategorized__"

    init(
        item: Item? = nil,
        viewModel: StuffViewModel,
        onSave: @escaping (String, String?, String?, String?) -> Void
    ) {
        self.item = item
        self.viewModel = viewModel
        self.onSave = onSave
        _name = State(initialValue: item?.name ?? "")
        _notes = State(initialValue: item?.notes ?? "")
        _selectedLocationId = State(initialValue: item?.locationId ?? "__unassigned__")
        _selectedCategoryId = State(initialValue: item?.categoryId ?? "__uncategorized__")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Item name", text: $name)
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("Location") {
                    Picker("Location", selection: $selectedLocationId) {
                        Text("Unassigned").tag(unassignedSentinel)
                        ForEach(viewModel.locations) { location in
                            Label {
                                Text(location.name)
                            } icon: {
                                Text(location.emoji ?? "📍")
                            }
                            .tag(location.id)
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
                        onSave(name, notes.isEmpty ? nil : notes, locationId, categoryId)
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
        }
    }
}

#Preview {
    ContentView(authService: AuthService())
}
