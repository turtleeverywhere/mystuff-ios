import Foundation

struct Location: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var name: String
    var emoji: String?
    var createdAt: Date

    init(
        id: String = UUID().uuidString,
        name: String,
        emoji: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.createdAt = createdAt
    }
}
