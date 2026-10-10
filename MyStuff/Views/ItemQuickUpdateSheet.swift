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
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    itemSummary

                    VStack(alignment: .leading, spacing: 12) {
                        AppSectionHeading(title: "Storage location", subtitle: "Choose where this item will live.")
                        VStack(alignment: .leading, spacing: 12) {
                            LocationPickerRow(
                                viewModel: viewModel,
                                label: "Store in",
                                pickerTitle: "Store this item",
                                selection: locationBinding
                            )
                            Divider().overlay(Color.appBorder)
                            if QRScannerView.isSupported {
                                Button {
                                    showLocationScanner = true
                                } label: {
                                    Label("Scan location QR", systemImage: "qrcode.viewfinder")
                                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                }
                            }
                            NFCScanButton(accepts: .location) { target in
                                selectScanned(target)
                            } label: { scanning in
                                Label(scanning ? "Hold near tag…" : "Scan location NFC tag", systemImage: "wave.3.right")
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            }
                            Button {
                                showLocationFormSheet = true
                            } label: {
                                Label("New location", systemImage: "plus.circle")
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            }
                        }
                        .font(.body.weight(.medium))
                        .padding(16)
                        .appCard()
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        AppSectionHeading(title: "Location photo", subtitle: "Optional: capture the shelf or spot to find it later.")
                        VStack(alignment: .leading, spacing: 12) {
                            photoRow
                            Button {
                                showPhotoSource = true
                            } label: {
                                Label(newPhotoData != nil ? "Change photo" : "Add location photo", systemImage: "camera")
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            }
                            .font(.body.weight(.medium))
                        }
                        .padding(16)
                        .appCard()
                    }
                }
                .frame(maxWidth: 600)
                .padding(20)
                .frame(maxWidth: .infinity)
            }
            .background(Color.appBackground)
            .safeAreaInset(edge: .bottom) {
                Button(action: save) {
                    HStack(spacing: 10) {
                        if isSaving { ProgressView().tint(.appOnHero) }
                        Text(isSaving ? "Saving…" : "Save location")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(AppPrimaryButtonStyle())
                .disabled(isSaving)
                .frame(maxWidth: 600)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(Color.appBackground)
            }
            .disabled(isSaving)
            .navigationTitle("Store item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
            }
            .tint(.appPrimary)
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(isSaving)
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

    private var itemSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Ready to store", systemImage: "shippingbox")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.appHeroSecondary)
            Text(item.name)
                .font(.title2.weight(.bold))
                .foregroundStyle(Color.appOnHero)
                .accessibilityAddTraits(.isHeader)
            Text("Currently: " + (viewModel.location(for: item).map { viewModel.displayPath(for: $0) } ?? "Unassigned"))
                .font(.subheadline)
                .foregroundStyle(Color.appHeroSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color.appHero, in: RoundedRectangle(cornerRadius: 24))
    }

    @ViewBuilder
    private var photoRow: some View {
        if let newPhotoData, let uiImage = UIImage(data: newPhotoData) {
            HStack(spacing: 16) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .accessibilityLabel("New location photo")
                Text("New photo ready")
                    .font(.subheadline)
                    .foregroundStyle(Color.appTertiary)
            }
        } else if item.hasLocationPhoto {
            HStack(spacing: 16) {
                PhotoView(item: item, kind: .location, size: .thumbnail(240)) { image in
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: 80, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                } placeholder: {
                    ProgressView().frame(width: 80, height: 80)
                }
                .accessibilityLabel("Current location photo")
                Text("Current photo")
                    .font(.subheadline)
                    .foregroundStyle(Color.appTertiary)
            }
        } else {
            Label("No location photo yet", systemImage: "photo")
                .font(.subheadline)
                .foregroundStyle(Color.appTertiary)
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
