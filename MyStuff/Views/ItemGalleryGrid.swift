import SwiftUI

/// Which of an item's two photos a gallery tile shows.
enum GalleryPhotoKind {
    case item, location
}

/// Photo grid with configurable column count, used by the Home and Items gallery modes.
struct ItemGalleryGrid<TileMenu: View>: View {
    let items: [Item]
    let kind: GalleryPhotoKind
    let columns: Int
    let onTap: (Item) -> Void
    let onAddPhoto: (Item) -> Void
    let tileMenu: ((Item) -> TileMenu)?

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12), count: max(1, columns))
    }

    init(
        items: [Item],
        kind: GalleryPhotoKind,
        columns: Int = 2,
        onTap: @escaping (Item) -> Void,
        onAddPhoto: @escaping (Item) -> Void,
        @ViewBuilder tileMenu: @escaping (Item) -> TileMenu
    ) {
        self.items = items
        self.kind = kind
        self.columns = columns
        self.onTap = onTap
        self.onAddPhoto = onAddPhoto
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
            kind: kind,
            onTap: onTap,
            onAddPhoto: onAddPhoto
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
        kind: GalleryPhotoKind,
        columns: Int = 2,
        onTap: @escaping (Item) -> Void,
        onAddPhoto: @escaping (Item) -> Void
    ) {
        self.items = items
        self.kind = kind
        self.columns = columns
        self.onTap = onTap
        self.onAddPhoto = onAddPhoto
        self.tileMenu = nil
    }
}

// MARK: - Tile

private struct GalleryTile: View {
    let item: Item
    let kind: GalleryPhotoKind
    let onTap: (Item) -> Void
    let onAddPhoto: (Item) -> Void

    private var hasPhoto: Bool {
        kind == .item ? item.hasItemPhoto : item.hasLocationPhoto
    }

    var body: some View {
        tileBody
    }

    private var tileBody: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if hasPhoto {
                    PhotoView(
                        item: item,
                        kind: kind == .item ? .item : .location,
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
                if item.nfcTagUID != nil {
                    NFCBadge(iconOnly: true)
                        .padding(6)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .onTapGesture {
                if hasPhoto {
                    onTap(item)
                } else {
                    onAddPhoto(item)
                }
            }
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
