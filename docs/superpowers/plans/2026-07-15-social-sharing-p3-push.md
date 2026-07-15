# Social Sharing — P3 Push Notifications Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver push notifications for three events — friend request received, friend request accepted, and an item/location shared with you — via FCM, with tap-to-open deep-linking.

**Architecture:** Firestore-triggered Cloud Functions (v1, in the existing `functions/` project) send FCM messages through a shared sender that reads the recipient's registered tokens and prunes dead ones. The app registers for remote notifications via an `AppDelegate` adaptor (it's pure SwiftUI today), stores its FCM token at `users/{uid}/fcmTokens/{token}`, shows foreground banners, and routes taps into the existing deep-link resolution.

**Tech Stack:** Swift 6 / SwiftUI, FirebaseMessaging (iOS), Node Firebase Functions (v1 Firestore triggers) + firebase-admin messaging.

## Prerequisites (MANUAL — must be done before the Swift tasks)

- **APNs Authentication Key** uploaded to Firebase → Project Settings → Cloud Messaging. **(Already done.)**
- **Add the `FirebaseMessaging` product to the `MyStuff` target in Xcode** (the firebase-ios-sdk package is already resolved; only Firestore + Auth are currently linked). Xcode → project → MyStuff target → General → "Frameworks, Libraries, and Embedded Content" (or the package product list) → add `FirebaseMessaging`. **Tasks 3–4 will not compile until this is done.** Tasks 1–2 (Cloud Functions) have no such dependency and can run first.

## Global Constraints

- iOS 26.0, Swift 6.0. `@Observable` / `@Bindable`. Haptics via `HapticManager`.
- **No test target exists.** Verification = compile via `xcodebuild` (Swift) / `node --check` (Functions) + deferred on-device gates. Swift build (repo root, look for `** BUILD SUCCEEDED **`):
  ```
  xcodebuild -project MyStuff.xcodeproj -scheme MyStuff -destination 'generic/platform=iOS Simulator' -configuration Debug build
  ```
- Firebase prod project `mystuff-b072d`, Functions region us-central1. The `functions/` project uses `firebase-functions/v1` + firebase-admin v13 (`admin.messaging()`, `admin.firestore()` namespaced APIs).
- New Swift files go under `MyStuff/` (synchronized folder groups auto-include them).
- Notifications are user-visible alerts (no silent/background push → no extra background-mode entitlement). `aps-environment: development` is already in `MyStuff.entitlements`.
- **Cloud Function deploys are controller/human-gated** (the controller runs `firebase deploy`); implementers only write + `node --check`.
- FCM data-payload values are always strings.

---

### Task 1: fcmTokens rule + FCM sender helper + friend-request push triggers

**Files:**
- Modify: `firestore.rules`
- Modify: `functions/index.js`

**Interfaces:**
- Produces: `users/{uid}/fcmTokens/{tokenId}` owner-only rule; a `sendPushToUser(uid, notification, data)` helper in the Functions codebase; `onFriendRequestCreated` and `onFriendRequestUpdated` triggers.

- [ ] **Step 1: Add the `fcmTokens` rule**

In `firestore.rules`, inside the `match /users/{uid} { … }` block (after the existing `match /friends/{friendUid} { … }` block), add:

```
      match /fcmTokens/{tokenId} {
        allow read, write: if signedIn() && request.auth.uid == uid;
      }
```

- [ ] **Step 2: Add the sender helper + friend-request triggers to `functions/index.js`**

Append to `functions/index.js` (after the existing `lookupUserByEmail` export):

```javascript
/**
 * Send a push to every registered token of `uid`. Prunes tokens FCM reports dead.
 */
async function sendPushToUser(uid, notification, data) {
  const col = admin.firestore().collection("users").doc(uid).collection("fcmTokens");
  const snap = await col.get();
  const tokens = snap.docs.map((d) => d.id);
  if (tokens.length === 0) return;

  const resp = await admin.messaging().sendEachForMulticast({
    tokens,
    notification,
    data: data || {},
    apns: {payload: {aps: {sound: "default"}}},
  });

  const dead = [];
  resp.responses.forEach((r, i) => {
    if (!r.success) {
      const code = r.error && r.error.code;
      if (code === "messaging/registration-token-not-registered" ||
          code === "messaging/invalid-argument") {
        dead.push(tokens[i]);
      }
    }
  });
  await Promise.all(dead.map((t) => col.doc(t).delete()));
}

/** New friend request → notify the recipient. */
exports.onFriendRequestCreated = functions.firestore
    .document("friendRequests/{requestId}")
    .onCreate(async (snap) => {
      const req = snap.data();
      if (req.status !== "pending") return;
      await sendPushToUser(
          req.toUid,
          {title: "New friend request", body: `${req.fromName || "Someone"} wants to connect`},
          {type: "friendRequest"},
      );
    });

/** Friend request accepted → notify the original sender. */
exports.onFriendRequestUpdated = functions.firestore
    .document("friendRequests/{requestId}")
    .onUpdate(async (change) => {
      const before = change.before.data();
      const after = change.after.data();
      if (before.status !== "accepted" && after.status === "accepted") {
        await sendPushToUser(
            after.fromUid,
            {title: "Friend request accepted", body: `${after.toName || "Your friend"} accepted your request`},
            {type: "friendAccepted"},
        );
      }
    });
```

- [ ] **Step 3: Syntax-check**

Run: `node --check functions/index.js && python3 -m json.tool functions/../firestore.rules >/dev/null 2>&1; echo "js-ok"`
Expected: `js-ok` (the rules file isn't JSON; the `node --check` is the real gate here). Also eyeball that `firestore.rules` still starts with `rules_version = '2';` and the `fcmTokens` block is nested inside `match /users/{uid}`.

- [ ] **Step 4: Commit**

```bash
git add firestore.rules functions/index.js
git commit -m "feat: FCM sender helper + friend-request push triggers + fcmTokens rule

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

> Deploy (controller): `firebase deploy --only firestore:rules,functions --project mystuff-b072d`.

---

### Task 2: Share push triggers (item/location memberIds diff)

**Files:**
- Modify: `functions/index.js`

**Interfaces:**
- Consumes: `sendPushToUser` (Task 1).
- Produces: `onItemUpdated`, `onLocationUpdated` triggers that push to newly-added members; a `displayNameFor(uid)` helper.

- [ ] **Step 1: Add the share triggers to `functions/index.js`**

Append to `functions/index.js`:

```javascript
/** Owner's display name for share notifications. */
async function displayNameFor(uid) {
  const doc = await admin.firestore().collection("users").doc(uid).get();
  return (doc.exists && doc.data().displayName) || "Someone";
}

/** uids added to memberIds by this update, excluding the owner. */
function newlyAddedMembers(before, after, ownerId) {
  const beforeM = (before && before.memberIds) || [];
  const afterM = (after && after.memberIds) || [];
  return afterM.filter((u) => !beforeM.includes(u) && u !== ownerId);
}

/** Item shared with new members → notify each. */
exports.onItemUpdated = functions.firestore
    .document("users/{ownerId}/items/{itemId}")
    .onUpdate(async (change, context) => {
      const added = newlyAddedMembers(change.before.data(), change.after.data(), context.params.ownerId);
      if (added.length === 0) return;
      const name = await displayNameFor(context.params.ownerId);
      const itemName = change.after.data().name || "an item";
      await Promise.all(added.map((uid) => sendPushToUser(
          uid,
          {title: "Item shared with you", body: `${name} shared "${itemName}"`},
          {type: "itemShared", itemId: context.params.itemId},
      )));
    });

/** Location shared with new members → notify each. */
exports.onLocationUpdated = functions.firestore
    .document("users/{ownerId}/locations/{locationId}")
    .onUpdate(async (change, context) => {
      const added = newlyAddedMembers(change.before.data(), change.after.data(), context.params.ownerId);
      if (added.length === 0) return;
      const name = await displayNameFor(context.params.ownerId);
      const locName = change.after.data().name || "a location";
      await Promise.all(added.map((uid) => sendPushToUser(
          uid,
          {title: "Location shared with you", body: `${name} shared "${locName}"`},
          {type: "locationShared", locationId: context.params.locationId},
      )));
    });
```

- [ ] **Step 2: Syntax-check**

Run: `node --check functions/index.js && echo "js-ok"`
Expected: `js-ok`.

- [ ] **Step 3: Commit**

```bash
git add functions/index.js
git commit -m "feat: push triggers for items/locations shared with new members

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

> Deploy (controller): `firebase deploy --only functions --project mystuff-b072d`.

---

### Task 3: App push infrastructure — AppDelegate, permission, token storage, foreground banners

**Files:**
- Create: `MyStuff/Services/PushNotificationManager.swift`
- Create: `MyStuff/AppDelegate.swift`
- Modify: `MyStuff/MyStuffApp.swift`
- Modify: `MyStuff/Views/ContentView.swift`

**Prerequisite:** `FirebaseMessaging` added to the target (see Prerequisites) — required for this to compile.

**Interfaces:**
- Produces:
  - `PushNotificationManager` — `@MainActor @Observable` singleton (`shared`): `requestAuthorization()`, `saveTokenIfPossible()`, `handleTap(userInfo:)`, and observable nav intents `pendingItemId: String?`, `pendingLocationId: String?`, `openFriends: Bool`, plus `currentFCMToken: String?`.
  - `AppDelegate` conforming to `UIApplicationDelegate`, `MessagingDelegate`, `UNUserNotificationCenterDelegate`.

- [ ] **Step 1: Create `PushNotificationManager.swift`**

```swift
import Foundation
import FirebaseAuth
import FirebaseFirestore
import UserNotifications
import UIKit

/// Owns notification permission, FCM-token persistence, and tap→navigation intents.
@MainActor
@Observable
final class PushNotificationManager {
    static let shared = PushNotificationManager()
    private init() {}

    var currentFCMToken: String?

    // Nav intents consumed by ContentView after a notification tap.
    var pendingItemId: String?
    var pendingLocationId: String?
    var openFriends: Bool = false

    /// Ask for alert permission and register with APNs. Safe to call repeatedly.
    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            Task { @MainActor in UIApplication.shared.registerForRemoteNotifications() }
        }
    }

    /// Persist the current FCM token under the signed-in user (token = doc id, dedup-free).
    func saveTokenIfPossible() {
        guard let uid = Auth.auth().currentUser?.uid, let token = currentFCMToken else { return }
        Firestore.firestore()
            .collection("users").document(uid)
            .collection("fcmTokens").document(token)
            .setData(["token": token, "platform": "ios", "updatedAt": FieldValue.serverTimestamp()], merge: true)
    }

    /// Parse a notification payload into a nav intent.
    func handleTap(userInfo: [AnyHashable: Any]) {
        switch userInfo["type"] as? String {
        case "itemShared":
            if let id = userInfo["itemId"] as? String { pendingItemId = id }
        case "locationShared":
            if let id = userInfo["locationId"] as? String { pendingLocationId = id }
        case "friendRequest", "friendAccepted":
            openFriends = true
        default:
            break
        }
    }
}
```

- [ ] **Step 2: Create `AppDelegate.swift`**

```swift
import UIKit
import FirebaseCore
import FirebaseMessaging
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, MessagingDelegate, UNUserNotificationCenterDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        Messaging.messaging().delegate = self
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    // APNs token → FCM.
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }

    // FCM registration token (may fire before sign-in).
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        Task { @MainActor in
            PushNotificationManager.shared.currentFCMToken = fcmToken
            PushNotificationManager.shared.saveTokenIfPossible()
        }
    }

    // Show banners while the app is foregrounded.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }

    // Tap → stash a nav intent for ContentView.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        let userInfo = response.notification.request.content.userInfo
        await MainActor.run { PushNotificationManager.shared.handleTap(userInfo: userInfo) }
    }
}
```

- [ ] **Step 3: Wire the adaptor in `MyStuffApp.swift`**

In `MyStuff/MyStuffApp.swift`, add the adaptor property to `MyStuffApp` (after `@State private var authService: AuthService`):

```swift
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
```

(Leave `FirebaseApp.configure()` in `init()` — it runs before `AppDelegate.application(_:didFinishLaunching:)`, so Messaging is configured by the time the delegate sets itself up.)

- [ ] **Step 4: Request permission + save token on launch in `ContentView`**

In `MyStuff/Views/ContentView.swift`, add a `.task` on the `TabView` (alongside the existing `.task`s):

```swift
        .task {
            PushNotificationManager.shared.requestAuthorization()
            PushNotificationManager.shared.saveTokenIfPossible()
        }
```

- [ ] **Step 5: Build to verify** (requires FirebaseMessaging linked)

Run: `xcodebuild -project MyStuff.xcodeproj -scheme MyStuff -destination 'generic/platform=iOS Simulator' -configuration Debug build 2>&1 | tail -20`
Expected: `** BUILD SUCCEEDED **`. If it fails with "No such module 'FirebaseMessaging'", the Prerequisite (add the product in Xcode) hasn't been done — STOP and report; do not attempt to edit the project file.

- [ ] **Step 6: Commit**

```bash
git add MyStuff/Services/PushNotificationManager.swift MyStuff/AppDelegate.swift MyStuff/MyStuffApp.swift MyStuff/Views/ContentView.swift
git commit -m "feat: FCM registration, permission prompt, token storage, foreground banners

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: Notification tap → deep-link routing in ContentView

**Files:**
- Modify: `MyStuff/Views/ContentView.swift`

**Interfaces:**
- Consumes: `PushNotificationManager.shared` nav intents (Task 3), ContentView's existing `pendingNFCItemId`/`pendingLocationId`/`resolvePendingDeepLink()`/`showingProfile`.

- [ ] **Step 1: Bridge push nav intents into ContentView's existing deep-link resolution**

In `MyStuff/Views/ContentView.swift`, add a reference to the push manager near the other state:

```swift
    private let push = PushNotificationManager.shared
```

Add `.onChange` handlers (alongside the existing `.onChange(of: viewModel.items)` etc.) that translate push intents into the existing pending-deep-link state and clear the intent:

```swift
        .onChange(of: push.pendingItemId) {
            if let id = push.pendingItemId {
                pendingNFCItemId = id
                push.pendingItemId = nil
            }
        }
        .onChange(of: push.pendingLocationId) {
            if let id = push.pendingLocationId {
                pendingLocationId = id
                push.pendingLocationId = nil
            }
        }
        .onChange(of: push.openFriends) {
            if push.openFriends {
                selectedTab = 0
                showingProfile = true
                push.openFriends = false
            }
        }
```

> These reuse `resolvePendingDeepLink()` (already wired to `onChange(of: pendingNFCItemId)` / `pendingLocationId`), which opens the item's `NFCUpdateSheet` / the location's `LocationDetailView` sheet once the entity is loaded. Friend pushes open the account sheet (which has the Friends row + badge).

- [ ] **Step 2: Build to verify**

Run: `xcodebuild -project MyStuff.xcodeproj -scheme MyStuff -destination 'generic/platform=iOS Simulator' -configuration Debug build 2>&1 | tail -20`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add MyStuff/Views/ContentView.swift
git commit -m "feat: route notification taps to item/location/friends

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage (P3 slice):**
- FCM token registration → Task 3 (AppDelegate + PushNotificationManager + ContentView task). ✅
- Push on friend request received + accepted → Task 1. ✅
- Push on item/location shared → Task 2. ✅
- Sender Cloud Function(s) + token pruning → Task 1 (`sendPushToUser`). ✅
- APNs setup → prerequisite (done). FirebaseMessaging link → prerequisite (manual, Xcode). ✅
- Tap → deep-link → Task 4 (reuses existing resolution). ✅
- Permission on first launch after sign-in → Task 3 Step 4. ✅

**Placeholder scan:** No TBD/TODO; every code step shows complete code. ✅

**Type consistency:** `sendPushToUser(uid, notification, data)` defined in Task 1, called in Task 2; data-payload keys (`type`, `itemId`, `locationId`) written by Functions (Tasks 1–2) match those read in `handleTap` (Task 3) and routed in Task 4; `PushNotificationManager.shared` intents (`pendingItemId`/`pendingLocationId`/`openFriends`) consistent between Task 3 and Task 4. ✅

## Known follow-ups (later)
- `onItemUpdated`/`onLocationUpdated` fire on every doc update; they early-return unless memberIds gained a member, but a very hot item still invokes the function — fine at this scale.
- No de-dup if the same share is toggled off/on rapidly (each add pushes). Acceptable.
- Token cleanup on explicit sign-out isn't implemented (dead tokens are pruned lazily on send failure).
- Direct create-with-members (not via `shareItem`'s update) wouldn't push — current UI always shares via update, so covered; add an `onCreate` trigger if that changes.
- No per-user notification preferences / mute (out of scope).
