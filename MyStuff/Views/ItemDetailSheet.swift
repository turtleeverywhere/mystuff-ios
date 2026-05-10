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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    photoSection
                    infoSection
                    nfcSection
                }
                .padding()
            }
            .navigationTitle(item.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
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
    }

    // MARK: - Photo Section

    @ViewBuilder
    private var photoSection: some View {
        let liveItem = viewModel.items.first(where: { $0.id == item.id }) ?? item

        if let photoURL = liveItem.photoURL, let url = URL(string: photoURL) {
            CachedAsyncImage(url: url) { image in
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
                        Task { await viewModel.clearNFCTag(itemId: item.id) }
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
