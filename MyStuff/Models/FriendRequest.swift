import Foundation

enum FriendRequestStatus: String, Codable, Sendable {
    case pending
    case accepted
    case declined
}

/// A connection request between two existing users. Denormalizes BOTH users'
/// profiles so either side can build its `Friend` subdoc without extra reads.
struct FriendRequest: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var fromUid: String
    var fromEmail: String
    var fromName: String
    var fromPhotoURL: String?
    var toUid: String
    var toEmail: String
    var toName: String
    var toPhotoURL: String?
    var status: FriendRequestStatus
    var createdAt: Date
    var respondedAt: Date?

    init(
        id: String = UUID().uuidString,
        fromUid: String,
        fromEmail: String,
        fromName: String,
        fromPhotoURL: String? = nil,
        toUid: String,
        toEmail: String,
        toName: String,
        toPhotoURL: String? = nil,
        status: FriendRequestStatus = .pending,
        createdAt: Date = .now,
        respondedAt: Date? = nil
    ) {
        self.id = id
        self.fromUid = fromUid
        self.fromEmail = fromEmail
        self.fromName = fromName
        self.fromPhotoURL = fromPhotoURL
        self.toUid = toUid
        self.toEmail = toEmail
        self.toName = toName
        self.toPhotoURL = toPhotoURL
        self.status = status
        self.createdAt = createdAt
        self.respondedAt = respondedAt
    }
}
