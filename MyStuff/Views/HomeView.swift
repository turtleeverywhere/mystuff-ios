import PhotosUI
import SwiftUI

struct HomeView: View {
    @Bindable var viewModel: StuffViewModel
    @State private var selectedItem: Item?
    @State private var detailItem: Item?
    @State private var itemToPromptPhoto: Item?
    @State private var previewItem: Item?
    @State private var photoSourceItem: Item?
    @State private var showPhotoSource = false
    @State private var showCamera = false
    @State private var selectedPhoto: PhotosPickerItem?

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
                    viewModel: viewModel,
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
                        await viewModel.setItemPhoto(for: item, imageData: data)
                        photoSourceItem = nil
                    }
                }
                .ignoresSafeArea()
            }
            .onChange(of: selectedPhoto) {
                guard let selectedPhoto, let item = photoSourceItem else { return }
                Task {
                    if let data = try? await selectedPhoto.loadTransferable(type: Data.self) {
                        await viewModel.setItemPhoto(for: item, imageData: data)
                    }
                    self.selectedPhoto = nil
                    photoSourceItem = nil
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

    // MARK: - Location Grouping

    private var locationGrouping: some View {
        Group {
            ForEach(viewModel.rootLocations) { location in
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
                Text("\(viewModel.recursiveItemCount(for: location))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule())
            }

            // Items directly at this root location
            let directItems = viewModel.items(for: location)
            if directItems.isEmpty && viewModel.flattenedDescendantItems(for: location).isEmpty {
                Text("No items here")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 4)
            } else {
                ForEach(directItems) { item in
                    itemRow(item, tag: categoryTag(for: item))
                }

                // Flattened descendant items grouped by sublocation
                ForEach(viewModel.flattenedDescendantItems(for: location), id: \.sublocation.id) { entry in
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
        if let photoURL = item.itemPhotoURL, let url = URL(string: photoURL) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: 28, height: 28)
                        .clipShape(Circle())
                default:
                    Image(systemName: "photo.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.tertiary)
                }
            }
            .onTapGesture {
                previewItem = item
            }
            .onLongPressGesture {
                photoSourceItem = item
                showPhotoSource = true
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

#Preview {
    ContentView(authService: AuthService())
}
