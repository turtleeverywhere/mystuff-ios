import Foundation

struct Item: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var name: String
    var notes: String?
    var locationId: String?
    var categoryId: String?
    var photoURL: String?
    var itemPhotoURL: String?
    var locationChangedAt: Date?
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
        locationChangedAt: Date? = nil,
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
        self.locationChangedAt = locationChangedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
