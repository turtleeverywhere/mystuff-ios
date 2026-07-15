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
    @State private var nfcService: NFCService = CoreNFCService()
    @State private var isPairing = false
    @State private var nfcErrorMessage: String?
    @State private var pairOverwritePrevious: String?
    @State private var showUnpairConfirmation = false
    @State private var showShareSheet = false
    @State private var showMoveScanner = false
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
                    nfcSection
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
            .alert("NFC Error", isPresented: Binding(
                get: { nfcErrorMessage != nil },
                set: { if !$0 { nfcErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { nfcErrorMessage = nil }
            } message: {
                Text(nfcErrorMessage ?? "")
            }
            .alert("Tag Already Paired", isPresented: Binding(
                get: { pairOverwritePrevious != nil },
                set: { if !$0 { pairOverwritePrevious = nil } }
            )) {
                Button("Reassign", role: .destructive) {
                    pairOverwritePrevious = nil
                    pairTag(allowOverwrite: true)
                }
                Button("Cancel", role: .cancel) { pairOverwritePrevious = nil }
            } message: {
                if let prevId = pairOverwritePrevious,
                   let prevItem = viewModel.items.first(where: { $0.id == prevId }) {
                    Text("This tag is already paired to \"\(prevItem.name)\". Reassign to \"\(item.name)\"?")
                } else {
                    Text("This tag is already paired to another item. Reassign?")
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
        .confirmationDialog(
            "Unpair NFC tag from \"\(item.name)\"?",
            isPresented: $showUnpairConfirmation,
            titleVisibility: .visible
        ) {
            Button("Unpair Tag", role: .destructive) {
                Task { await viewModel.clearNFCTag(itemId: item.id) }
            }
        } message: {
            Text("The tag will no longer be linked to this item. You can re-pair it anytime.")
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
            QRScannerSheet { locationId in
                if viewModel.locations.contains(where: { $0.id == locationId }) {
                    performMove(toLocationId: locationId)
                } else {
                    unknownScan = true
                }
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

    // MARK: - NFC Section

    @ViewBuilder
    private var nfcSection: some View {
        let liveItem = viewModel.items.first(where: { $0.id == item.id }) ?? item
        if nfcService.isAvailable {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "wave.3.right")
                        .foregroundStyle(.tint)
                    Text("NFC Tag")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    if liveItem.nfcTagUID != nil {
                        Text("Paired")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(.green.opacity(0.15), in: Capsule())
                            .foregroundStyle(.green)
                    }
                    Spacer()
                }

                if liveItem.nfcTagUID != nil {
                    Button(role: .destructive) {
                        showUnpairConfirmation = true
                    } label: {
                        Label("Unpair Tag", systemImage: "wave.3.right.slash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isPairing)
                } else {
                    Button {
                        pairTag(allowOverwrite: false)
                    } label: {
                        Label(isPairing ? "Hold near tag..." : "Pair NFC Tag", systemImage: "wave.3.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isPairing)
                }
            }
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func pairTag(allowOverwrite: Bool) {
        isPairing = true
        Task {
            do {
                let result = try await nfcService.writeItem(id: item.id, allowOverwrite: allowOverwrite)
                if let prevId = result.previousItemId {
                    await viewModel.clearNFCTag(itemId: prevId)
                }
                await viewModel.setNFCTag(itemId: item.id, uid: result.tagSerial)
                isPairing = false
            } catch NFCError.userCancelled {
                isPairing = false
            } catch NFCError.existingPairing(let previousId, _) {
                isPairing = false
                pairOverwritePrevious = previousId
            } catch {
                isPairing = false
                nfcErrorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Privacy Section

    private var privacySection: some View {
        let isPrivate = Binding(
            get: { liveItem.isPrivate == true },
            set: { newValue in
                Task { await viewModel.setItemPrivate(liveItem, newValue) }
            }
        )
        return VStack(alignment: .leading, spacing: 6) {
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

    // MARK: - Info Section

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let notes = item.notes, !notes.isEmpty {
                Text(notes)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                if let location = viewModel.location(for: item) {
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

                if let category = viewModel.category(for: item) {
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
        Menu {
            Button {
                performMove(toLocationId: nil)
            } label: {
                Label("Unassigned", systemImage: "questionmark.circle")
            }

            ForEach(viewModel.flattenedLocationTree(), id: \.location.id) { entry in
                Button {
                    performMove(toLocationId: entry.location.id)
                } label: {
                    Label {
                        Text(String(repeating: "   ", count: entry.depth) + entry.location.name)
                    } icon: {
                        Text(entry.location.emoji ?? "📍")
                    }
                }
            }

            if QRScannerView.isSupported {
                Divider()
                Button {
                    showMoveScanner = true
                } label: {
                    Label("Scan Location QR", systemImage: "qrcode.viewfinder")
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.right.circle")
                Text("Move to Location")
                    .fontWeight(.medium)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
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
