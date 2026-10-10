import PhotosUI
import SwiftUI

/// Fast re-shelving sheet, reached by scanning an item's NFC tag or QR code,
/// or by opening its universal link. Lets the user update the item's location
/// photo and current location without the full detail screen.
struct ItemQuickUpdateSheet: View {
    let item: Item
    @Bindable var viewModel: StuffViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedLocationId: String
    @State private var newPhotoData: Data?
    @State private var showLocationFormSheet = false
    @State private var showLocationScanner = false
    @State private var unknownScan = false
    @State private var showPhotoSource = false
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isSaving = false

    private static let unassignedSentinel = "__unassigned__"

    init(item: Item, viewModel: StuffViewModel) {
        self.item = item
        self.viewModel = viewModel
        _selectedLocationId = State(initialValue: item.locationId ?? Self.unassignedSentinel)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Item") {
                    HStack {
                        Text(item.name)
                            .font(.headline)
                        Spacer()
                    }
                }

                Section("Location Photo") {
                    photoRow
                    Button {
                        showPhotoSource = true
                    } label: {
                        Label(newPhotoData != nil ? "Retake" : "Take New Photo", systemImage: "camera")
                    }
                }

                Section("Location") {
                    LocationPickerRow(
                        viewModel: viewModel,
                        label: "Location",
                        pickerTitle: "Choose Location",
                        selection: locationBinding
                    )

                    if QRScannerView.isSupported {
                        Button {
                            showLocationScanner = true
                        } label: {
                            Label("Scan Location QR", systemImage: "qrcode.viewfinder")
                        }
                    }

                    NFCScanButton(accepts: .location) { target in
                        selectScanned(target)
                    } label: { scanning in
                        Label(
                            scanning ? "Hold near tag…" : "Scan Location NFC Tag",
                            systemImage: "wave.3.right"
                        )
                    }

                    Button {
                        showLocationFormSheet = true
                    } label: {
                        Label("New Location...", systemImage: "plus.circle")
                    }
                }
            }
            .navigationTitle("Update Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving..." : "Save") { save() }
                        .disabled(isSaving)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .sheet(isPresented: $showLocationFormSheet) {
            LocationFormSheet(
                viewModel: viewModel,
                onSave: { result in
                    Task {
                        await viewModel.addLocation(id: result.id, name: result.name, emoji: result.emoji, parentId: result.parentId)
                        guard viewModel.locations.contains(where: { $0.id == result.id }) else { return }
                        await viewModel.applyStagedTags(result.nfcTags, to: .location(result.id))
                        selectedLocationId = result.id
                    }
                }
            )
        }
        .sheet(isPresented: $showLocationScanner) {
            QRScannerSheet(accepts: .location) { target in
                selectScanned(target)
            }
        }
        .alert("Location not found", isPresented: $unknownScan) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("That code points to a location that no longer exists.")
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
                newPhotoData = data
            }
            .ignoresSafeArea()
        }
        .onChange(of: selectedPhoto) {
            guard let selectedPhoto else { return }
            Task {
                if let data = try? await selectedPhoto.loadTransferable(type: Data.self) {
                    newPhotoData = data
                }
                self.selectedPhoto = nil
            }
        }
    }

    /// Bridges the sentinel-backed state to the picker's optional selection.
    private var locationBinding: Binding<String?> {
        Binding(
            get: { selectedLocationId == Self.unassignedSentinel ? nil : selectedLocationId },
            set: { selectedLocationId = $0 ?? Self.unassignedSentinel }
        )
    }

    /// Shared by both scanners: QR and NFC resolve to the same target.
    private func selectScanned(_ target: AppLink.Target) {
        let locationId = target.entityId
        if viewModel.locations.contains(where: { $0.id == locationId }) {
            selectedLocationId = locationId
        } else {
            unknownScan = true
        }
    }

    @ViewBuilder
    private var photoRow: some View {
        if let newPhotoData, let uiImage = UIImage(data: newPhotoData) {
            HStack {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                Spacer()
                Text("New photo")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if item.hasLocationPhoto {
            HStack {
                PhotoView(item: item, kind: .location, size: .thumbnail(240)) { image in
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: 80, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                } placeholder: {
                    ProgressView().frame(width: 80, height: 80)
                }
                Spacer()
                Text("Current photo")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            Text("No photo yet")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func save() {
        isSaving = true
        let locationId = selectedLocationId == Self.unassignedSentinel ? nil : selectedLocationId
        Task {
            await viewModel.applyNFCUpdate(itemId: item.id, locationId: locationId, photoData: newPhotoData)
            isSaving = false
            dismiss()
        }
    }
}
