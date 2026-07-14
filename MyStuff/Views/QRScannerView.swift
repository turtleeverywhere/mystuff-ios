import SwiftUI
import VisionKit
import AVFoundation
import UIKit

/// VisionKit live QR scanner. Reports the first decoded barcode string via `onScan`.
struct QRScannerView: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    static var isSupported: Bool {
        DataScannerViewController.isSupported
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
/// codes surface an inline message and keep scanning. Handles camera
/// authorization explicitly (prompts when undetermined, offers Settings when denied).
struct QRScannerSheet: View {
    let onLocation: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var errorText: String?
    @State private var authStatus = AVCaptureDevice.authorizationStatus(for: .video)

    var body: some View {
        NavigationStack {
            Group {
                if !QRScannerView.isSupported {
                    ContentUnavailableView("Scanning unavailable",
                                           systemImage: "camera",
                                           description: Text("This device can’t scan QR codes."))
                } else {
                    switch authStatus {
                    case .authorized:
                        scanner
                    case .notDetermined:
                        Color.clear.task { await requestAccess() }
                    default:
                        cameraDenied
                    }
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

    private var scanner: some View {
        QRScannerView { payload in handle(payload) }
            .ignoresSafeArea(edges: .bottom)
            .overlay(alignment: .bottom) {
                if let errorText {
                    Text(errorText)
                        .font(.callout)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 32)
                }
            }
    }

    private var cameraDenied: some View {
        ContentUnavailableView {
            Label("Camera access needed", systemImage: "camera.fill")
        } description: {
            Text("Allow camera access in Settings to scan QR codes.")
        } actions: {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func requestAccess() async {
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        authStatus = granted ? .authorized : .denied
    }

    private func handle(_ payload: String) {
        guard let url = URL(string: payload), let target = AppLink.parse(url) else {
            errorText = "Not a MyStuff code"
            return
        }
        guard case .location(let id) = target else {
            errorText = "That’s not a location code"
            return
        }
        HapticManager.success()
        onLocation(id)
        dismiss()
    }
}
