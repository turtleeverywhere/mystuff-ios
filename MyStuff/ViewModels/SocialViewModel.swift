import Foundation
import FirebaseAuth

/// Owns the social graph state (friends + requests) and orchestrates the flows.
/// Sibling to StuffViewModel; created and loaded in ContentView.
@MainActor
@Observable
final class SocialViewModel {

    var friends: [Friend] = []
    /// Pending only (filtered).
    var incomingRequests: [FriendRequest] = []
    /// Pending only (filtered).
    var outgoingRequests: [FriendRequest] = []
    var isLoading: Bool = false
    var errorMessage: String?

    private let service: SocialService = FirebaseSocialService()

    /// Set by ContentView: called on unfriend to strip shared memberIds between the two users.
    var onUnfriend: ((String) async -> Void)?

    var incomingPendingCount: Int { incomingRequests.count }

    // MARK: - Load

    func load() async {
        await upsertOwnProfile()
        isLoading = true
        defer { isLoading = false }
        do {
            async let f = service.fetchFriends()
            async let inc = service.fetchIncomingRequests()
            async let out = service.fetchOutgoingRequests()
            let friendsList = try await f
            let incoming = try await inc
            let outgoing = try await out
            friends = friendsList
            incomingRequests = incoming.filter { $0.status == .pending }
            outgoingRequests = outgoing.filter { $0.status == .pending }
            await reconcileAcceptedOutgoing(outgoing: outgoing, existingFriends: friendsList)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Real-time listeners for friends + requests + badge. Runs until the caller's task is cancelled.
    func liveSync() async {
        let service = self.service
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for await friends in service.friendsStream() {
                    await MainActor.run { self.friends = friends }
                }
            }
            group.addTask {
                for await incoming in service.incomingRequestsStream() {
                    let pending = incoming.filter { $0.status == .pending }
                    await MainActor.run { self.incomingRequests = pending }
                }
            }
            group.addTask {
                for await outgoing in service.outgoingRequestsStream() {
                    let pending = outgoing.filter { $0.status == .pending }
                    let currentFriends = await MainActor.run { () -> [Friend] in
                        self.outgoingRequests = pending
                        return self.friends
                    }
                    await self.reconcileAcceptedOutgoing(outgoing: outgoing, existingFriends: currentFriends)
                }
            }
        }
    }

    private func upsertOwnProfile() async {
        guard let user = Auth.auth().currentUser else { return }
        let email = (user.email ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let profile = UserProfile(
            uid: user.uid,
            email: email,
            displayName: user.displayName ?? (user.email ?? "User"),
            photoURL: user.photoURL?.absoluteString
        )
        try? await service.upsertProfile(profile)
    }

    /// The requester writes its own friend subdoc once the recipient has accepted.
    private func reconcileAcceptedOutgoing(outgoing: [FriendRequest], existingFriends: [Friend]) async {
        let friendIds = Set(existingFriends.map(\.uid))
        for req in outgoing where req.status == .accepted && !friendIds.contains(req.toUid) {
            let friend = Friend(uid: req.toUid, email: req.toEmail, displayName: req.toName, photoURL: req.toPhotoURL)
            do {
                try await service.addFriend(friend)
                if !friends.contains(where: { $0.uid == friend.uid }) {
                    friends.append(friend)
                }
            } catch {
                // Leave for the next load to retry; don't show an optimistic unpersisted friend.
            }
        }
    }

    // MARK: - Actions

    /// Returns true if a request was sent. On failure, sets `errorMessage` and returns false.
    func addFriend(email: String) async -> Bool {
        errorMessage = nil
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let me = Auth.auth().currentUser else {
            errorMessage = "You're not signed in."
            return false
        }
        guard !normalized.isEmpty else {
            errorMessage = "Enter an email."
            return false
        }
        if normalized == (me.email ?? "").lowercased() {
            errorMessage = "That's your own email."
            return false
        }
        do {
            guard let target = try await service.lookupUser(email: normalized) else {
                errorMessage = "No MyStuff user with that email."
                return false
            }
            if friends.contains(where: { $0.uid == target.uid }) {
                errorMessage = "You're already friends."
                return false
            }
            if let incoming = incomingRequests.first(where: { $0.fromUid == target.uid }) {
                // They already invited me — accept instead of sending a reversed request.
                await respond(to: incoming, accept: true)
                return true
            }
            if outgoingRequests.contains(where: { $0.toUid == target.uid }) {
                errorMessage = "Request already sent."
                return false
            }
            let request = FriendRequest(
                fromUid: me.uid,
                fromEmail: (me.email ?? "").lowercased(),
                fromName: me.displayName ?? (me.email ?? "User"),
                fromPhotoURL: me.photoURL?.absoluteString,
                toUid: target.uid,
                toEmail: target.email,
                toName: target.displayName,
                toPhotoURL: target.photoURL
            )
            try await service.sendFriendRequest(request)
            outgoingRequests.append(request)
            HapticManager.success()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func respond(to request: FriendRequest, accept: Bool) async {
        do {
            if accept {
                // Write the friendship BEFORE flipping status / removing from the list,
                // so a failure leaves the request pending and retryable.
                let friend = Friend(uid: request.fromUid, email: request.fromEmail, displayName: request.fromName, photoURL: request.fromPhotoURL)
                try await service.addFriend(friend)
                try await service.respondToRequest(request, accept: true)
                if !friends.contains(where: { $0.uid == friend.uid }) {
                    friends.append(friend)
                }
                incomingRequests.removeAll { $0.id == request.id }
                HapticManager.success()
            } else {
                try await service.respondToRequest(request, accept: false)
                incomingRequests.removeAll { $0.id == request.id }
                HapticManager.impact()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeFriend(_ friend: Friend) async {
        do {
            await onUnfriend?(friend.uid)
            try await service.removeFriend(uid: friend.uid)
            friends.removeAll { $0.uid == friend.uid }
            HapticManager.impact()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
