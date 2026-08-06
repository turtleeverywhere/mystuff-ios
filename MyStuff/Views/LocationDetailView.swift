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
    @State private var previewItem: Item?
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

    /// Items homed here but currently somewhere else.
    private var missingItems: [Item] {
        viewModel.missingItems(for: live)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func currentPlace(of item: Item) -> String {
        guard let location = viewModel.location(for: item) else { return "Unassigned" }
        return viewModel.displayPath(for: location)
    }

    /// Bulk-returns everything homed here. Mirrors `MoveItemsHereSheet.confirmMove`:
    /// collaborators on the moved items are added to the destination first, or they
    /// would lose sight of items that just moved into a location they can't see.
    private func putAllBackHere() {
        let dest = live
        let targets = missingItems
        Task {
            if viewModel.canManageSharing(of: dest) {
                var missingMembers: [String] = []
                for item in targets where viewModel.canManageSharing(of: item) {
                    missingMembers.append(contentsOf: viewModel.membersMissing(
                        from: dest,
                        forItemMembers: viewModel.sharedMembers(of: item)
                    ))
                }
                let union = Array(Set(missingMembers))
                if !union.isEmpty {
                    await viewModel.addMembers(union, toLocation: dest)
                }
            }
            await viewModel.moveItems(targets, toLocationId: dest.id)
        }
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

            if !missingItems.isEmpty {
                Section {
                    ForEach(missingItems) { item in
                        Button {
                            Task { await viewModel.putBackItems([item]) }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name)
                                        .foregroundStyle(.primary)
                                    Text(currentPlace(of: item))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "arrow.uturn.left.circle")
                                    .foregroundStyle(.tint)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    HStack {
                        Text("Missing from here")
                        Spacer()
                        Button("Put all back here", action: putAllBackHere)
                            .font(.caption)
                            .textCase(nil)
                    }
                }
            }

            Section("Items") {
                if directItems.isEmpty {
                    Text("No items here yet.").foregroundStyle(.secondary)
                } else if isGallery {
                    ItemGalleryGrid(
                        items: directItems,
                        isMisplaced: { viewModel.isMisplaced($0) },
                        kind: .location,
                        columns: horizontalSizeClass == .regular ? galleryColumns : 2,
                        onTap: { detailItem = $0 },
                        onAddPhoto: { item in
                            photoSourceItem = item
                            showPhotoSource = true
                        },
                        onDoubleTap: { previewItem = $0 },
                        tileMenu: { item in itemMenuItems(item) }
                    )
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(directItems) { item in
                        itemRow(item)
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
        .fullScreenCover(item: $previewItem) { item in
            PhotoPreviewViewer(item: item, kind: .location, viewModel: viewModel)
        }
        .sheet(isPresented: $showCodes) {
            // Build the subject locally rather than looking it up: a lookup
            // returns nil once the location is deleted, presenting a blank sheet.
            CodesSheet(
                live: QRSubject(target: .location(live.id), name: live.name, icon: live.emoji ?? "📍"),
                tags: live.pairedTags,
                viewModel: viewModel
            )
        }
        .sheet(isPresented: $showingEdit) {
            LocationFormSheet(
                location: live,
                viewModel: viewModel,
                onSave: { result in
                    var updated = live
                    updated.name = result.name
                    updated.emoji = result.emoji
                    updated.parentId = result.parentId
                    Task {
                        await viewModel.updateLocation(updated)
                        await viewModel.applyStagedTags(result.nfcTags, to: .location(live.id))
                    }
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

    private func itemRow(_ item: Item) -> some View {
        itemRowBody(item)
            .itemTapGestures(
                previewEnabled: item.hasLocationPhoto,
                onPreview: { previewItem = item },
                onOpen: { detailItem = item }
            )
    }

    private func itemRowBody(_ item: Item) -> some View {
        HStack {
            Text(item.name)
                .foregroundStyle(.primary)
            Spacer()
            if viewModel.isMisplaced(item) {
                MisplacedBadge(iconOnly: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityAddTraits(.isButton)
        .contextMenu { itemMenuItems(item) }
    }

    @ViewBuilder
    private func itemMenuItems(_ item: Item) -> some View {
        PutBackMenuButton(item: item, viewModel: viewModel)
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
