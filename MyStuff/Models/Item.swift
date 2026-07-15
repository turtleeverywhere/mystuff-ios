import Foundation

struct Item: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var name: String
    var notes: String?
    var locationId: String?
    var categoryId: String?
    /// Local hint — relative path "Photos/{id}_photo.jpg" or nil. Primary store for location photo.
    var photoURL: String?
    /// Local hint — relative path "Photos/{id}_item_photo.jpg" or nil. Primary store for item photo.
    var itemPhotoURL: String?
    /// Firebase Storage URL for location photo (full size). Used for cross-device sync.
    var remotePhotoURL: String?
    /// Firebase Storage URL for item photo (full size). Used for cross-device sync.
    var remoteItemPhotoURL: String?
    var locationChangedAt: Date?
    var nfcTagUID: String?
    /// When true, automatic member-propagation flows (e.g. moveLocation subtree share)
    /// skip this item. Manual sharing is unaffected. Optional so legacy docs missing the
    /// field decode cleanly — same idiom as ownerId/memberIds.
    var isPrivate: Bool?
    /// Owner's uid. Writes route to `users/{ownerId}/items`. nil on legacy docs until migrated.
    var ownerId: String?
    /// `[ownerId] + sharedWith`. The array queried for visibility. nil on legacy docs until migrated.
    var memberIds: [String]?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        name: String,
        notes: String? = nil,
        locationId: String? = nil,
        categoryId: String? = nil,
        photoURL: String? = nil,
        itemPhotoURL: String? = nil,
        remotePhotoURL: String? = nil,
        remoteItemPhotoURL: String? = nil,
        locationChangedAt: Date? = nil,
        nfcTagUID: String? = nil,
        isPrivate: Bool? = nil,
        ownerId: String? = nil,
        memberIds: [String]? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.notes = notes
        self.locationId = locationId
        self.categoryId = categoryId
        self.photoURL = photoURL
        self.itemPhotoURL = itemPhotoURL
        self.remotePhotoURL = remotePhotoURL
        self.remoteItemPhotoURL = remoteItemPhotoURL
        self.locationChangedAt = locationChangedAt
        self.nfcTagUID = nfcTagUID
        self.isPrivate = isPrivate
        self.ownerId = ownerId
        self.memberIds = memberIds
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Non-optional membership convenience; falls back to `[ownerId]` for legacy docs.
    var members: [String] {
        if let memberIds, !memberIds.isEmpty { return memberIds }
        if let ownerId { return [ownerId] }
        return []
    }
}
