import Foundation

/// Encoded bytes of an item's **item** photo, resolved the way `PhotoView` does:
/// the local file first, else the remote copy (which is then kept locally).
enum ItemPhotoLoader {
    @MainActor
    static func data(for item: Item) async -> Data? {
        let local = PhotoUploadManager.shared.localFullURL(itemId: item.id, filename: "item_photo")
        if let data = try? Data(contentsOf: local) { return data }

        guard let remote = item.remoteItemPhotoURL.flatMap(URL.init(string:)),
              let (data, _) = try? await URLSession.shared.data(from: remote)
        else { return nil }
        try? data.write(to: local)
        return data
    }
}
