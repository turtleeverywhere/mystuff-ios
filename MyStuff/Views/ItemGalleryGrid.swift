import SwiftUI

/// Photo grid with configurable column count, used by the Home and Items gallery modes.
struct ItemGalleryGrid<TileMenu: View>: View {
    let items: [Item]
    /// Per-item misplaced flag. Injected because this grid has no view model.
    let isMisplaced: (Item) -> Bool
    let kind: PhotoKind
    let columns: Int
    let onTap: (Item) -> Void
    let onAddPhoto: (Item) -> Void
    let onDoubleTap: ((Item) -> Void)?
    let tileMenu: ((Item) -> TileMenu)?

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12), count: max(1, columns))
    }

    init(
        items: [Item],
        isMisplaced: @escaping (Item) -> Bool = { _ in false },
        kind: PhotoKind,
        columns: Int = 2,
        onTap: @escaping (Item) -> Void,
        onAddPhoto: @escaping (Item) -> Void,
        onDoubleTap: ((Item) -> Void)? = nil,
        @ViewBuilder tileMenu: @escaping (Item) -> TileMenu
    ) {
        self.items = items
        self.isMisplaced = isMisplaced
        self.kind = kind
        self.columns = columns
        self.onTap = onTap
        self.onAddPhoto = onAddPhoto
        self.onDoubleTap = onDoubleTap
        self.tileMenu = tileMenu
    }

    var body: some View {
        LazyVGrid(columns: gridColumns, spacing: 12) {
            ForEach(items) { item in
                tile(item)
            }
        }
    }

    @ViewBuilder
    private func tile(_ item: Item) -> some View {
        let base = GalleryTile(
            item: item,
            isMisplaced: isMisplaced(item),
            kind: kind,
            onTap: onTap,
            onAddPhoto: onAddPhoto,
            onDoubleTap: onDoubleTap
        )
        if let tileMenu {
            base.contextMenu { tileMenu(item) }
        } else {
            base
        }
    }
}

extension ItemGalleryGrid where TileMenu == EmptyView {
    init(
        items: [Item],
        isMisplaced: @escaping (Item) -> Bool = { _ in false },
        kind: PhotoKind,
        columns: Int = 2,
        onTap: @escaping (Item) -> Void,
        onAddPhoto: @escaping (Item) -> Void,
        onDoubleTap: ((Item) -> Void)? = nil
    ) {
        self.items = items
        self.isMisplaced = isMisplaced
        self.kind = kind
        self.columns = columns
        self.onTap = onTap
        self.onAddPhoto = onAddPhoto
        self.onDoubleTap = onDoubleTap
        self.tileMenu = nil
    }
}

// MARK: - Tile

private struct GalleryTile: View {
    let item: Item
    let isMisplaced: Bool
    let kind: PhotoKind
    let onTap: (Item) -> Void
    let onAddPhoto: (Item) -> Void
    let onDoubleTap: ((Item) -> Void)?

    private var hasPhoto: Bool {
        kind == .item ? item.hasItemPhoto : item.hasLocationPhoto
    }

    var body: some View {
        if hasPhoto, let onDoubleTap {
            tileButton.highPriorityGesture(TapGesture(count: 2).onEnded { onDoubleTap(item) })
        } else {
            tileButton
        }
    }

    private var tileButton: some View {
        Button { onTap(item) } label: {
            VStack(alignment: .leading, spacing: 0) {
                Color.appSurfaceMuted
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        if hasPhoto {
                            PhotoView(item: item, kind: kind, size: .thumbnail(480)) { image in
                                image.resizable().scaledToFill()
                            } placeholder: { placeholderFill }
                        } else { placeholderFill }
                    }
                    .overlay(alignment: .topTrailing) {
                        HStack(spacing: 4) {
                            if isMisplaced { MisplacedBadge(iconOnly: true) }
                            if !item.pairedTags.isEmpty { NFCBadge(iconOnly: true) }
                        }
                        .padding(8)
                    }
                    .clipped()
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.appText)
                        .fixedSize(horizontal: false, vertical: true)
                    if let changedAt = item.locationChangedAt {
                        Text("Stored \(changedAt, format: .relative(presentation: .named))")
                            .font(.caption).foregroundStyle(Color.appTertiary)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.appSurface)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.appBorder, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .accessibilityAction(named: Text(hasPhoto ? "Change photo" : "Add photo")) { onAddPhoto(item) }
        .accessibilityLabel(item.name)
        .accessibilityHint("Opens item details")

    }

    private var placeholderFill: some View {
        VStack(spacing: 8) {
            Image(systemName: "shippingbox")
                .font(.largeTitle).symbolRenderingMode(.hierarchical)
            Text("No photo yet").font(.caption)
        }
        .foregroundStyle(Color.appTertiary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appSurfaceMuted)
        .accessibilityHidden(true)
    }

}

#Preview {
    ScrollView {
        ItemGalleryGrid(
            items: [
                Item(name: "Passport"),
                Item(name: "Camping tent with a very long name that wraps", locationChangedAt: .now.addingTimeInterval(-86_400 * 3))
            ],
            kind: .item,
            onTap: { _ in },
            onAddPhoto: { _ in }
        )
        .padding()
    }
}
