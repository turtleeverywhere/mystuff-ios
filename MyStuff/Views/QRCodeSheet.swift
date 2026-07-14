import SwiftUI
import UIKit

/// Sheet that shows a location's QR sticker with Share (PNG/PDF) and Print actions.
struct QRCodeSheet: View {
    let location: Location
    @Environment(\.dismiss) private var dismiss

    @State private var qrImage: UIImage?
    @State private var pngURL: URL?
    @State private var pdfURL: URL?

    var body: some View {
        NavigationStack {
            Group {
                if let qrImage {
                    content(qrImage: qrImage)
                } else {
                    ContentUnavailableView("Couldn't generate code", systemImage: "qrcode")
                }
            }
            .navigationTitle("QR Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .task { prepare() }
    }

    @ViewBuilder
    private func content(qrImage: UIImage) -> some View {
        VStack(spacing: 24) {
            QRStickerView(location: location, qrImage: qrImage)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(radius: 8)

            HStack(spacing: 16) {
                if let pdfURL {
                    ShareLink(item: pdfURL,
                              preview: SharePreview("\(location.name) QR", image: Image(uiImage: qrImage))) {
                        Label("Share PDF", systemImage: "doc")
                    }
                }
                if let pngURL {
                    ShareLink(item: pngURL,
                              preview: SharePreview("\(location.name) QR", image: Image(uiImage: qrImage))) {
                        Label("Share PNG", systemImage: "photo")
                    }
                }
            }

            Button {
                printSticker()
            } label: {
                Label("Print", systemImage: "printer")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.appAccent)
            .disabled(pdfURL == nil)
            .padding(.horizontal)

            Spacer()
        }
        .padding()
    }

    // MARK: - Export

    @MainActor
    private func prepare() {
        let urlString = AppLink.url(for: .location(location.id)).absoluteString
        guard let qr = QRCodeGenerator.image(for: urlString) else { return }
        qrImage = qr

        let renderer = ImageRenderer(content: QRStickerView(location: location, qrImage: qr))
        renderer.scale = 3

        if let uiImage = renderer.uiImage, let data = uiImage.pngData() {
            pngURL = writeTemp(data, ext: "png")
        }
        if let data = renderPDF(renderer) {
            pdfURL = writeTemp(data, ext: "pdf")
        }
    }

    private func renderPDF(_ renderer: ImageRenderer<QRStickerView>) -> Data? {
        let pdfData = NSMutableData()
        renderer.render { size, renderInContext in
            var box = CGRect(origin: .zero, size: size)
            guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
                  let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else { return }
            ctx.beginPDFPage(nil)
            renderInContext(ctx)
            ctx.endPDFPage()
            ctx.closePDF()
        }
        return pdfData.length > 0 ? (pdfData as Data) : nil
    }

    private func writeTemp(_ data: Data, ext: String) -> URL? {
        let safe = location.name
            .components(separatedBy: CharacterSet(charactersIn: "/\\:")).joined(separator: "-")
        let name = safe.isEmpty ? "location" : safe
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-qr.\(ext)")
        do { try data.write(to: url); return url } catch { return nil }
    }

    private func printSticker() {
        guard let pdfURL, let data = try? Data(contentsOf: pdfURL) else { return }
        let info = UIPrintInfo(dictionary: nil)
        info.jobName = "\(location.name) QR"
        info.outputType = .general
        let controller = UIPrintInteractionController.shared
        controller.printInfo = info
        controller.printingItem = data
        if let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow }) {
            controller.present(from: window.bounds, in: window, animated: true, completionHandler: nil)
        } else {
            controller.present(animated: true, completionHandler: nil)
        }
    }
}
