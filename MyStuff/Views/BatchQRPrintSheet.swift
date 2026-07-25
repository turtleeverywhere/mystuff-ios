import SwiftUI
import UIKit

/// A QR sticker size preset for batch printing. Larger = easier to scan but
/// fewer per page; smaller = more per page, less paper.
enum QRTileSize: String, CaseIterable, Identifiable {
    case small, medium, large

    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    /// Side length of the QR image within a tile (points).
    var qrSide: CGFloat {
        switch self {
        case .small: return 88
        case .medium: return 128
        case .large: return 170
        }
    }

    /// Fixed cell size the tile occupies in the grid (points). With a caption,
    /// height leaves room for a two-line name under the code; without, the cell
    /// hugs the QR so more fit per page.
    func cell(hasCaption: Bool) -> CGSize {
        CGSize(width: qrSide + (hasCaption ? 34 : 20),
               height: qrSide + (hasCaption ? 52 : 20))
    }
}

/// A single QR + emoji + name tile, fixed-size for grid packing and export.
struct QRTileView: View {
    let subject: QRSubject
    let qrImage: UIImage
    let size: QRTileSize
    var showIcon: Bool = true
    var showName: Bool = true

    private var showsCaption: Bool { showIcon || showName }

    var body: some View {
        VStack(spacing: showsCaption ? 6 : 0) {
            Image(uiImage: qrImage)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(width: size.qrSide, height: size.qrSide)

            if showsCaption {
                HStack(spacing: 3) {
                    if showIcon {
                        Text(subject.icon)
                            .font(.system(size: max(10, size.qrSide * 0.13)))
                    }
                    if showName {
                        Text(subject.name)
                            .font(.system(size: max(8, size.qrSide * 0.11), weight: .semibold))
                            .foregroundStyle(.black)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.6)
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .frame(width: size.cell(hasCaption: showsCaption).width,
               height: size.cell(hasCaption: showsCaption).height)
        .background(Color.white)
    }
}

/// Tiles QR stickers onto A4 pages, packing as many as fit per page.
enum QRSheetPDF {
    static let a4 = CGSize(width: 595.2, height: 841.8) // 72 dpi points
    static let margin: CGFloat = 24
    static let gap: CGFloat = 12

    static func gridInfo(cell: CGSize, page: CGSize = a4) -> (cols: Int, rows: Int, perPage: Int) {
        let usableW = page.width - 2 * margin
        let usableH = page.height - 2 * margin
        let cols = max(1, Int((usableW + gap) / (cell.width + gap)))
        let rows = max(1, Int((usableH + gap) / (cell.height + gap)))
        return (cols, rows, cols * rows)
    }

    @MainActor
    static func makePDF(tiles: [UIImage], cell: CGSize, page: CGSize = a4) -> Data {
        let (cols, _, perPage) = gridInfo(cell: cell, page: page)
        let gridW = CGFloat(cols) * cell.width + CGFloat(cols - 1) * gap
        let startX = max(margin, (page.width - gridW) / 2)

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: page))
        return renderer.pdfData { ctx in
            for (i, img) in tiles.enumerated() {
                let pos = i % perPage
                if pos == 0 { ctx.beginPage() }
                let col = pos % cols
                let row = pos / cols
                let x = startX + CGFloat(col) * (cell.width + gap)
                let y = margin + CGFloat(row) * (cell.height + gap)
                img.draw(in: CGRect(x: x, y: y, width: cell.width, height: cell.height))
            }
        }
    }
}

/// Lets the user pick multiple items and locations and print their QR codes
/// packed efficiently onto A4 pages to save paper.
struct BatchQRPrintSheet: View {
    let viewModel: StuffViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedIds: Set<AppLink.Target>
    @State private var size: QRTileSize = .medium
    @State private var showIcon = true
    @State private var showName = true

    init(viewModel: StuffViewModel, initialSelection: Set<AppLink.Target> = []) {
        self.viewModel = viewModel
        _selectedIds = State(initialValue: initialSelection)
    }

    /// Locations in tree order, paired with their indent depth.
    private var locationEntries: [(location: Location, depth: Int)] {
        viewModel.flattenedLocationTree()
    }

    private var itemEntries: [Item] {
        viewModel.items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var allTargets: [AppLink.Target] {
        locationEntries.map { .location($0.location.id) } + itemEntries.map { .item($0.id) }
    }

    private var allSelected: Bool {
        !allTargets.isEmpty && selectedIds.count == allTargets.count
    }

    private var hasCaption: Bool { showIcon || showName }

    private var perPage: Int { QRSheetPDF.gridInfo(cell: size.cell(hasCaption: hasCaption)).perPage }

    private var pageCount: Int {
        selectedIds.isEmpty ? 0 : Int(ceil(Double(selectedIds.count) / Double(perPage)))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("QR size", selection: $size) {
                        ForEach(QRTileSize.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    Toggle("Include icon", isOn: $showIcon)
                        .tint(Color.appAccent)
                    Toggle("Include name", isOn: $showName)
                        .tint(Color.appAccent)
                } footer: {
                    Text(summary)
                }

                Section {
                    ForEach(locationEntries, id: \.location.id) { entry in
                        selectRow(
                            target: .location(entry.location.id),
                            icon: entry.location.emoji ?? "📍",
                            name: entry.location.name,
                            indent: CGFloat(entry.depth) * 16
                        )
                    }
                } header: {
                    HStack {
                        Text("Locations")
                        Spacer()
                        Button(allSelected ? "Clear" : "Select All") { toggleAll() }
                            .font(.caption)
                            .textCase(nil)
                    }
                }

                Section("Items") {
                    ForEach(itemEntries) { item in
                        selectRow(target: .item(item.id), icon: "📦", name: item.name, indent: 0)
                    }
                }
            }
            .navigationTitle("Print Multiple")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        shareSheets()
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(selectedIds.isEmpty)

                    Button("Print") { printSheets() }
                        .disabled(selectedIds.isEmpty)
                }
            }
        }
        .presentationDetents([.large])
    }

    private var summary: String {
        guard !selectedIds.isEmpty else { return "Select items or locations to print." }
        return "\(selectedIds.count) selected · \(perPage) per A4 page · \(pageCount) page\(pageCount == 1 ? "" : "s")"
    }

    @ViewBuilder
    private func selectRow(target: AppLink.Target, icon: String, name: String, indent: CGFloat) -> some View {
        Button {
            toggle(target)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: selectedIds.contains(target) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selectedIds.contains(target) ? Color.appAccent : .secondary)
                Text(icon)
                Text(name)
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.leading, indent)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func toggle(_ target: AppLink.Target) {
        if selectedIds.contains(target) { selectedIds.remove(target) } else { selectedIds.insert(target) }
    }

    private func toggleAll() {
        selectedIds = allSelected ? [] : Set(allTargets)
    }

    /// Renders every selected target's tile and packs them into an A4 PDF.
    /// Order follows `allTargets` so locations lead and items follow.
    @MainActor
    private func makeBatchPDF() -> Data? {
        let subjects = allTargets
            .filter { selectedIds.contains($0) }
            .compactMap { viewModel.qrSubject(for: $0) }
        let tiles: [UIImage] = subjects.compactMap { subject in
            guard let qr = QRCodeGenerator.image(for: subject.urlString) else { return nil }
            let renderer = ImageRenderer(
                content: QRTileView(subject: subject, qrImage: qr, size: size, showIcon: showIcon, showName: showName)
            )
            renderer.scale = 3
            return renderer.uiImage
        }
        guard !tiles.isEmpty else { return nil }
        return QRSheetPDF.makePDF(tiles: tiles, cell: size.cell(hasCaption: hasCaption))
    }

    @MainActor
    private func printSheets() {
        guard let data = makeBatchPDF() else { return }
        // Don't dismiss: the AirPrint UI presents over this sheet; dismissing
        // here would tear it down immediately.
        PDFPrinter.print(data, jobName: "MyStuff QR codes")
    }

    @MainActor
    private func shareSheets() {
        guard let data = makeBatchPDF() else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mystuff-qr-codes.pdf")
        guard (try? data.write(to: url)) != nil else { return }
        PDFShare.present(url: url)
    }
}
