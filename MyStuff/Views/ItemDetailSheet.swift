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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    photoSection
                    infoSection
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
        .confirmationDialog("Add Photo", isPresented: $showPhotoSource) {
            Button("Take Photo") { showCamera = true }
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                Text("Choose from Library")
            }
        }
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
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 300)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                case .failure:
                    photoPlaceholder(systemName: "exclamationmark.triangle", text: "Failed to load")
                case .empty:
                    photoPlaceholder(systemName: "photo", text: "Loading...")
                        .overlay { ProgressView() }
                @unknown default:
                    photoPlaceholder(systemName: "photo", text: "Loading...")
                }
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
                        Text(location.name)
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
