import AVFoundation
import PhotosUI
import SwiftUI
import VisionKit

/// Handle on the live scanner so SwiftUI can ask it for a still.
@MainActor
final class ScanCameraController {
    weak var scanner: DataScannerViewController?

    /// A JPEG still from the running scanner; nil when no scanner is attached
    /// or the capture failed.
    func capturePhoto() async -> Data? {
        guard let scanner, let image = try? await scanner.capturePhoto() else { return nil }
        return image.jpegData(compressionQuality: 0.9)
    }
}

/// Camera viewfinder with a reticle and shutter, shared by the scan session and
/// "Add angles". Also reports QR payloads seen in frame. Where the live scanner
/// is unavailable (simulator, older hardware) it offers the photo library instead.
struct ScanCaptureStage<Accessory: View>: View {
    /// Disables the shutter while the caller is still working on the last photo.
    let isBusy: Bool
    var onCode: (String) -> Void = { _ in }
    /// Receives encoded image bytes for each shot.
    let onPhoto: (Data) -> Void
    /// Shown just above the shutter — status text, the tray.
    @ViewBuilder var accessory: () -> Accessory

    @State private var controller = ScanCameraController()
    @State private var authStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var isCapturing = false
    @State private var libraryPick: PhotosPickerItem?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if !QRScannerView.isSupported {
                libraryFallback
            } else {
                switch authStatus {
                case .authorized:
                    camera
                case .notDetermined:
                    Color.clear.task { await requestAccess() }
                default:
                    cameraDenied
                }
            }
        }
        .environment(\.colorScheme, .dark)
        .onChange(of: libraryPick) {
            guard let libraryPick else { return }
            Task {
                if let data = try? await libraryPick.loadTransferable(type: Data.self) {
                    onPhoto(data)
                }
                self.libraryPick = nil
            }
        }
    }

    private var camera: some View {
        QRScannerView(controller: controller, onScan: onCode)
            .ignoresSafeArea()
            .overlay { reticle }
            .overlay(alignment: .bottom) {
                VStack(spacing: 16) {
                    accessory()
                    shutter
                }
                .padding(.bottom, 24)
            }
    }

    /// Where to hold the item. Guidance only — the crop follows the detected subject.
    private var reticle: some View {
        RoundedRectangle(cornerRadius: 24)
            .strokeBorder(.white.opacity(0.8), lineWidth: 2)
            .aspectRatio(1, contentMode: .fit)
            .padding(48)
            .allowsHitTesting(false)
    }

    private var shutter: some View {
        Button {
            takePhoto()
        } label: {
            ZStack {
                Circle().fill(.white).frame(width: 66, height: 66)
                Circle().strokeBorder(.white, lineWidth: 3).frame(width: 78, height: 78)
            }
        }
        .disabled(isBusy || isCapturing)
        .opacity(isBusy || isCapturing ? 0.4 : 1)
        .accessibilityLabel("Capture item")
    }

    private var libraryFallback: some View {
        VStack(spacing: 20) {
            ContentUnavailableView(
                "Camera unavailable",
                systemImage: "camera",
                description: Text("Choose a photo of the item instead.")
            )
            .fixedSize(horizontal: false, vertical: true)
            accessory()
            PhotosPicker(selection: $libraryPick, matching: .images) {
                Label("Choose Photo", systemImage: "photo.on.rectangle")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isBusy)
        }
        .padding()
    }

    private var cameraDenied: some View {
        ContentUnavailableView {
            Label("Camera access needed", systemImage: "camera.fill")
        } description: {
            Text("Allow camera access in Settings to scan items.")
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

    private func takePhoto() {
        isCapturing = true
        Task {
            if let data = await controller.capturePhoto() {
                onPhoto(data)
            }
            isCapturing = false
        }
    }
}
