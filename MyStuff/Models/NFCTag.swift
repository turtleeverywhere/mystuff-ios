import Foundation

/// One physical NFC sticker paired to an item or location.
/// `uid` is the tag's hex serial and is the stable identity; `label` is a
/// display-only name the user can edit ("front", "inside lid"). Nothing is
/// written to the tag itself beyond the universal link.
struct NFCTag: Codable, Hashable, Sendable, Identifiable {
    var uid: String
    var label: String?

    var id: String { uid }

    init(uid: String, label: String? = nil) {
        self.uid = uid
        self.label = label
    }

    /// Trailing bytes of the serial, for when the tag has no user label.
    var shortSerial: String {
        uid.count <= 8 ? uid : "…" + uid.suffix(8)
    }

    /// What list rows show: the label when set, otherwise the short serial.
    var displayName: String {
        if let label, !label.isEmpty { return label }
        return shortSerial
    }
}
