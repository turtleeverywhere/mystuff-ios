import Foundation

/// A confirmed connection, stored at `users/{uid}/friends/{friendUid}`.
/// Denormalized so the friends list renders without extra profile reads.
struct Friend: Identifiable, Codable, Hashable, Sendable {
    var uid: String
    var email: String
    var displayName: String
    var photoURL: String?
    var since: Date

    var id: String { uid }

    init(uid: String, email: String, displayName: String, photoURL: String? = nil, since: Date = .now) {
        self.uid = uid
        self.email = email
        self.displayName = displayName
        self.photoURL = photoURL
        self.since = since
    }
}
