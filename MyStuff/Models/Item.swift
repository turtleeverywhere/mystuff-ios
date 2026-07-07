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
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
