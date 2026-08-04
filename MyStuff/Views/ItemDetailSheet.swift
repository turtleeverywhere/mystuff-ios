import PhotosUI
import SwiftUI

struct ItemDetailSheet: View {
    let item: Item
    @Bindable var viewModel: StuffViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isUploading = false
    @State private var showDeleteConfirmation = false
    @State private var showPhotoSource = false
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var showCodes = false
    @State private var showShareSheet = false
    @State private var showMoveScanner = false
    @State private var showLocationSearch = false
    @State private var unknownScan = false
    @State private var pendingMove: (locationId: String, location: Location, missing: [String])?

    private var liveItem: Item {
        viewModel.items.first(where: { $0.id == item.id }) ?? item
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    photoSection
                    infoSection
                    moveSection
                    Button {
                        showCodes = true
                    } label: {
                        CodesRow(tags: liveItem.pairedTags)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .tint(.primary)
                    privacySection
                }
                .padding()
            }
            .navigationTitle(item.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    if viewModel.canManageSharing(of: liveItem) {
                        Button {
                            showShareSheet = true
                        } label: {
                            Image(systemName: viewModel.isShared(liveItem) ? "person.2.fill" : "person.2")
                        }
                    }
                }
            }
        }
        .onChange(of: selectedPhoto) {
            guard let selectedPhoto else { return }
            Task {
                isUploading = true
                if let data = try? await selectedPhoto.loadTransferable(type: Data.self) {
                    await viewModel.setPhoto(for: item, imageData: data)
                }
                isUploading = false
                self.selectedPhoto = nil
            }
        }
        .confirmationDialog("Delete photo?", isPresented: $showDeleteConfirmation) {
            Button("Delete Photo", role: .destructive) {
                Task { await viewModel.deletePhoto(for: item) }
            }
        }
        .sheet(isPresented: $showCodes) {
            // Build the subject locally rather than looking it up: a lookup
            // returns nil once the item is deleted, presenting a blank sheet.
            CodesSheet(
                live: QRSubject(target: .item(liveItem.id), name: liveItem.name, icon: "📦"),
                tags: liveItem.pairedTags,
                viewModel: viewModel
            )
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
                Task {
                    isUploading = true
                    await viewModel.setPhoto(for: item, imageData: data)
                    isUploading = false
                }
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showMoveScanner) {
            QRScannerSheet(accepts: .location) { target in
                let locationId = target.entityId
                if viewModel.locations.contains(where: { $0.id == locationId }) {
                    performMove(toLocationId: locationId)
                } else {
                    unknownScan = true
                }
            }
        }
        .sheet(isPresented: $showLocationSearch) {
            LocationSearchSheet(viewModel: viewModel) { locationId in
                performMove(toLocationId: locationId)
            }
        }
        .alert("Location not found", isPresented: $unknownScan) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("That QR points to a location that no longer exists.")
        }
        .confirmationDialog(
            pendingMove.map { "\"\(item.name)\" is shared, but \($0.location.name) isn't." } ?? "",
            isPresented: Binding(
                get: { pendingMove != nil },
                set: { if !$0 { pendingMove = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let pending = pendingMove {
                Button("Share \(pending.location.name) too") {
                    Task {
                        await viewModel.addMembers(pending.missing, toLocation: pending.location)
                        await viewModel.moveItem(liveItem, toLocationId: pending.locationId)
                        pendingMove = nil
                    }
                }
                Button("Make item private", role: .destructive) {
                    Task {
                        await viewModel.makeItemPrivate(liveItem)
                        await viewModel.moveItem(liveItem, toLocationId: pending.locationId)
                        pendingMove = nil
                    }
                }
                Button("Cancel", role: .cancel) { pendingMove = nil }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            let live = viewModel.items.first(where: { $0.id == item.id }) ?? item
            FriendShareSheet(
                title: "Share \"\(live.name)\"",
                friends: viewModel.friends,
                sharedWith: Set(viewModel.sharedMembers(of: live)),
                onToggle: { uid, share in
                    if share { await viewModel.shareItem(live, withFriend: uid) }
                    else { await viewModel.unshareItem(live, fromFriend: uid) }
                }
            )
        }
    }

    // MARK: - Photo Section

    @ViewBuilder
    private var photoSection: some View {
        let liveItem = viewModel.items.first(where: { $0.id == item.id }) ?? item

        if liveItem.hasLocationPhoto {
            PhotoView(item: liveItem, kind: .location, size: .full) { image in
                image
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 300)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            } placeholder: {
                photoPlaceholder(systemName: "photo", text: "Loading...")
                    .overlay { ProgressView() }
            }
            .overlay(alignment: .topTrailing) {
                Button {
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.5))
                }
                .padding(8)
            }

            Button {
                showPhotoSource = true
            } label: {
                Label("Replace Photo", systemImage: "arrow.triangle.2.circlepath.camera")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(isUploading)
        } else {
            photoPlaceholder(systemName: "camera", text: "No photo yet")

            Button {
                showPhotoSource = true
            } label: {
                Label(isUploading ? "Uploading..." : "Add Photo", systemImage: "camera.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isUploading)
        }

        if isUploading {
            ProgressView("Uploading...")
        }
    }

    private func photoPlaceholder(systemName: String, text: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: systemName)
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 200)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Privacy Section

    @ViewBuilder
    private var privacySection: some View {
        if viewModel.canManageSharing(of: liveItem) {
            let isPrivate = Binding(
                get: { liveItem.isPrivate == true },
                set: { newValue in
                    Task { await viewModel.setItemPrivate(liveItem, newValue) }
                }
            )
            VStack(alignment: .leading, spacing: 6) {
                Toggle(isOn: isPrivate) {
                    HStack(spacing: 8) {
                        Image(systemName: "lock")
                            .foregroundStyle(.tint)
                        Text("Always private")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                }
                Text("Excluded from automatic sharing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Info Section

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let notes = liveItem.notes, !notes.isEmpty {
                Text(notes)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                if let location = viewModel.location(for: liveItem) {
                    Label {
                        Text(viewModel.displayPath(for: location))
                    } icon: {
                        Text(location.emoji ?? "📍")
                    }
                    .font(.subheadline)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                }

                if let category = viewModel.category(for: liveItem) {
                    Text(category.name)
                        .font(.subheadline)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Move Section

    private var moveSection: some View {
        VStack(spacing: 12) {
            Menu {
                Button {
                    showLocationSearch = true
                } label: {
                    Label("Search Locations…", systemImage: "magnifyingglass")
                }

                Divider()

                Button {
                    performMove(toLocationId: nil)
                } label: {
                    Label("Unassigned", systemImage: "questionmark.circle")
                }

                Divider()

                ForEach(moveRootLocations, id: \.id) { root in
                    LocationMoveMenuItem(location: root, viewModel: viewModel) { locationId in
                        performMove(toLocationId: locationId)
                    }
                }
            } label: {
                moveRow(icon: "arrow.right.circle", text: "Move to Location", trailingIcon: "chevron.up.chevron.down")
            }

            if QRScannerView.isSupported {
                Button {
                    showMoveScanner = true
                } label: {
                    moveRow(icon: "qrcode.viewfinder", text: "Scan Location QR", trailingIcon: nil)
                }
            }
        }
    }

    private var moveRootLocations: [Location] {
        viewModel.rootLocations
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func moveRow(icon: String, text: String, trailingIcon: String?) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
            Text(text)
                .fontWeight(.medium)
            Spacer()
            if let trailingIcon {
                Image(systemName: trailingIcon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    /// Move the live item, prompting first if it's shared with members the target location lacks.
    private func performMove(toLocationId locationId: String?) {
        let live = liveItem
        let itemMembers = viewModel.sharedMembers(of: live)
        guard let locationId,
              viewModel.canManageSharing(of: live),
              !itemMembers.isEmpty,
              let location = viewModel.locations.first(where: { $0.id == locationId }) else {
            Task { await viewModel.moveItem(live, toLocationId: locationId) }
            return
        }
        let missing = viewModel.membersMissing(from: location, forItemMembers: itemMembers)
        if missing.isEmpty {
            Task { await viewModel.moveItem(live, toLocationId: locationId) }
        } else {
            pendingMove = (locationId, location, missing)
        }
    }
}

// MARK: - Location Move Menu

/// One entry in the move menu. Locations with children render as a submenu:
/// the parent itself is selectable at the top, its sublocations nest below.
struct LocationMoveMenuItem: View {
    let location: Location
    let viewModel: StuffViewModel
    let onSelect: (String) -> Void

    var body: some View {
        let children = viewModel.childLocations(for: location)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        if children.isEmpty {
            Button {
                onSelect(location.id)
            } label: {
                Label {
                    Text(location.name)
                } icon: {
                    Text(location.emoji ?? "📍")
                }
            }
        } else {
            Menu {
                Button {
                    onSelect(location.id)
                } label: {
                    Label("Move to \"\(location.name)\"", systemImage: "arrow.right.circle")
                }

                Divider()

                ForEach(children, id: \.id) { child in
                    LocationMoveMenuItem(location: child, viewModel: viewModel, onSelect: onSelect)
                }
            } label: {
                Label {
                    Text(location.name)
                } icon: {
                    Text(location.emoji ?? "📍")
                }
            }
        }
    }
}

// MARK: - Location Search Sheet

/// Searchable location picker. Browsing shows the indented tree;
/// typing filters to matches with their full path for context.
struct LocationSearchSheet: View {
    let viewModel: StuffViewModel
    let onSelect: (String?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var results: [(location: Location, depth: Int)] {
        let tree = viewModel.flattenedLocationTree()
        guard !searchText.isEmpty else { return tree }
        return tree.filter { $0.location.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            List {
                if searchText.isEmpty {
                    Button {
                        onSelect(nil)
                        dismiss()
                    } label: {
                        Label("Unassigned", systemImage: "questionmark.circle")
                    }
                    .tint(.primary)
                }

                ForEach(results, id: \.location.id) { entry in
                    Button {
                        onSelect(entry.location.id)
                        dismiss()
                    } label: {
                        Label {
                            if searchText.isEmpty {
                                Text(entry.location.name)
                            } else {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.location.name)
                                    Text(viewModel.displayPath(for: entry.location))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } icon: {
                            Text(entry.location.emoji ?? "📍")
                        }
                    }
                    .tint(.primary)
                    .padding(.leading, searchText.isEmpty ? CGFloat(entry.depth) * 20 : 0)
                }
            }
            .overlay {
                if !searchText.isEmpty && results.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search locations"
            )
            .navigationTitle("Move to Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Camera Picker

struct CameraPicker: UIViewControllerRepresentable {
    let onCapture: (Data) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker

        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage,
               let data = image.jpegData(compressionQuality: 0.9) {
                parent.onCapture(data)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
