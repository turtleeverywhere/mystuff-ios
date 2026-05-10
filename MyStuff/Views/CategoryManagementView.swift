import SwiftUI

struct CategoryManagementView: View {
    @Bindable var viewModel: StuffViewModel
    @State private var showingAddAlert = false
    @State private var newCategoryName = ""
    @State private var editingCategory: Category?
    @State private var editName = ""

    var body: some View {
        Group {
            if viewModel.categories.isEmpty {
                emptyState
            } else {
                categoryList
            }
        }
        .navigationTitle("Categories")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddAlert = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .alert("New Category", isPresented: $showingAddAlert) {
            TextField("Category name", text: $newCategoryName)
            Button("Add") {
                let trimmed = newCategoryName.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    Task { await viewModel.addCategory(name: trimmed) }
                    newCategoryName = ""
                }
            }
            Button("Cancel", role: .cancel) {
                newCategoryName = ""
            }
        }
        .alert("Rename Category", isPresented: Binding(
            get: { editingCategory != nil },
            set: { if !$0 { editingCategory = nil } }
        )) {
            TextField("Category name", text: $editName)
            Button("Save") {
                if var category = editingCategory {
                    let trimmed = editName.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty {
                        category.name = trimmed
                        Task { await viewModel.updateCategory(category) }
                    }
                }
                editingCategory = nil
            }
            Button("Cancel", role: .cancel) {
                editingCategory = nil
            }
        }
    }

    private var categoryList: some View {
        List {
            ForEach(viewModel.categories) { category in
                Button {
                    editingCategory = category
                    editName = category.name
                } label: {
                    HStack {
                        Text(category.name)
                            .font(.body)
                            .foregroundStyle(.primary)
                        Spacer()
                        Text("\(viewModel.itemCount(for: category)) items")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        Task { await viewModel.deleteCategory(category) }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Categories Yet", systemImage: "folder")
        } description: {
            Text("Tap + to create your first category.")
        } actions: {
            Button("Add Category") {
                showingAddAlert = true
            }
            .buttonStyle(.borderedProminent)
        }
    }
}
