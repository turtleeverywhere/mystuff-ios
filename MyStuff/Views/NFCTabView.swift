import SwiftUI

struct NFCTabView: View {
    @Bindable var viewModel: StuffViewModel

    @State private var nfcService: NFCService = CoreNFCService()
    @State private var isScanning = false
    @State private var errorMessage: String?
    @State private var pairingItem: Item?

    @State private var updateItem: Item?
    @State private var showPairSheet = false
    @State private var lastScannedSerial: String?
    @State private var lastUnknownTarget: AppLink.Target?

    @State private var showQRScanner = false
    @State private var path: [Location] = []

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "wave.3.right.circle.fill")
                    .font(.system(size: 96))
                    .foregroundStyle(Color.appAccent)
                    .symbolRenderingMode(.hierarchical)

                Text(headline)
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(subhead)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Spacer()

                if nfcService.isAvailable {
                    Button {
                        startScan()
                    } label: {
                        Label(isScanning ? "Scanning..." : "Scan Tag", systemImage: "wave.3.right")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.appAccent)
                    .controlSize(.large)
                    .disabled(isScanning)
                    .padding(.horizontal, 32)
                } else {
                    Text("NFC is not available on this device.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 32)
                }

                if QRScannerView.isSupported {
                    Button {
                        showQRScanner = true
                    } label: {
                        Label("Scan QR Code", systemImage: "qrcode.viewfinder")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.bordered)
                    .tint(Color.appAccent)
                    .controlSize(.large)
                    .padding(.horizontal, 32)
                }

                Spacer()
            }
            .navigationTitle("NFC/QR")
            .navigationDestination(for: Location.self) { loc in
                LocationDetailView(location: loc, viewModel: viewModel)
            }
            .sheet(isPresented: $showQRScanner) {
                QRScannerSheet { target in
                    handle(target: target)
                }
            }
            .sheet(item: $updateItem) { item in
                ItemQuickUpdateSheet(item: item, viewModel: viewModel)
            }
            .sheet(isPresented: $showPairSheet) {
                NFCPairSheet(viewModel: viewModel, nfcService: nfcService)
            }
            .alert("Scan Issue", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                if lastUnknownTarget != nil {
                    Button("Pair Tag") {
                        errorMessage = nil
                        lastUnknownTarget = nil
                        showPairSheet = true
                    }
                }
                Button("OK", role: .cancel) {
                    errorMessage = nil
                    lastUnknownTarget = nil
                }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .containerBackground(LinearGradient.appBackground, for: .navigation)
    }

    private var headline: String {
        if isScanning { return "Hold near tag..." }
        return "Tap a tag to update"
    }

    private var subhead: String {
        if isScanning { return "Move your iPhone close to the NFC sticker." }
        if !nfcService.isAvailable { return "" }
        return "Scan a tag or QR code. Item codes open a quick update; location codes open that location."
    }

    private func startScan() {
        isScanning = true
        Task {
            do {
                let result = try await nfcService.scan()
                isScanning = false
                handle(result: result)
            } catch NFCError.userCancelled {
                isScanning = false
            } catch {
                isScanning = false
                errorMessage = error.localizedDescription
            }
        }
    }

    private func handle(result: NFCScanResult) {
        lastScannedSerial = result.tagSerial
        guard let target = result.target else {
            // Blank/unknown tag → open pair flow
            HapticManager.impact()
            showPairSheet = true
            return
        }
        handle(target: target)
    }

    /// One dispatch point for both code kinds. What happens depends on the
    /// entity, not on whether it was scanned by NFC or camera: items open the
    /// quick re-shelve sheet, locations open their detail screen.
    private func handle(target: AppLink.Target) {
        switch target {
        case .item(let id):
            if let item = viewModel.items.first(where: { $0.id == id }) {
                HapticManager.success()
                updateItem = item
            } else {
                lastUnknownTarget = target
                errorMessage = "This tag is paired to an item that no longer exists. Would you like to pair it to something else?"
            }
        case .location(let id):
            if let location = viewModel.locations.first(where: { $0.id == id }) {
                HapticManager.success()
                path.append(location)
            } else {
                lastUnknownTarget = target
                errorMessage = "This tag is paired to a location that no longer exists. Would you like to pair it to something else?"
            }
        }
    }
}
