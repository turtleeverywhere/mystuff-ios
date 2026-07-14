# Social Sharing — P1 Friends Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a user connect to another existing MyStuff user by email — send a friend request, accept/deny incoming ones — with an in-app pending-request badge on the account button. No sharing yet (that's P2).

**Architecture:** A new `SocialService` (Firebase + Mock) owns profile upsert, friend-request CRUD, and the friends subcollection. A new `SocialViewModel` (sibling to `StuffViewModel`) holds friends/requests state and orchestrates the flows. Email→uid resolution goes through a first-ever Cloud Function (`lookupUserByEmail`, v1 callable) so user profiles stay private; the app invokes it over plain `URLSession` with a Firebase ID token (no `FirebaseFunctions` SPM product, no Xcode project changes). Friendship is recorded as a `friends` subdoc on **each** side: the accepter writes its side on accept; the requester writes its side lazily on next load (reconciliation), both derivable from the `FriendRequest` which denormalizes both users' profiles.

**Tech Stack:** Swift 6 / SwiftUI, Firebase Auth + Firestore, Node.js Firebase Functions (v1 callable).

## Global Constraints

- iOS 26.0, Swift 6.0, bundle ID `com.flyingturtle.mystuff`.
- `@Observable` macro (not `ObservableObject`); `@Bindable` in views. Haptics via `HapticManager`.
- Firestore uses Codable (`data(as:)` / `setData(from:)`).
- **No test target exists.** Verification = compile via `xcodebuild` + deferred manual gates. Swift build command (run from repo root, ~30–90s, look for `** BUILD SUCCEEDED **`):
  ```
  xcodebuild -project MyStuff.xcodeproj -scheme MyStuff -destination 'generic/platform=iOS Simulator' -configuration Debug build
  ```
- Firebase prod project id: `mystuff-b072d`. Functions region: **us-central1**. The v1 callable URL is therefore exactly `https://us-central1-mystuff-b072d.cloudfunctions.net/lookupUserByEmail`.
- New Swift files go under `MyStuff/` (synchronized folder groups auto-include them in the target — no `.pbxproj` edits).
- Firestore security rules for `users/{uid}` (owner-only), `users/{uid}/friends/**` (owner-only), and `friendRequests/{id}` (create if `fromUid==auth.uid`; read/update if `auth.uid in [fromUid,toUid]`) were **already deployed in P0** — do not modify rules in P1.
- Email is always normalized to `trimmed.lowercased()` before storage, lookup, or comparison.
- **Deploying the Cloud Function requires the Firebase Blaze (pay-as-you-go) billing plan.** The prod project may currently be on Spark. The `firebase deploy --only functions` step is human-gated (the controller runs it after confirming billing); implementers only write + syntax-check the function.

---

### Task 1: Social domain models

**Files:**
- Create: `MyStuff/Models/UserProfile.swift`
- Create: `MyStuff/Models/FriendRequest.swift`
- Create: `MyStuff/Models/Friend.swift`

**Interfaces:**
- Produces:
  - `UserProfile { uid: String; email: String; displayName: String; photoURL: String? }`, `id == uid`.
  - `FriendRequestStatus` enum: `.pending .accepted .declined` (String-raw Codable).
  - `FriendRequest { id; fromUid; fromEmail; fromName; fromPhotoURL?; toUid; toEmail; toName; toPhotoURL?; status; createdAt; respondedAt? }`.
  - `Friend { uid; email; displayName; photoURL?; since: Date }`, `id == uid`.

- [ ] **Step 1: Create `UserProfile.swift`**

```swift
import Foundation

/// Minimal public-facing profile stored at `users/{uid}`. Written on sign-in;
/// resolved by email through the `lookupUserByEmail` Cloud Function.
struct UserProfile: Identifiable, Codable, Hashable, Sendable {
    var uid: String
    /// Normalized: trimmed + lowercased.
    var email: String
    var displayName: String
    var photoURL: String?

    var id: String { uid }

    init(uid: String, email: String, displayName: String, photoURL: String? = nil) {
        self.uid = uid
        self.email = email
        self.displayName = displayName
        self.photoURL = photoURL
    }
}
```

- [ ] **Step 2: Create `FriendRequest.swift`**

```swift
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
```

- [ ] **Step 3: Create `Friend.swift`**

```swift
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
```

- [ ] **Step 4: Build to verify**

Run: `xcodebuild -project MyStuff.xcodeproj -scheme MyStuff -destination 'generic/platform=iOS Simulator' -configuration Debug build 2>&1 | tail -20`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add MyStuff/Models/UserProfile.swift MyStuff/Models/FriendRequest.swift MyStuff/Models/Friend.swift
git commit -m "feat: add UserProfile, FriendRequest, Friend models

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: `SocialService` protocol + `MockSocialService`

**Files:**
- Create: `MyStuff/Services/SocialService.swift`
- Create: `MyStuff/Services/MockSocialService.swift`

**Interfaces:**
- Consumes: `UserProfile`, `FriendRequest`, `Friend` (Task 1).
- Produces:
  - `protocol SocialService: Sendable` with: `var currentUserId: String { get }`, `upsertProfile(_:)`, `lookupUser(email:) -> UserProfile?`, `sendFriendRequest(_:)`, `fetchIncomingRequests() -> [FriendRequest]`, `fetchOutgoingRequests() -> [FriendRequest]`, `respondToRequest(_:accept:)`, `fetchFriends() -> [Friend]`, `addFriend(_:)`, `removeFriend(uid:)`.
  - `enum SocialError: LocalizedError` cases `notSignedIn, lookupFailed, userNotFound`.

- [ ] **Step 1: Create `SocialService.swift`**

```swift
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
```

- [ ] **Step 2: Create `MockSocialService.swift`**

```swift
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
}
```

- [ ] **Step 3: Build to verify**

Run: `xcodebuild -project MyStuff.xcodeproj -scheme MyStuff -destination 'generic/platform=iOS Simulator' -configuration Debug build 2>&1 | tail -20`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add MyStuff/Services/SocialService.swift MyStuff/Services/MockSocialService.swift
git commit -m "feat: SocialService protocol + in-memory mock

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: `FirebaseSocialService`

**Files:**
- Create: `MyStuff/Services/FirebaseSocialService.swift`

**Interfaces:**
- Consumes: the `SocialService` protocol + `SocialError` (Task 2), models (Task 1).
- Produces: `final class FirebaseSocialService: SocialService, @unchecked Sendable` — the production implementation. `lookupUser` invokes the v1 callable over `URLSession`.

- [ ] **Step 1: Create `FirebaseSocialService.swift`**

```swift
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
```

- [ ] **Step 2: Build to verify**

Run: `xcodebuild -project MyStuff.xcodeproj -scheme MyStuff -destination 'generic/platform=iOS Simulator' -configuration Debug build 2>&1 | tail -20`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add MyStuff/Services/FirebaseSocialService.swift
git commit -m "feat: FirebaseSocialService (Firestore + callable lookup over URLSession)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: `lookupUserByEmail` Cloud Function (files only — deploy is human-gated)

**Files:**
- Create: `functions/package.json`
- Create: `functions/index.js`
- Create: `functions/.gitignore`
- Modify: `firebase.json`

**Interfaces:**
- Produces: v1 callable `lookupUserByEmail` at `https://us-central1-mystuff-b072d.cloudfunctions.net/lookupUserByEmail`. Auth required (`context.auth`). Input `{ email }`; output `{ uid, displayName, photoURL }` or `null`.

- [ ] **Step 1: Create `functions/package.json`**

```json
{
  "name": "functions",
  "description": "Cloud Functions for MyStuff",
  "engines": {
    "node": "20"
  },
  "main": "index.js",
  "dependencies": {
    "firebase-admin": "^12.6.0",
    "firebase-functions": "^5.1.0"
  },
  "private": true
}
```

- [ ] **Step 2: Create `functions/index.js`**

```javascript
const functions = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();

/**
 * Resolve an email to a minimal public profile. Keeps user profiles private:
 * clients cannot read the users collection directly; this runs with admin
 * privileges and returns only uid/displayName/photoURL.
 */
exports.lookupUserByEmail = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Must be signed in.");
  }
  const email = String((data && data.email) || "").trim().toLowerCase();
  if (!email) {
    throw new functions.https.HttpsError("invalid-argument", "Email required.");
  }
  const snap = await admin.firestore()
      .collection("users")
      .where("email", "==", email)
      .limit(1)
      .get();
  if (snap.empty) {
    return null;
  }
  const doc = snap.docs[0];
  const d = doc.data();
  return {
    uid: doc.id,
    displayName: d.displayName || "",
    photoURL: d.photoURL || null,
  };
});
```

- [ ] **Step 3: Create `functions/.gitignore`**

```
node_modules/
```

- [ ] **Step 4: Add functions to `firebase.json`**

Replace `firebase.json` with:

```json
{
  "firestore": {
    "rules": "firestore.rules",
    "indexes": "firestore.indexes.json"
  },
  "storage": {
    "rules": "storage.rules"
  },
  "functions": {
    "source": "functions"
  }
}
```

- [ ] **Step 5: Syntax-check the function**

Run: `node --check functions/index.js && echo "syntax-ok"`
Expected: `syntax-ok`. (Do NOT run `npm install` or `firebase deploy` — deploy is human-gated and requires the Blaze plan. The controller runs the deploy separately.)

- [ ] **Step 6: Commit**

```bash
git add functions/package.json functions/index.js functions/.gitignore firebase.json
git commit -m "feat: lookupUserByEmail callable Cloud Function (deploy pending)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 5: `SocialViewModel`

**Files:**
- Create: `MyStuff/ViewModels/SocialViewModel.swift`

**Interfaces:**
- Consumes: `SocialService`/`FirebaseSocialService` (Tasks 2–3), models (Task 1), `HapticManager`.
- Produces: `@MainActor @Observable final class SocialViewModel` with observable `friends`, `incomingRequests`, `outgoingRequests`, `isLoading`, `errorMessage`; computed `incomingPendingCount`; methods `load()`, `addFriend(email:) -> Bool`, `respond(to:accept:)`, `removeFriend(_:)`.

- [ ] **Step 1: Create `SocialViewModel.swift`**

```swift
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
            try? await service.addFriend(friend)
            if !friends.contains(where: { $0.uid == friend.uid }) {
                friends.append(friend)
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
            try await service.respondToRequest(request, accept: accept)
            incomingRequests.removeAll { $0.id == request.id }
            if accept {
                let friend = Friend(uid: request.fromUid, email: request.fromEmail, displayName: request.fromName, photoURL: request.fromPhotoURL)
                try await service.addFriend(friend)
                if !friends.contains(where: { $0.uid == friend.uid }) {
                    friends.append(friend)
                }
                HapticManager.success()
            } else {
                HapticManager.impact()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeFriend(_ friend: Friend) async {
        do {
            try await service.removeFriend(uid: friend.uid)
            friends.removeAll { $0.uid == friend.uid }
            HapticManager.impact()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `xcodebuild -project MyStuff.xcodeproj -scheme MyStuff -destination 'generic/platform=iOS Simulator' -configuration Debug build 2>&1 | tail -20`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add MyStuff/ViewModels/SocialViewModel.swift
git commit -m "feat: SocialViewModel — friends/requests state + flows

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 6: `FriendsView` + add-friend sheet

**Files:**
- Create: `MyStuff/Views/FriendsView.swift`

**Interfaces:**
- Consumes: `SocialViewModel` (Task 5), models, `HapticManager`.
- Produces: `struct FriendsView: View` (init `FriendsView(social: SocialViewModel)`) and a private `AddFriendSheet`. FriendsView is designed to be pushed inside an existing `NavigationStack` (it sets a `.navigationTitle`, not its own stack).

- [ ] **Step 1: Create `FriendsView.swift`**

```swift
import SwiftUI

struct FriendsView: View {
    @Bindable var social: SocialViewModel
    @State private var showAdd = false

    var body: some View {
        List {
            if !social.incomingRequests.isEmpty {
                Section("Requests") {
                    ForEach(social.incomingRequests) { request in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(request.fromName).font(.subheadline)
                                Text(request.fromEmail).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                Task { await social.respond(to: request, accept: true) }
                            } label: {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            }
                            .buttonStyle(.plain)
                            Button {
                                Task { await social.respond(to: request, accept: false) }
                            } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            if !social.outgoingRequests.isEmpty {
                Section("Pending") {
                    ForEach(social.outgoingRequests) { request in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(request.toName).font(.subheadline)
                            Text("Waiting for response").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Friends") {
                if social.friends.isEmpty {
                    Text("No friends yet")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                } else {
                    ForEach(social.friends) { friend in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(friend.displayName).font(.subheadline)
                            Text(friend.email).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { indexSet in
                        let toRemove = indexSet.map { social.friends[$0] }
                        Task { for friend in toRemove { await social.removeFriend(friend) } }
                    }
                }
            }
        }
        .navigationTitle("Friends")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showAdd = true } label: {
                    Image(systemName: "person.badge.plus")
                }
            }
        }
        .sheet(isPresented: $showAdd) {
            AddFriendSheet(social: social)
                .presentationDetents([.height(220)])
        }
        .task { await social.load() }
    }
}

private struct AddFriendSheet: View {
    @Bindable var social: SocialViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var sending = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("friend@email.com", text: $email)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                }
                if let error = social.errorMessage {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
            .navigationTitle("Add Friend")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") {
                        sending = true
                        Task {
                            let ok = await social.addFriend(email: email)
                            sending = false
                            if ok { dismiss() }
                        }
                    }
                    .disabled(email.isEmpty || sending)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        FriendsView(social: SocialViewModel())
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `xcodebuild -project MyStuff.xcodeproj -scheme MyStuff -destination 'generic/platform=iOS Simulator' -configuration Debug build 2>&1 | tail -20`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add MyStuff/Views/FriendsView.swift
git commit -m "feat: FriendsView — requests, friends list, add-by-email sheet

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 7: Wire `SocialViewModel` into ContentView + account-button badge

**Files:**
- Modify: `MyStuff/Views/ContentView.swift`
- Modify: `MyStuff/Views/HomeView.swift`

**Interfaces:**
- Consumes: `SocialViewModel` (Task 5), `FriendsView` (Task 6).
- Produces: `ContentView` owns a `SocialViewModel`, loads it, shows a Friends row (with badge) in `ProfileSheet`, and passes `pendingRequestCount` to `HomeView`. `HomeView` gains a `pendingRequestCount: Int = 0` parameter and overlays a badge on the account button.

- [ ] **Step 1: Add `SocialViewModel` state + load in `ContentView`**

In `MyStuff/Views/ContentView.swift`, add a state property after `@State private var viewModel = StuffViewModel()`:

```swift
    @State private var viewModel = StuffViewModel()
    @State private var social = SocialViewModel()
```

Load it alongside the data load. Change the `.task`:

```swift
        .task {
            await viewModel.loadData()
        }
        .task {
            await social.load()
        }
```

- [ ] **Step 2: Pass the pending count into `HomeView`**

In `ContentView`, update the Home tab to pass the badge count:

```swift
            Tab("Home", systemImage: "house.fill", value: 0) {
                HomeView(viewModel: viewModel, onProfileTap: { showingProfile = true }, pendingRequestCount: social.incomingPendingCount)
            }
```

- [ ] **Step 3: Pass `social` into `ProfileSheet` and widen its detents**

In `ContentView`, update the profile sheet presentation:

```swift
        .sheet(isPresented: $showingProfile) {
            ProfileSheet(authService: authService, social: social)
                .presentationDetents([.medium, .large])
        }
```

- [ ] **Step 4: Add a Friends row (with badge) to `ProfileSheet`**

In `ContentView.swift`, update `ProfileSheet` to accept `social` and show a Friends navigation row. Change the struct's stored properties:

```swift
struct ProfileSheet: View {
    @Bindable var authService: AuthService
    @Bindable var social: SocialViewModel
    @Environment(\.dismiss) private var dismiss
```

Insert a new `Section` with the Friends link between the profile-info `Section` and the Sign Out `Section` (i.e. after the closing brace of the first `Section { … }` and before `Section { Button(role: .destructive) … }`):

```swift
                Section {
                    NavigationLink {
                        FriendsView(social: social)
                    } label: {
                        HStack {
                            Label("Friends", systemImage: "person.2.fill")
                            Spacer()
                            if social.incomingPendingCount > 0 {
                                Text("\(social.incomingPendingCount)")
                                    .font(.caption2).bold()
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(Color.red, in: Capsule())
                            }
                        }
                    }
                }
```

Update the `#Preview` at the bottom of the file if it constructs `ProfileSheet` directly (it constructs `ContentView`, so no change needed).

- [ ] **Step 5: Add the `pendingRequestCount` param + badge overlay to `HomeView`**

In `MyStuff/Views/HomeView.swift`, add the parameter after `onProfileTap`:

```swift
    @Bindable var viewModel: StuffViewModel
    var onProfileTap: (() -> Void)? = nil
    var pendingRequestCount: Int = 0
```

Update the account-button toolbar item to overlay a badge:

```swift
                if let onProfileTap {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(action: onProfileTap) {
                            Image(systemName: "person.circle.fill")
                                .font(.title3)
                                .symbolRenderingMode(.hierarchical)
                                .overlay(alignment: .topTrailing) {
                                    if pendingRequestCount > 0 {
                                        Circle()
                                            .fill(Color.red)
                                            .frame(width: 10, height: 10)
                                            .offset(x: 3, y: -2)
                                    }
                                }
                        }
                    }
                }
```

- [ ] **Step 6: Build to verify**

Run: `xcodebuild -project MyStuff.xcodeproj -scheme MyStuff -destination 'generic/platform=iOS Simulator' -configuration Debug build 2>&1 | tail -20`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add MyStuff/Views/ContentView.swift MyStuff/Views/HomeView.swift
git commit -m "feat: wire SocialViewModel into account area + pending-request badge

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage (P1 slice of the design spec):**
- `UserProfile` written on sign-in → Task 1 (model) + Task 5 `upsertOwnProfile` (called in `load()`, which runs on app open while signed in). ✅
- `SocialService` + `MockSocialService` → Task 2; `FirebaseSocialService` → Task 3. ✅
- `lookupUserByEmail` callable Cloud Function (first Functions deploy, private profiles) → Task 4 (files) + human-gated deploy. ✅
- `SocialViewModel` (keeps StuffViewModel focused) → Task 5. ✅
- Account-sheet Friends UI: add by email, incoming/outgoing requests, accept/deny → Task 6 + Task 7 Step 4. ✅
- Incoming-request badge on account button → Task 7 Steps 2 & 5 (HomeView badge) + Step 4 (Friends row badge). ✅
- Friendship both-sides (accepter writes on accept; requester reconciles on load) → Task 5 `respond` + `reconcileAcceptedOutgoing`. ✅
- Rules already deployed in P0 (friendRequests, users profile, friends subcollection) → no rules work in P1 (constraint). ✅

Deferred correctly (out of P1 scope): sharing mechanics, move/share dialog, collectionGroup read switch, symmetric unfriend + auto-unshare (P1 `removeFriend` deletes only own side — P2 completes it), push (P3).

**Placeholder scan:** No TBD/TODO; every code step shows complete code. ✅

**Type consistency:** `SocialService` method names/signatures identical across protocol (Task 2), Mock (Task 2), Firebase (Task 3), and VM call sites (Task 5). `FriendRequestStatus` raw values used in `respondToRequest` update match the enum. `SocialViewModel(social:)` init used consistently in FriendsView (Task 6) and ContentView (Task 7). `incomingPendingCount` used in Task 7 Steps 2 & 4. `pendingRequestCount` param name consistent between HomeView (Task 7 Step 5) and its ContentView call site (Task 7 Step 2). ✅

## Known follow-ups (carry to P2/P3)
- Guard `StuffViewModel` sharing-migration on `!currentUid.isEmpty` (P0 minor); the same `currentUserId == ""` footgun exists in `FirebaseSocialService` — every social call is gated behind a signed-in `.task`, so it's latent, but P2 should centralize the signed-in guard.
- `removeFriend` only deletes the caller's side. P2's unfriend must also strip the pair from all shared `memberIds` and ideally remove the reciprocal friend doc (needs a Cloud Function or accepting a one-sided dangle until the other opens the app).
- Declined requests linger in `friendRequests` (filtered out of the UI). A cleanup pass (or TTL) can be added later; harmless for now.
- Lookup requires the target to have opened the app at least once since P1 ships (so their profile doc exists). Pre-existing users who never re-open won't be findable until they do.
