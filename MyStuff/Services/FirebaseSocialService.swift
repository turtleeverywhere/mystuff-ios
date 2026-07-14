import Foundation
import FirebaseAuth
import FirebaseFirestore

/// Firestore + Cloud Function backed SocialService.
///
/// Layout: profile at `users/{uid}`, friends at `users/{uid}/friends/{friendUid}`,
/// requests in top-level `friendRequests`. Email lookup goes through the
/// `lookupUserByEmail` v1 callable, invoked over URLSession with a Firebase ID token
/// (avoids adding the FirebaseFunctions SPM product).
final class FirebaseSocialService: SocialService, @unchecked Sendable {

    private static let functionsBaseURL = "https://us-central1-mystuff-b072d.cloudfunctions.net"

    private let db = Firestore.firestore()

    var currentUserId: String { Auth.auth().currentUser?.uid ?? "" }

    private var requestsCollection: CollectionReference { db.collection("friendRequests") }
    private func friendsCollection(_ uid: String) -> CollectionReference {
        db.collection("users").document(uid).collection("friends")
    }

    // MARK: - Profile

    func upsertProfile(_ profile: UserProfile) async throws {
        try db.collection("users").document(profile.uid).setData(from: profile, merge: true)
    }

    // MARK: - Lookup (Cloud Function)

    func lookupUser(email: String) async throws -> UserProfile? {
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }
        guard let user = Auth.auth().currentUser else { throw SocialError.notSignedIn }
        let token = try await user.getIDToken()

        guard let url = URL(string: "\(Self.functionsBaseURL)/lookupUserByEmail") else {
            throw SocialError.lookupFailed
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["data": ["email": normalized]])

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw SocialError.lookupFailed
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let result = json?["result"]
        guard let result, !(result is NSNull),
              let dict = result as? [String: Any],
              let uid = dict["uid"] as? String else {
            return nil  // no such user
        }
        let name = dict["displayName"] as? String ?? ""
        let photo = dict["photoURL"] as? String
        return UserProfile(uid: uid, email: normalized, displayName: name, photoURL: photo)
    }

    // MARK: - Requests

    func sendFriendRequest(_ request: FriendRequest) async throws {
        try requestsCollection.document(request.id).setData(from: request)
    }

    func fetchIncomingRequests() async throws -> [FriendRequest] {
        let snap = try await requestsCollection.whereField("toUid", isEqualTo: currentUserId).getDocuments()
        return try snap.documents.map { try $0.data(as: FriendRequest.self) }
    }

    func fetchOutgoingRequests() async throws -> [FriendRequest] {
        let snap = try await requestsCollection.whereField("fromUid", isEqualTo: currentUserId).getDocuments()
        return try snap.documents.map { try $0.data(as: FriendRequest.self) }
    }

    func respondToRequest(_ request: FriendRequest, accept: Bool) async throws {
        try await requestsCollection.document(request.id).updateData([
            "status": (accept ? FriendRequestStatus.accepted : .declined).rawValue,
            "respondedAt": Timestamp(date: .now)
        ])
    }

    // MARK: - Friends

    func fetchFriends() async throws -> [Friend] {
        let snap = try await friendsCollection(currentUserId).getDocuments()
        return try snap.documents.map { try $0.data(as: Friend.self) }
    }

    func addFriend(_ friend: Friend) async throws {
        try friendsCollection(currentUserId).document(friend.uid).setData(from: friend)
    }

    func removeFriend(uid: String) async throws {
        try await friendsCollection(currentUserId).document(uid).delete()
    }
}
