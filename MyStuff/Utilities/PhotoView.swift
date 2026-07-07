import SwiftUI

/// Local-first photo loader for `Item` photos.
///
/// Resolution order:
///   1. Local thumbnail file (if `.thumbnail` size requested)
///   2. Local full-size file (downsampled if needed)
///   3. Remote URL — downloaded once, persisted to the local primary store
///   4. Placeholder
struct PhotoView<Content: View, Placeholder: View>: View {

    enum Kind {
        case location, item

        fileprivate var filename: String {
            switch self {
            case .location: return "photo"
            case .item: return "item_photo"
            }
        }
    }

    enum TargetSize {
        case thumbnail(CGFloat)
        case full

        fileprivate var maxPixelSize: CGFloat {
            switch self {
            case .thumbnail(let pts): return pts
            case .full: return .infinity
            }
        }
    }

    let item: Item
    let kind: Kind
    let size: TargetSize
    @ViewBuilder var content: (Image) -> Content
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var uiImage: UIImage?

    var body: some View {
        Group {
            if let uiImage {
                content(Image(uiImage: uiImage))
            } else {
                placeholder()
            }
        }
        .task(id: cacheKey) {
            uiImage = await resolve()
        }
    }

    private var cacheKey: String {
        let remote = (kind == .location ? item.remotePhotoURL : item.remoteItemPhotoURL) ?? ""
        let local = (kind == .location ? item.photoURL : item.itemPhotoURL) ?? ""
        let sizeTag: String
        switch size {
        case .thumbnail(let pts): sizeTag = "t\(Int(pts))"
        case .full: sizeTag = "full"
        }
        return "\(item.id)|\(kind.filename)|\(local)|\(remote)|\(sizeTag)"
    }

    private func resolve() async -> UIImage? {
        let filename = kind.filename
        let target = size.maxPixelSize

        let fullURL = PhotoUploadManager.shared.localFullURL(itemId: item.id, filename: filename)
        let thumbURL = PhotoUploadManager.shared.localThumbURL(itemId: item.id, filename: filename)
        let remoteString = (kind == .location ? item.remotePhotoURL : item.remoteItemPhotoURL)

        // 1. Local thumbnail (preferred for small renders).
        if case .thumbnail = size, FileManager.default.fileExists(atPath: thumbURL.path) {
            if let img = await ImageCache.shared.image(for: thumbURL, maxPixelSize: target) {
                return img
            }
        }

        // 2. Local full file.
        if FileManager.default.fileExists(atPath: fullURL.path) {
            if let img = await ImageCache.shared.image(for: fullURL, maxPixelSize: target) {
                return img
            }
        }

        // 3. Remote — download once, persist to local primary store.
        if let remoteString, let remoteURL = URL(string: remoteString) {
            if let img = await ImageCache.shared.image(
                for: remoteURL,
                maxPixelSize: target,
                persistTo: fullURL
            ) {
                return img
            }
        }

        return nil
    }
}

extension Item {
    var hasLocationPhoto: Bool { photoURL != nil || remotePhotoURL != nil }
    var hasItemPhoto: Bool { itemPhotoURL != nil || remoteItemPhotoURL != nil }
}
