import SwiftUI

struct HomeView: View {
    @Bindable var viewModel: StuffViewModel
    @State private var selectedItem: Item?
    @State private var detailItem: Item?
    @State private var itemToPromptPhoto: Item?

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
            .sheet(item: $selectedItem) { item in
                MoveItemSheet(
                    item: item,
                    locations: viewModel.locations,
                    onMove: { locationId in
                        Task {
                            await viewModel.moveItem(item, toLocationId: locationId)
                            if item.photoURL != nil {
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
        }
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

    // MARK: - Location Grouping (existing behavior)

    private var locationGrouping: some View {
        Group {
            ForEach(viewModel.locations) { location in
                locationCard(location)
            }
            if !viewModel.unassignedItems.isEmpty {
                unassignedLocationCard
            }
        }
    }

    // MARK: - Category Grouping

    private var categoryGrouping: some View {
        Group {
            ForEach(viewModel.categories) { category in
                categoryCard(category)
            }
            if !viewModel.uncategorizedItems.isEmpty {
                uncategorizedCard
            }
        }
    }

    // MARK: - Location Card

    private func locationCard(_ location: Location) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(location.emoji ?? "📍")
                    .font(.title2)
                Text(location.name)
                    .font(.headline)
                Spacer()
                Text("\(viewModel.itemCount(for: location))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule())
            }

            let locationItems = viewModel.items(for: location)
            if locationItems.isEmpty {
                Text("No items here")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 4)
            } else {
                ForEach(locationItems) { item in
                    itemRow(item, tag: categoryTag(for: item))
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Unassigned Location Card

    private var unassignedLocationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("❓")
                    .font(.title2)
                Text("Unassigned")
                    .font(.headline)
                Spacer()
                Text("\(viewModel.unassignedItems.count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule())
            }

            ForEach(viewModel.unassignedItems) { item in
                itemRow(item, tag: categoryTag(for: item))
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Category Card

    private func categoryCard(_ category: Category) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(category.name)
                    .font(.headline)
                Spacer()
                Text("\(viewModel.itemCount(for: category))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule())
            }

            let categoryItems = viewModel.items(for: category)
            if categoryItems.isEmpty {
                Text("No items here")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 4)
            } else {
                ForEach(categoryItems) { item in
                    itemRow(item, tag: locationTag(for: item))
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Uncategorized Card

    private var uncategorizedCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Uncategorized")
                    .font(.headline)
                Spacer()
                Text("\(viewModel.uncategorizedItems.count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule())
            }

            ForEach(viewModel.uncategorizedItems) { item in
                itemRow(item, tag: locationTag(for: item))
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Item Row

    private func itemRow(_ item: Item, tag: some View) -> some View {
        HStack {
            Button {
                detailItem = item
            } label: {
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
    }

    @ViewBuilder
    private func itemThumbnail(_ item: Item) -> some View {
        if let photoURL = item.photoURL, let url = URL(string: photoURL) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: 28, height: 28)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                default:
                    Image(systemName: "shippingbox")
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            Image(systemName: "shippingbox")
                .foregroundStyle(.secondary)
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
    let locations: [Location]
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

                    ForEach(locations) { location in
                        Button {
                            onMove(location.id)
                            dismiss()
                        } label: {
                            Label {
                                Text(location.name)
                            } icon: {
                                Text(location.emoji ?? "📍")
                            }
                        }
                        .tint(item.locationId == location.id ? .accentColor : .primary)
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

#Preview {
    ContentView(authService: AuthService())
}
