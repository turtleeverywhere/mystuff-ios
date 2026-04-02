import Foundation

struct Location: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var name: String
    var emoji: String?
    var parentId: String?
    var createdAt: Date

    init(
        id: String = UUID().uuidString,
        name: String,
        emoji: String? = nil,
        parentId: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.parentId = parentId
        self.createdAt = createdAt
    }
}
