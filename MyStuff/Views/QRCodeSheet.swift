import SwiftUI
import UIKit

/// Sheet that shows a location's QR sticker with Share (PNG/PDF) and Print actions.
struct QRCodeSheet: View {
    let location: Location
    let viewModel: StuffViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var qrImage: UIImage?
    @State private var pngURL: URL?
    @State private var pdfURL: URL?
    @State private var size: QRTileSize = .medium
    @State private var showIcon = true
    @State private var showName = true
    @State private var showBatch = false

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
        .task { render() }
        .onChange(of: size) { render() }
        .onChange(of: showIcon) { render() }
        .onChange(of: showName) { render() }
    }

    @ViewBuilder
    private func content(qrImage: UIImage) -> some View {
        VStack(spacing: 24) {
            QRTileView(location: location, qrImage: qrImage, size: size, showIcon: showIcon, showName: showName)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(radius: 6)

            VStack(spacing: 12) {
                Picker("QR size", selection: $size) {
                    ForEach(QRTileSize.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                Toggle("Include icon", isOn: $showIcon)
                Toggle("Include name", isOn: $showName)
            }
            .tint(Color.appAccent)
            .padding(.horizontal)

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

            Button {
                showBatch = true
            } label: {
                Label("Print Multiple…", systemImage: "square.grid.2x2")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
            .tint(Color.appAccent)
            .padding(.horizontal)

            Spacer()
        }
        .padding()
        .sheet(isPresented: $showBatch) {
            BatchQRPrintSheet(viewModel: viewModel, initialSelection: [location.id])
        }
    }

    // MARK: - Export

    /// (Re)builds the QR image and the PNG/PDF exports for the current size and
    /// icon/name toggles. Re-runs whenever one of those changes. The PDF places
    /// the tile on an A4 page at its actual size so print isn't scaled to fill.
    @MainActor
    private func render() {
        let urlString = AppLink.url(for: .location(location.id)).absoluteString
        guard let qr = qrImage ?? QRCodeGenerator.image(for: urlString) else { return }
        qrImage = qr

        let tile = QRTileView(location: location, qrImage: qr, size: size, showIcon: showIcon, showName: showName)
        let renderer = ImageRenderer(content: tile)
        renderer.scale = 3
        guard let image = renderer.uiImage else { return }

        if let data = image.pngData() {
            pngURL = writeTemp(data, ext: "png")
        }
        let pdf = QRSheetPDF.makePDF(tiles: [image], cell: size.cell(hasCaption: showIcon || showName))
        pdfURL = writeTemp(pdf, ext: "pdf")
    }

    private func writeTemp(_ data: Data, ext: String) -> URL? {
        let safe = location.name
            .components(separatedBy: CharacterSet(charactersIn: "/\\:")).joined(separator: "-")
        let name = safe.isEmpty ? "location" : safe
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(location.id.prefix(8))-qr.\(ext)")
        do { try data.write(to: url); return url } catch { return nil }
    }

    private func printSticker() {
        guard let pdfURL, let data = try? Data(contentsOf: pdfURL) else { return }
        PDFPrinter.print(data, jobName: "\(location.name) QR")
    }
}
