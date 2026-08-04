import PhotosUI
import SwiftUI

/// A location's home: its items and sub-locations, with Edit and QR actions.
/// Used both pushed (Locations tab) and presented as a sheet (deep-link / scan).
struct LocationDetailView: View {
    let location: Location
    @Bindable var viewModel: StuffViewModel

    @State private var showingEdit = false
    @State private var showingQR = false
    @State private var showCodes = false
    @State private var detailItem: Item?
    @State private var showShareSheet = false
    @State private var showingMoveItemsHere = false
    @State private var showingAddItem = false
    @State private var photoSourceItem: Item?
    @State private var showPhotoSource = false
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var selectedPhoto: PhotosPickerItem?
    @AppStorage("locationViewMode") private var viewMode = "list"
    @AppStorage("galleryColumns") private var galleryColumns = 2
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isGallery: Bool { viewMode == "gallery" }

    /// Follow live edits so the header/list update after Edit.
    private var live: Location {
        viewModel.locations.first(where: { $0.id == location.id }) ?? location
    }

    private var children: [Location] {
        viewModel.childLocations(for: live)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var directItems: [Item] {
        viewModel.items(for: live)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    Text(live.emoji ?? "📍").font(.largeTitle)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(live.name).font(.title2.weight(.semibold))
                        Text("\(viewModel.recursiveItemCount(for: live)) items")
                            .font(.caption).foregroundStyle(.secondary)
                        if viewModel.isSharedWithMe(live) {
                            SharedBadge(ownerName: viewModel.friend(forUid: live.ownerId ?? "")?.displayName)
                        } else if viewModel.isShared(live) {
                            SharedBadge()
                        }
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            }

            if !children.isEmpty {
                Section("Sub-locations") {
                    ForEach(children) { child in
                        NavigationLink {
                            LocationDetailView(location: child, viewModel: viewModel)
                        } label: {
                            Label { Text(child.name) } icon: { Text(child.emoji ?? "📍") }
                        }
                    }
                }
            }

            Section {
                Button {
                    showCodes = true
                } label: {
                    CodesRow(tags: live.pairedTags)
                }
                .tint(.primary)
            }

            // Add actions live in their own section, separated from the item list.
            Section {
                Button {
                    showingAddItem = true
                } label: {
                    Label("Add item here", systemImage: "plus.circle")
                }

                Button {
                    showingMoveItemsHere = true
                } label: {
                    Label("Move items here", systemImage: "tray.and.arrow.down")
                }
            }

            Section("Items") {
                if directItems.isEmpty {
                    Text("No items here yet.").foregroundStyle(.secondary)
                } else if isGallery {
                    ItemGalleryGrid(
                        items: directItems,
                        kind: .location,
                        columns: horizontalSizeClass == .regular ? galleryColumns : 2,
                        onTap: { detailItem = $0 },
                        onAddPhoto: { item in
                            photoSourceItem = item
                            showPhotoSource = true
                        },
                        tileMenu: { item in itemMenuItems(item) }
                    )
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(directItems) { item in
                        Button {
                            detailItem = item
                        } label: {
                            Text(item.name).foregroundStyle(.primary)
                        }
                        .contextMenu { itemMenuItems(item) }
                    }
                }
            }
        }
        .navigationTitle(live.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if viewModel.canManageSharing(of: live) {
                    Button { showShareSheet = true } label: {
                        Image(systemName: viewModel.isShared(live) ? "person.2.fill" : "person.2")
                    }
                }
                if isGallery && horizontalSizeClass == .regular {
                    GalleryColumnSlider()
                }
                Button {
                    withAnimation { viewMode = isGallery ? "list" : "gallery" }
                } label: {
                    Image(systemName: isGallery ? "list.bullet" : "square.grid.2x2")
                }
                Button { showingQR = true } label: { Image(systemName: "qrcode") }
                Button("Edit") { showingEdit = true }
            }
        }
        .sheet(isPresented: $showingQR) {
            if let subject = viewModel.qrSubject(for: .location(live.id)) {
                QRCodeSheet(subject: subject, viewModel: viewModel)
            }
        }
        .sheet(isPresented: $showCodes) {
            if let subject = viewModel.qrSubject(for: .location(live.id)) {
                CodesSheet(live: subject, tags: live.pairedTags, viewModel: viewModel)
            }
        }
        .sheet(isPresented: $showingEdit) {
            LocationFormSheet(
                location: live,
                viewModel: viewModel,
                onSave: { name, emoji, parentId in
                    var updated = live
                    updated.name = name
                    updated.emoji = emoji
                    updated.parentId = parentId
                    Task { await viewModel.updateLocation(updated) }
                }
            )
        }
        .sheet(item: $detailItem) { item in
            ItemDetailSheet(item: item, viewModel: viewModel)
        }
        .sheet(isPresented: $showingMoveItemsHere) {
            MoveItemsHereSheet(destination: live, viewModel: viewModel)
        }
        .sheet(isPresented: $showingAddItem) {
            ItemFormSheet(
                initialLocationId: live.id,
                viewModel: viewModel,
                onSave: { name, notes, locationId, categoryId, itemPhotoData, locationPhotoData, shareWith in
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
                            for uid in shareWith {
                                await viewModel.shareItem(newItem, withFriend: uid)
                            }
                        }
                    }
                }
            )
        }
        .sheet(isPresented: $showShareSheet) {
            LocationShareSheet(location: live, viewModel: viewModel)
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
        .containerBackground(LinearGradient.appBackground, for: .navigation)
    }

    @ViewBuilder
    private func itemMenuItems(_ item: Item) -> some View {
        Button {
            detailItem = item
        } label: {
            Label("Details", systemImage: "info.circle")
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
}
