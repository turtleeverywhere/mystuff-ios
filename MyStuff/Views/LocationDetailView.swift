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
    @State private var showingItemScan = false
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

    /// Items stored in sublocations, grouped by the sublocation holding them.
    /// Mirrors the Home screen's location cards: root items first, then each sublocation.
    private var descendantGroups: [(sublocation: Location, items: [Item])] {
        viewModel.flattenedDescendantItems(for: live).map { entry in
            (entry.sublocation,
             entry.items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
        }
    }

    /// Path of a sublocation relative to this location, e.g. "Shelf > Box".
    private func relativePath(of sublocation: Location) -> String {
        let path = viewModel.locationPath(for: sublocation)
        guard let idx = path.firstIndex(where: { $0.id == live.id }) else { return sublocation.name }
        return path.suffix(from: path.index(after: idx)).map(\.name).joined(separator: " > ")
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

    var body: some View {
        // Cards in a ScrollView, not a List: a LazyVGrid of tiles inside a list
        // row gets its context menu hoisted to the cell, so every long press
        // fired the first tile's menu. Also matches the Home screen's layout.
        ScrollView {
            LazyVStack(spacing: 16) {
                headerCard
                if !children.isEmpty {
                    sublocationsCard
                }
                codesCard
                actionsCard
                if !missingItems.isEmpty {
                    missingCard
                }
                itemsCard
            }
            .padding()
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
        .fullScreenCover(isPresented: $showingItemScan) {
            ItemScanView(viewModel: viewModel, destinationId: live.id)
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

    // MARK: - Cards

    /// Shared card chrome, matching the Home screen's location cards.
    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func cardTitle(_ text: String) -> some View {
        Text(text)
            .font(.headline)
    }

    private var headerCard: some View {
        card {
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
        }
    }

    private var sublocationsCard: some View {
        card {
            cardTitle("Sub-locations")
            ForEach(children) { child in
                NavigationLink {
                    LocationDetailView(location: child, viewModel: viewModel)
                } label: {
                    HStack(spacing: 8) {
                        Text(child.emoji ?? "📍")
                        Text(child.name)
                            .foregroundStyle(.primary)
                        Spacer()
                        Text("\(viewModel.recursiveItemCount(for: child))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var codesCard: some View {
        card {
            Button {
                showCodes = true
            } label: {
                CodesRow(tags: live.pairedTags)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var actionsCard: some View {
        card {
            Button {
                showingAddItem = true
            } label: {
                Label("Add item here", systemImage: "plus.circle")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }

            Divider().opacity(0.5)

            Button {
                showingMoveItemsHere = true
            } label: {
                Label("Move items here", systemImage: "tray.and.arrow.down")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }

            Divider().opacity(0.5)

            Button {
                showingItemScan = true
            } label: {
                Label("Scan items here", systemImage: "camera.viewfinder")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
        }
    }

    private var missingCard: some View {
        card {
            HStack {
                cardTitle("Missing from here")
                Spacer()
                // Every item here is homed at `live`, so putBackItems sends them
                // exactly where this button promises — and handles the auto-share.
                Button("Put all back here") {
                    Task { await viewModel.putBackItems(missingItems) }
                }
                .font(.caption)
            }

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
        }
    }

    /// Items stored here, then one group per sublocation — same shape as a Home card.
    private var itemsCard: some View {
        card {
            cardTitle("Items")

            if directItems.isEmpty && descendantGroups.isEmpty {
                Text("No items here yet.")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            } else if directItems.isEmpty {
                Text("No items directly here.")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            } else {
                itemsContent(directItems)
            }

            ForEach(descendantGroups, id: \.sublocation.id) { group in
                sublocationHeader(group.sublocation)
                itemsContent(group.items)
            }
        }
    }

    private func sublocationHeader(_ sublocation: Location) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
                .opacity(0.5)
            HStack(spacing: 6) {
                Text(sublocation.emoji ?? "📍")
                    .font(.subheadline)
                Text(relativePath(of: sublocation))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 6)
    }

    /// Renders a group of items in whichever mode is active.
    @ViewBuilder
    private func itemsContent(_ items: [Item]) -> some View {
        if isGallery {
            ItemGalleryGrid(
                items: items,
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
        } else {
            ForEach(items) { item in
                itemRow(item)
            }
        }
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
            if !item.pairedTags.isEmpty {
                NFCBadge(iconOnly: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
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
