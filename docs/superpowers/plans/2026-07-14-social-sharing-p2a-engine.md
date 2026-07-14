# Social Sharing — P2a Sharing Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make shared items/locations actually load and mutate — switch reads to a `collectionGroup(memberIds arrayContains me)` query, add the ViewModel share/unshare/make-private/add-members operations, and wire unfriend to auto-unshare everything between the two users. No sharing UI yet (that's P2b), so there is no new visible entry point — but shared data (if any exists) now appears.

**Architecture:** Approach A. `FirebaseDataService` stops reading a single owner's subcollection and instead runs `db.collectionGroup("items").whereField("memberIds", arrayContains: uid)` (same for locations), returning own + shared in one query (indexes deployed in P0). Writes already route to `users/{ownerId}/…` (P0). Sharing = mutating `memberIds`; visibility follows automatically. Unfriend strips the pair from every shared `memberIds` in the loaded set (both directions, since a member may update per the P0 rules).

**Tech Stack:** Swift 6 / SwiftUI, Firebase Firestore.

## Global Constraints

- iOS 26.0, Swift 6.0. `@Observable` / `@Bindable`. Haptics via `HapticManager`.
- Firestore uses Codable (`data(as:)` / `setData(from:)`).
- **No test target exists.** Verification = compile via `xcodebuild` + deferred manual gates. Build command (run from repo root, ~30–90s, look for `** BUILD SUCCEEDED **`):
  ```
  xcodebuild -project MyStuff.xcodeproj -scheme MyStuff -destination 'generic/platform=iOS Simulator' -configuration Debug build
  ```
- Composite collectionGroup indexes (`memberIds arrayContains` + `createdAt desc`) for `items` and `locations` were deployed in P0. Do NOT change rules or indexes in P2a.
- `Item.members` / `Location.members` (from P0) = `memberIds ?? [ownerId]` non-optional accessor. `ownerId`/`memberIds` are `Optional`.
- `DataService.currentUserId` (P0) returns the signed-in uid ("" if unauthenticated). `StuffViewModel`'s `service` is a `DataService`.
- **MockDataService is NOT changed** — its `fetchItems`/`fetchLocations` keep returning all in-memory rows (the mock does not simulate multi-user visibility). Only `FirebaseDataService` switches to collectionGroup.
- Sharing only ever adds/removes uids in `memberIds`; the owner (`ownerId`) is always kept as a member.

---

### Task 1: Switch FirebaseDataService reads to collectionGroup

**Files:**
- Modify: `MyStuff/Services/FirebaseDataService.swift`

**Interfaces:**
- Consumes: `memberIds` field + P0 composite indexes.
- Produces: `fetchItems`/`fetchLocations` return own **and** shared entities (every doc where `uid ∈ memberIds`), still ordered by `createdAt desc`. Signatures unchanged.

- [ ] **Step 1: Replace `fetchItems` and `fetchLocations`**

In `MyStuff/Services/FirebaseDataService.swift`, replace the existing `fetchItems(source:)` method with:

```swift
    func fetchItems(source: FetchSource) async throws -> [Item] {
        let snapshot = try await db.collectionGroup("items")
            .whereField("memberIds", arrayContains: uid)
            .order(by: "createdAt", descending: true)
            .getDocuments(source: source.firestoreSource)
        return try snapshot.documents.map { try $0.data(as: Item.self) }
    }
```

And replace the existing `fetchLocations(source:)` method with:

```swift
    func fetchLocations(source: FetchSource) async throws -> [Location] {
        let snapshot = try await db.collectionGroup("locations")
            .whereField("memberIds", arrayContains: uid)
            .order(by: "createdAt", descending: true)
            .getDocuments(source: source.firestoreSource)
        return try snapshot.documents.map { try $0.data(as: Location.self) }
    }
```

> Leave `itemsCollection(owner:)` / `locationsCollection(owner:)` and all write methods unchanged — writes still route to `users/{ownerId}/…`. `categoriesCollection` and the Categories CRUD are unchanged (categories stay per-user).

- [ ] **Step 2: Build to verify**

Run: `xcodebuild -project MyStuff.xcodeproj -scheme MyStuff -destination 'generic/platform=iOS Simulator' -configuration Debug build 2>&1 | tail -20`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add MyStuff/Services/FirebaseDataService.swift
git commit -m "feat: read items/locations via collectionGroup memberIds query

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: Sharing operations on StuffViewModel

**Files:**
- Modify: `MyStuff/ViewModels/StuffViewModel.swift`

**Interfaces:**
- Consumes: `Item.members`/`ownerId`/`memberIds`, `Location.members`/`ownerId`/`memberIds`, `service.currentUserId`, `service.updateItem`/`updateLocation`.
- Produces (all on `StuffViewModel`):
  - `var currentUserId: String`
  - `func sharedMembers(of item: Item) -> [String]` / `func sharedMembers(of location: Location) -> [String]`
  - `func isShared(_ item: Item) -> Bool` / `func isShared(_ location: Location) -> Bool`
  - `func isSharedWithMe(_ item: Item) -> Bool` / `func isSharedWithMe(_ location: Location) -> Bool`
  - `func membersMissing(from location: Location, forItemMembers itemMembers: [String]) -> [String]`
  - `func shareItem(_:withFriend:)`, `func unshareItem(_:fromFriend:)`, `func makeItemPrivate(_:)`
  - `func shareLocation(_:withFriend:)`, `func unshareLocation(_:fromFriend:)`
  - `func addMembers(_:toLocation:)`

- [ ] **Step 1: Add the sharing section to `StuffViewModel`**

In `MyStuff/ViewModels/StuffViewModel.swift`, add this section immediately after the `// MARK: - Location CRUD` block's closing (i.e. after `deleteLocation` and before `// MARK: - Category CRUD`):

```swift
    // MARK: - Sharing

    /// Current signed-in uid, surfaced for views/badges.
    var currentUserId: String { service.currentUserId }

    /// Members an entity is shared with (everyone except its owner).
    func sharedMembers(of item: Item) -> [String] {
        item.members.filter { $0 != (item.ownerId ?? currentUserId) }
    }
    func sharedMembers(of location: Location) -> [String] {
        location.members.filter { $0 != (location.ownerId ?? currentUserId) }
    }

    func isShared(_ item: Item) -> Bool { !sharedMembers(of: item).isEmpty }
    func isShared(_ location: Location) -> Bool { !sharedMembers(of: location).isEmpty }

    /// True if this entity is owned by someone else (i.e. shared *with* me).
    func isSharedWithMe(_ item: Item) -> Bool { (item.ownerId ?? currentUserId) != currentUserId }
    func isSharedWithMe(_ location: Location) -> Bool { (location.ownerId ?? currentUserId) != currentUserId }

    /// Member uids of an item that are NOT members of `location` — i.e. who would lose
    /// visibility of the item's location if the item moved there. Drives the move/share dialog.
    func membersMissing(from location: Location, forItemMembers itemMembers: [String]) -> [String] {
        let locMembers = Set(location.members)
        return itemMembers.filter { !locMembers.contains($0) }
    }

    func shareItem(_ item: Item, withFriend friendUid: String) async {
        guard var updated = items.first(where: { $0.id == item.id }) else { return }
        guard !updated.members.contains(friendUid) else { return }
        updated.memberIds = updated.members + [friendUid]
        await persistItemMembers(updated)
    }

    func unshareItem(_ item: Item, fromFriend friendUid: String) async {
        guard var updated = items.first(where: { $0.id == item.id }) else { return }
        updated.memberIds = updated.members.filter { $0 != friendUid }
        await persistItemMembers(updated)
    }

    /// Reset an item to private: members become exactly `[owner]`.
    func makeItemPrivate(_ item: Item) async {
        guard var updated = items.first(where: { $0.id == item.id }) else { return }
        updated.memberIds = [updated.ownerId ?? currentUserId]
        await persistItemMembers(updated)
    }

    func shareLocation(_ location: Location, withFriend friendUid: String) async {
        guard var updated = locations.first(where: { $0.id == location.id }) else { return }
        guard !updated.members.contains(friendUid) else { return }
        updated.memberIds = updated.members + [friendUid]
        await persistLocationMembers(updated)
    }

    func unshareLocation(_ location: Location, fromFriend friendUid: String) async {
        guard var updated = locations.first(where: { $0.id == location.id }) else { return }
        updated.memberIds = updated.members.filter { $0 != friendUid }
        await persistLocationMembers(updated)
    }

    /// Add member uids to a location (union). Used to resolve a move/share conflict by
    /// sharing the destination location with the item's members.
    func addMembers(_ uids: [String], toLocation location: Location) async {
        guard var updated = locations.first(where: { $0.id == location.id }) else { return }
        var members = updated.members
        for uid in uids where !members.contains(uid) { members.append(uid) }
        updated.memberIds = members
        await persistLocationMembers(updated)
    }

    /// Persist a membership change on an item. If the change removed *me* from the members,
    /// drop it from local state (it will no longer be returned by my collectionGroup query).
    private func persistItemMembers(_ item: Item) async {
        var updated = item
        updated.updatedAt = .now
        do {
            try await service.updateItem(updated)
            if updated.members.contains(currentUserId) {
                if let i = items.firstIndex(where: { $0.id == updated.id }) { items[i] = updated }
            } else {
                items.removeAll { $0.id == updated.id }
            }
            HapticManager.success()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func persistLocationMembers(_ location: Location) async {
        var updated = location
        do {
            try await service.updateLocation(updated)
            if updated.members.contains(currentUserId) {
                if let i = locations.firstIndex(where: { $0.id == updated.id }) { locations[i] = updated }
            } else {
                locations.removeAll { $0.id == updated.id }
            }
            HapticManager.success()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
```

- [ ] **Step 2: Build to verify**

Run: `xcodebuild -project MyStuff.xcodeproj -scheme MyStuff -destination 'generic/platform=iOS Simulator' -configuration Debug build 2>&1 | tail -20`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add MyStuff/ViewModels/StuffViewModel.swift
git commit -m "feat: share/unshare + make-private + add-members ops on StuffViewModel

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: Unfriend auto-unshare + SocialViewModel hook + ContentView wiring

**Files:**
- Modify: `MyStuff/ViewModels/StuffViewModel.swift`
- Modify: `MyStuff/ViewModels/SocialViewModel.swift`
- Modify: `MyStuff/Views/ContentView.swift`

**Interfaces:**
- Consumes: the sharing helpers from Task 2, `SocialViewModel.removeFriend`.
- Produces:
  - `StuffViewModel.unshareEverything(withFriend friendUid: String) async` — strips the pair from every shared item/location in the loaded set (both directions).
  - `SocialViewModel.onUnfriend: ((String) async -> Void)?` closure, invoked inside `removeFriend` before deleting the friend doc.
  - `ContentView` wires `social.onUnfriend = { await viewModel.unshareEverything(withFriend: $0) }`.

- [ ] **Step 1: Add `unshareEverything` to `StuffViewModel`**

In `MyStuff/ViewModels/StuffViewModel.swift`, add at the end of the `// MARK: - Sharing` section (after `persistLocationMembers`):

```swift
    /// On unfriend: remove the pair from every shared entity in the loaded set, in both
    /// directions — strip the friend from things I own, and strip me from things they own
    /// (allowed because a member may update, per security rules).
    func unshareEverything(withFriend friendUid: String) async {
        let me = currentUserId
        for item in items {
            let owner = item.ownerId ?? me
            if owner == me, item.members.contains(friendUid) {
                var u = item; u.memberIds = item.members.filter { $0 != friendUid }
                await persistItemMembers(u)
            } else if owner == friendUid, item.members.contains(me) {
                var u = item; u.memberIds = item.members.filter { $0 != me }
                await persistItemMembers(u)
            }
        }
        for location in locations {
            let owner = location.ownerId ?? me
            if owner == me, location.members.contains(friendUid) {
                var u = location; u.memberIds = location.members.filter { $0 != friendUid }
                await persistLocationMembers(u)
            } else if owner == friendUid, location.members.contains(me) {
                var u = location; u.memberIds = location.members.filter { $0 != me }
                await persistLocationMembers(u)
            }
        }
    }
```

> Note: `persistItemMembers`/`persistLocationMembers` mutate `items`/`locations`. Swift's `for x in items` iterates a copy-on-write snapshot taken at loop entry, so mutating `self.items` inside the body is safe — the loop still visits every element of the original array.

- [ ] **Step 2: Invoke the hook in `SocialViewModel.removeFriend`**

In `MyStuff/ViewModels/SocialViewModel.swift`, add the closure property near the other stored properties (after `private let service: SocialService = FirebaseSocialService()`):

```swift
    /// Set by ContentView: called on unfriend to strip shared memberIds between the two users.
    var onUnfriend: ((String) async -> Void)?
```

Then update `removeFriend(_:)` to call it before deleting the friend doc:

```swift
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
```

- [ ] **Step 3: Wire the hook in `ContentView`**

In `MyStuff/Views/ContentView.swift`, in the existing `.task { await social.load() }`, set the hook before loading. Replace that task with:

```swift
        .task {
            social.onUnfriend = { friendUid in
                await viewModel.unshareEverything(withFriend: friendUid)
            }
            await social.load()
        }
```

- [ ] **Step 4: Build to verify**

Run: `xcodebuild -project MyStuff.xcodeproj -scheme MyStuff -destination 'generic/platform=iOS Simulator' -configuration Debug build 2>&1 | tail -20`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Behavioral gate (controller/user, deferred)**

Not runnable by an implementer (needs two accounts + live data): after P2b ships the sharing UI, verify that removing a friend strips shared items/locations from both users' views. Note this as deferred in the report.

- [ ] **Step 6: Commit**

```bash
git add MyStuff/ViewModels/StuffViewModel.swift MyStuff/ViewModels/SocialViewModel.swift MyStuff/Views/ContentView.swift
git commit -m "feat: unfriend auto-unshares all shared items/locations between the pair

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: Self-healing own-doc backfill before the collectionGroup read

**Files:**
- Modify: `MyStuff/Services/DataService.swift`
- Modify: `MyStuff/Services/FirebaseDataService.swift`
- Modify: `MyStuff/Services/MockDataService.swift`
- Modify: `MyStuff/ViewModels/StuffViewModel.swift`

**Why:** The Task-1 collectionGroup query `whereField("memberIds", arrayContains: uid)` only returns docs that actually have a `memberIds` array stored in Firestore. The P0 backfill populated that field via the *old* per-user read — but if a device runs a build with the Task-1 read switch before that backfill ever ran (P0/P1 behavioral gates were deferred), its own un-migrated docs are invisible to the query and can never be seen to migrate them (chicken-and-egg). This task makes the app self-heal: a one-time per-owner read of the user's own subcollection stamps `ownerId`/`memberIds` before the collectionGroup fetch, independent of prior build history. Runs once per uid (guarded by a `UserDefaults` flag).

**Interfaces:**
- Produces:
  - `DataService.fetchOwnItems() async throws -> [Item]` and `fetchOwnLocations() async throws -> [Location]` — read the current user's own subcollection directly (the pre-P2a path).
  - `StuffViewModel.backfillOwnSharingFieldsIfNeeded(currentUid:)` — one-time own-doc backfill, called in `loadData` before the collectionGroup server fetch.

- [ ] **Step 1: Add the two methods to the `DataService` protocol**

In `MyStuff/Services/DataService.swift`, add to the `protocol DataService` body, right after the `currentUserId` requirement (before `// MARK: - Items`):

```swift
    /// Read the current user's OWN items subcollection directly (pre-sharing path).
    /// Used once to backfill `memberIds`/`ownerId` before the collectionGroup read.
    func fetchOwnItems() async throws -> [Item]
    /// Read the current user's OWN locations subcollection directly.
    func fetchOwnLocations() async throws -> [Location]
```

- [ ] **Step 2: Implement them in `FirebaseDataService`**

In `MyStuff/Services/FirebaseDataService.swift`, add after `fetchItems`/`fetchLocations` (the collectionGroup versions):

```swift
    func fetchOwnItems() async throws -> [Item] {
        let snapshot = try await itemsCollection(owner: uid)
            .order(by: "createdAt", descending: true)
            .getDocuments(source: .server)
        return try snapshot.documents.map { try $0.data(as: Item.self) }
    }

    func fetchOwnLocations() async throws -> [Location] {
        let snapshot = try await locationsCollection(owner: uid)
            .order(by: "createdAt", descending: true)
            .getDocuments(source: .server)
        return try snapshot.documents.map { try $0.data(as: Location.self) }
    }
```

- [ ] **Step 3: Implement them in `MockDataService`**

In `MyStuff/Services/MockDataService.swift`, add (near the other fetch methods):

```swift
    func fetchOwnItems() async throws -> [Item] { items }
    func fetchOwnLocations() async throws -> [Location] { locations }
```

- [ ] **Step 4: Add the backfill method to `StuffViewModel` and call it in `loadData`**

In `MyStuff/ViewModels/StuffViewModel.swift`, add this method just after `persistSharingMigrationsIfNeeded(rawItems:rawLocations:currentUid:)`:

```swift
    /// One-time-per-user backfill of `ownerId`/`memberIds` on the user's OWN docs, read via
    /// the pre-sharing per-owner path. Guarantees own docs carry `memberIds` so the
    /// collectionGroup `arrayContains` read returns them. Guarded by a UserDefaults flag.
    private func backfillOwnSharingFieldsIfNeeded(currentUid: String) async {
        guard !currentUid.isEmpty else { return }
        let key = "sharingBackfillDone_\(currentUid)"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        do {
            let ownItems = try await service.fetchOwnItems()
            for raw in ownItems {
                let migrated = Self.migratedSharingFields(raw, currentUid: currentUid)
                if raw.ownerId != migrated.ownerId || raw.memberIds != migrated.memberIds {
                    try? await service.updateItem(migrated)
                }
            }
            let ownLocations = try await service.fetchOwnLocations()
            for raw in ownLocations {
                let migrated = Self.migratedSharingFields(raw, currentUid: currentUid)
                if raw.ownerId != migrated.ownerId || raw.memberIds != migrated.memberIds {
                    try? await service.updateLocation(migrated)
                }
            }
            UserDefaults.standard.set(true, forKey: key)
        } catch {
            // Leave the flag unset so we retry on the next launch.
        }
    }
```

Then call it in `loadData()` in the Stage-2 `do` block, immediately after `let currentUid = service.currentUserId` and **before** the `async let serverItems = …` collectionGroup fetch. The start of the `do` block becomes:

```swift
        do {
            let currentUid = service.currentUserId
            await backfillOwnSharingFieldsIfNeeded(currentUid: currentUid)
            async let serverItems = service.fetchItems(source: .server)
```

> `migratedSharingFields` and `persistSharingMigrationsIfNeeded` already exist from P0; this reuses `migratedSharingFields`. The P0 `persistSharingMigrationsIfNeeded` (which runs on the collectionGroup result) stays — it's now redundant for own docs but harmless (its diff-guard suppresses no-op writes).

- [ ] **Step 5: Build to verify**

Run: `xcodebuild -project MyStuff.xcodeproj -scheme MyStuff -destination 'generic/platform=iOS Simulator' -configuration Debug build 2>&1 | tail -20`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add MyStuff/Services/DataService.swift MyStuff/Services/FirebaseDataService.swift MyStuff/Services/MockDataService.swift MyStuff/ViewModels/StuffViewModel.swift
git commit -m "fix: self-heal own-doc memberIds backfill before collectionGroup read

Closes the chicken-and-egg where a device running the collectionGroup read
switch before the P0 backfill ran would never see its own un-migrated docs.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage (P2a slice):**
- collectionGroup merged read (own + shared in one query) → Task 1. ✅
- Share/unshare item & location; create-shared handled via existing add + share; make-private + add-members for the move/share dialog resolution → Task 2. ✅
- Unfriend auto-unshare (both directions) → Task 3. ✅
- Privacy rule (per-entity visibility) → inherent in the collectionGroup query (Task 1) + the fact that sharing only touches the entity's own `memberIds`. ✅

Deferred to P2b (UI): friend-picker, Share actions in ItemDetailSheet/LocationDetailView, "Share with" in ItemFormSheet, shared badges + owner labels, orphan sub-location display, and the actual move/share **dialog** (Task 2 provides `membersMissing` + `makeItemPrivate` + `addMembers` for P2b to wire). Storage rules unchanged — shared photos load via the tokenized `remotePhotoURL` already stored on items.

**Placeholder scan:** No TBD/TODO; every code step shows complete code. ✅

**Type consistency:** `memberIds` set as `[String]?`; `.members` accessor used for reads; `currentUserId: String` consistent with P0 `DataService.currentUserId`; `persistItemMembers`/`persistLocationMembers` names consistent between Task 2 and Task 3; `onUnfriend: ((String) async -> Void)?` matches the ContentView closure and the `unshareEverything(withFriend:)` signature. ✅

## Known follow-ups (carry to P2b / later)
- Unfriend removes my friend doc + all shared memberIds, but cannot delete the *other* user's friend doc (owner-only). Their friend entry for me dangles until they act — cosmetic (all sharing already removed). A reciprocal-cleanup Cloud Function is the eventual fix.
- Replacing a photo on a shared item you don't own can leave the previous owner's Storage object un-deleted (cross-user delete denied by Storage rules) — a harmless orphan; the new tokenized URL is what everyone reads.
