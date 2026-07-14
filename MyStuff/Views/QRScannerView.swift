import SwiftUI
import VisionKit

/// VisionKit live QR scanner. Reports the first decoded barcode string via `onScan`.
struct QRScannerView: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    static var isSupported: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {
        try? vc.startScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onScan: (String) -> Void
        /// Last payload we forwarded, to suppress duplicate reports of the same
        /// continuously-visible code while still allowing a different code to fire.
        private var lastReported: String?

        init(onScan: @escaping (String) -> Void) { self.onScan = onScan }

        func dataScanner(_ scanner: DataScannerViewController,
                         didAdd addedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            handle(addedItems)
        }

        func dataScanner(_ scanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            handle([item])
        }

        private func handle(_ items: [RecognizedItem]) {
            for case let .barcode(barcode) in items {
                guard let payload = barcode.payloadStringValue else { continue }
                guard payload != lastReported else { return }
                lastReported = payload
                onScan(payload)
                return
            }
        }
    }
}

/// Sheet wrapper: presents the scanner, parses the code via `AppLink`,
/// and calls `onLocation(id)` for a location code. Non-location / non-app
/// codes surface an inline message and keep scanning.
struct QRScannerSheet: View {
    let onLocation: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Group {
                if QRScannerView.isSupported {
                    QRScannerView { payload in handle(payload) }
                        .ignoresSafeArea(edges: .bottom)
                } else {
                    ContentUnavailableView("Scanning unavailable",
                                           systemImage: "camera",
                                           description: Text("This device can't scan QR codes."))
                }
            }
            .overlay(alignment: .bottom) {
                if let errorText {
                    Text(errorText)
                        .font(.callout)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 32)
                }
            }
            .navigationTitle("Scan QR")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func handle(_ payload: String) {
        guard let url = URL(string: payload), let target = AppLink.parse(url) else {
            errorText = "Not a MyStuff code"
            return
        }
        guard case .location(let id) = target else {
            errorText = "That's not a location code"
            return
        }
        HapticManager.success()
        onLocation(id)
        dismiss()
    }
}
