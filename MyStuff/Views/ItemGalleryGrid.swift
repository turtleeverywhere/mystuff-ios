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
        tileBody
            .itemTapGestures(
                previewEnabled: hasPhoto && onDoubleTap != nil,
                onPreview: { onDoubleTap?(item) },
                onOpen: {
                    if hasPhoto {
                        onTap(item)
                    } else {
                        onAddPhoto(item)
                    }
                }
            )
    }

    private var tileBody: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if hasPhoto {
                    PhotoView(
                        item: item,
                        kind: kind,
                        size: .thumbnail(480)
                    ) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        placeholderFill
                    }
                } else {
                    placeholderFill
                }
            }
            .overlay(alignment: .bottom) {
                nameOverlay
            }
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 4) {
                    if isMisplaced {
                        MisplacedBadge(iconOnly: true)
                    }
                    if !item.pairedTags.isEmpty {
                        NFCBadge(iconOnly: true)
                    }
                }
                .padding(6)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .accessibilityAddTraits(.isButton)
    }

    private var nameOverlay: some View {
        Text(item.name)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.white)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(
                LinearGradient(
                    colors: [.clear, .black.opacity(0.55)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
    }

    private var placeholderFill: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
            Image(systemName: "photo")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
        }
    }
}

#Preview {
    ScrollView {
        ItemGalleryGrid(
            items: [
                Item(name: "Passport"),
                Item(name: "Camping tent with a very long name that wraps")
            ],
            kind: .item,
            onTap: { _ in },
            onAddPhoto: { _ in }
        )
        .padding()
    }
}
