import SwiftUI

/// Reads an NFC tag and reports the entity it points at — the read-only twin of
/// `QRScannerSheet`, with the same `accepts` filter and callback contract so a
/// screen can offer both ways of picking the same entity. Renders nothing where
/// NFC is unavailable, mirroring how the QR buttons hide on unsupported devices.
struct NFCScanButton<Label: View>: View {
    /// Which code kinds this scan will resolve. Contexts like "move this item
    /// somewhere" only make sense for locations.
    let accepts: AppLink.TargetKind
    let onTarget: (AppLink.Target) -> Void
    /// Receives the scanning flag so callers can swap the title while the
    /// system's NFC sheet is up.
    let label: (Bool) -> Label

    @State private var nfcService: NFCService = CoreNFCService()
    @State private var isScanning = false
    @State private var errorMessage: String?

    init(
        accepts: AppLink.TargetKind = .any,
        onTarget: @escaping (AppLink.Target) -> Void,
        @ViewBuilder label: @escaping (Bool) -> Label
    ) {
        self.accepts = accepts
        self.onTarget = onTarget
        self.label = label
    }

    var body: some View {
        if nfcService.isAvailable {
            Button {
                scan()
            } label: {
                label(isScanning)
            }
            .disabled(isScanning)
            .alert("Scan Issue", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func scan() {
        isScanning = true
        Task {
            do {
                let result = try await nfcService.scan()
                isScanning = false
                guard let target = result.target else {
                    errorMessage = "This tag isn't paired to anything yet."
                    return
                }
                guard accepts.accepts(target) else {
                    errorMessage = accepts.rejectionMessage
                    return
                }
                HapticManager.success()
                onTarget(target)
            } catch NFCError.userCancelled {
                isScanning = false
            } catch {
                isScanning = false
                errorMessage = error.localizedDescription
            }
        }
    }
}
