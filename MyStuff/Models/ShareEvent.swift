import Foundation

/// A single coalesced-share event. One doc per recipient in top-level `shareEvents`.
/// A Cloud Function turns each into exactly one push notification.
struct ShareEvent: Identifiable, Codable, Sendable {
    var id: String
    var ownerId: String
    var recipientUid: String
    var locationId: String
    var locationName: String
    var itemCount: Int
    var sublocationCount: Int
    var createdAt: Date

    init(
        id: String = UUID().uuidString,
        ownerId: String,
        recipientUid: String,
        locationId: String,
        locationName: String,
        itemCount: Int,
        sublocationCount: Int,
        createdAt: Date = .now
    ) {
        self.id = id
        self.ownerId = ownerId
        self.recipientUid = recipientUid
        self.locationId = locationId
        self.locationName = locationName
        self.itemCount = itemCount
        self.sublocationCount = sublocationCount
        self.createdAt = createdAt
    }
}
