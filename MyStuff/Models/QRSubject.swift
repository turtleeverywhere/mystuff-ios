import Foundation

/// What the QR renderer needs to draw a sticker, independent of entity kind.
struct QRSubject: Identifiable, Hashable {
    let target: AppLink.Target
    let name: String
    /// Emoji drawn in the tile caption.
    let icon: String

    var id: String { target.id }

    /// The universal link encoded into the QR image.
    var urlString: String { AppLink.url(for: target).absoluteString }
}
