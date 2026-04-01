import Foundation

struct Item: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var name: String
    var notes: String?
    var locationId: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        name: String,
        notes: String? = nil,
        locationId: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.notes = notes
        self.locationId = locationId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
