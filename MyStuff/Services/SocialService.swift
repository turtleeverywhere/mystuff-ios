import Foundation

/// CRUD for the social graph: profiles, friend requests, and friendships.
protocol SocialService: Sendable {
    /// Current authenticated user's uid; "" if unauthenticated (Firebase) or a constant (Mock).
    var currentUserId: String { get }

    /// Upsert the signed-in user's public profile at `users/{uid}` (merge).
    func upsertProfile(_ profile: UserProfile) async throws

    /// Resolve an email to a profile via the Cloud Function. nil if no such user.
    func lookupUser(email: String) async throws -> UserProfile?

    func sendFriendRequest(_ request: FriendRequest) async throws
    /// All requests where I am the recipient (any status).
    func fetchIncomingRequests() async throws -> [FriendRequest]
    /// All requests where I am the sender (any status).
    func fetchOutgoingRequests() async throws -> [FriendRequest]
    /// Set status to accepted/declined and stamp respondedAt.
    func respondToRequest(_ request: FriendRequest, accept: Bool) async throws

    func fetchFriends() async throws -> [Friend]
    /// Write a friend subdoc under MY uid (`users/{me}/friends/{friend.uid}`).
    func addFriend(_ friend: Friend) async throws
    /// Delete my friend subdoc for `uid`.
    func removeFriend(uid: String) async throws

    // MARK: - Live streams
    func friendsStream() -> AsyncStream<[Friend]>
    func incomingRequestsStream() -> AsyncStream<[FriendRequest]>
    func outgoingRequestsStream() -> AsyncStream<[FriendRequest]>
}

enum SocialError: LocalizedError {
    case notSignedIn
    case lookupFailed
    case userNotFound

    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "You're not signed in."
        case .lookupFailed: return "Couldn't reach the lookup service. Try again."
        case .userNotFound: return "No MyStuff user with that email."
        }
    }
}
