import Foundation

/// In-memory SocialService for previews/dev. Recognizes one canned lookup email.
final class MockSocialService: SocialService, @unchecked Sendable {

    let currentUserId = "mock-user"

    private var incoming: [FriendRequest] = []
    private var outgoing: [FriendRequest] = []
    private var friends: [Friend] = []

    /// Lookup returns this profile for "friend@example.com"; nil otherwise.
    private let cannedUser = UserProfile(uid: "friend-uid", email: "friend@example.com", displayName: "Sam Friend")

    func upsertProfile(_ profile: UserProfile) async throws {}

    func lookupUser(email: String) async throws -> UserProfile? {
        email == cannedUser.email ? cannedUser : nil
    }

    func sendFriendRequest(_ request: FriendRequest) async throws {
        outgoing.append(request)
    }

    func fetchIncomingRequests() async throws -> [FriendRequest] { incoming }
    func fetchOutgoingRequests() async throws -> [FriendRequest] { outgoing }

    func respondToRequest(_ request: FriendRequest, accept: Bool) async throws {
        if let i = incoming.firstIndex(where: { $0.id == request.id }) {
            incoming[i].status = accept ? .accepted : .declined
            incoming[i].respondedAt = .now
        }
    }

    func fetchFriends() async throws -> [Friend] { friends }

    func addFriend(_ friend: Friend) async throws {
        if !friends.contains(where: { $0.uid == friend.uid }) { friends.append(friend) }
    }

    func removeFriend(uid: String) async throws {
        friends.removeAll { $0.uid == uid }
    }

    // MARK: - Live streams

    func friendsStream() -> AsyncStream<[Friend]> {
        AsyncStream { continuation in continuation.yield(friends); continuation.finish() }
    }
    func incomingRequestsStream() -> AsyncStream<[FriendRequest]> {
        AsyncStream { continuation in continuation.yield(incoming); continuation.finish() }
    }
    func outgoingRequestsStream() -> AsyncStream<[FriendRequest]> {
        AsyncStream { continuation in continuation.yield(outgoing); continuation.finish() }
    }
}
