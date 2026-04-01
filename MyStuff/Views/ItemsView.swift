import SwiftUI

struct ItemsView: View {
    @Bindable var viewModel: StuffViewModel
    @State private var showingAddSheet = false
    @State private var editingItem: Item?

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
                    locations: viewModel.locations,
                    categories: viewModel.categories,
                    onSave: { name, notes, locationId, categoryId in
                        Task { await viewModel.addItem(name: name, notes: notes, locationId: locationId, categoryId: categoryId) }
                    },
                    onCreateCategory: { name in
                        Task { await viewModel.addCategory(name: name) }
                    }
                )
            }
            .sheet(item: $editingItem) { item in
                ItemFormSheet(
                    item: item,
                    locations: viewModel.locations,
                    categories: viewModel.categories,
                    onSave: { name, notes, locationId, categoryId in
                        var updated = item
                        updated.name = name
                        updated.notes = notes
                        updated.locationId = locationId
                        updated.categoryId = categoryId
                        Task { await viewModel.updateItem(updated) }
                    },
                    onCreateCategory: { name in
                        Task { await viewModel.addCategory(name: name) }
                    }
                )
            }
        }
    }

    // MARK: - Items List

    private var itemsList: some View {
        List {
            ForEach(viewModel.filteredItems) { item in
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
                        locationBadge(for: item)
                    }
                    .padding(.vertical, 2)
                }
                .buttonStyle(.plain)
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

// MARK: - Item Form Sheet

struct ItemFormSheet: View {
    let item: Item?
    let locations: [Location]
    let categories: [Category]
    let onSave: (String, String?, String?, String?) -> Void
    let onCreateCategory: (String) -> Void

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
        locations: [Location],
        categories: [Category],
        onSave: @escaping (String, String?, String?, String?) -> Void,
        onCreateCategory: @escaping (String) -> Void
    ) {
        self.item = item
        self.locations = locations
        self.categories = categories
        self.onSave = onSave
        self.onCreateCategory = onCreateCategory
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
                        ForEach(locations) { location in
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
                        ForEach(categories) { category in
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
                        onCreateCategory(trimmed)
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
