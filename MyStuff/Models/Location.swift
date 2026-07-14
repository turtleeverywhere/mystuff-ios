import Foundation

struct Location: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var name: String
    var emoji: String?
    var parentId: String?
    /// Owner's uid. Writes route to `users/{ownerId}/locations`. nil on legacy docs until migrated.
    var ownerId: String?
    /// `[ownerId] + sharedWith`. The array queried for visibility. nil on legacy docs until migrated.
    var memberIds: [String]?
    var createdAt: Date

    init(
        id: String = UUID().uuidString,
        name: String,
        emoji: String? = nil,
        parentId: String? = nil,
        ownerId: String? = nil,
        memberIds: [String]? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.parentId = parentId
        self.ownerId = ownerId
        self.memberIds = memberIds
        self.createdAt = createdAt
    }

    /// Non-optional membership convenience; falls back to `[ownerId]` for legacy docs.
    var members: [String] {
        if let memberIds, !memberIds.isEmpty { return memberIds }
        if let ownerId { return [ownerId] }
        return []
    }
}
