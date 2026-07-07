import PhotosUI
import SwiftUI

/// Bottom sheet shown after scanning a paired NFC tag.
/// Lets the user update the item's location photo and current location.
struct NFCUpdateSheet: View {
    let item: Item
    @Bindable var viewModel: StuffViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedLocationId: String
    @State private var newPhotoData: Data?
    @State private var showLocationFormSheet = false
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
                    Picker("Location", selection: $selectedLocationId) {
                        Text("Unassigned").tag(Self.unassignedSentinel)
                        ForEach(viewModel.flattenedLocationTree(), id: \.location.id) { entry in
                            Text(String(repeating: "  ", count: entry.depth) + (entry.location.emoji ?? "📍") + " " + entry.location.name)
                                .tag(entry.location.id)
                        }
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
                onSave: { name, emoji, parentId in
                    Task {
                        await viewModel.addLocation(name: name, emoji: emoji, parentId: parentId)
                        if let newLoc = viewModel.locations.last(where: { $0.name == name && $0.parentId == parentId }) {
                            selectedLocationId = newLoc.id
                        }
                    }
                }
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
