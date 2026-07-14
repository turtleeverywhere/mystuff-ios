# Social Sharing — P0 Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add ownership + membership metadata (`ownerId`, `memberIds`) to Item and Location, backfill existing docs, route writes to the owner's subcollection, and deploy forward-compatible security rules + collectionGroup indexes — with **no visible behavior change**.

**Architecture:** Approach A from the spec — data stays under `users/{ownerId}/…`. Each Item/Location gains `ownerId` and `memberIds` (`[ownerId] + sharedWith`). P0 keeps the read path per-user (the collectionGroup switch is P2); it establishes the schema, owner-aware writes, migration, and rules so P1/P2 can build on a stable foundation.

**Tech Stack:** Swift 6 / SwiftUI, Firebase Firestore (Codable mapping), Firebase CLI for rules/indexes.

## Global Constraints

- iOS 26.0, Swift 6.0, bundle ID `com.flyingturtle.mystuff` — copied from CLAUDE.md.
- `@Observable` macro (not `ObservableObject`); `@Bindable` in views.
- Firestore uses Codable (`data(as:)` / `setData(from:)`).
- **No test target exists.** Verification = compile via `xcodebuild` + behavioral checks. Build command (run from repo root, ~30–90s, look for `** BUILD SUCCEEDED **`):
  ```
  xcodebuild -project MyStuff.xcodeproj -scheme MyStuff -destination 'generic/platform=iOS Simulator' -configuration Debug build
  ```
- Firebase prod project id: `mystuff-b072d`. There is no `.firebaserc` yet.
- New model fields are **optional** (`ownerId: String?`, `memberIds: [String]?`) so legacy Firestore docs (which lack them) still decode via Codable; migration backfills them.
- P0 must not change what the user sees. After P0, every entity has `memberIds == [ownerId]` and nothing is shared.

---

### Task 1: Add `ownerId` + `memberIds` to Item and Location

**Files:**
- Modify: `MyStuff/Models/Item.swift`
- Modify: `MyStuff/Models/Location.swift`

**Interfaces:**
- Produces:
  - `Item.ownerId: String?`, `Item.memberIds: [String]?`, init params `ownerId: String? = nil, memberIds: [String]? = nil`.
  - `Location.ownerId: String?`, `Location.memberIds: [String]?`, same init params.
  - `Item.members: [String]` and `Location.members: [String]` computed accessors (non-optional convenience).

- [ ] **Step 1: Add fields + accessor to `Item`**

In `MyStuff/Models/Item.swift`, add the two stored properties after `nfcTagUID` (before `createdAt`):

```swift
    var nfcTagUID: String?
    /// Owner's uid. Writes route to `users/{ownerId}/items`. nil on legacy docs until migrated.
    var ownerId: String?
    /// `[ownerId] + sharedWith`. The array queried for visibility. nil on legacy docs until migrated.
    var memberIds: [String]?
    var createdAt: Date
```

Add the two params to `init` (after `nfcTagUID`, before `createdAt`), with assignments:

```swift
        nfcTagUID: String? = nil,
        ownerId: String? = nil,
        memberIds: [String]? = nil,
        createdAt: Date = .now,
```

```swift
        self.nfcTagUID = nfcTagUID
        self.ownerId = ownerId
        self.memberIds = memberIds
        self.createdAt = createdAt
```

At the end of the struct (after the init closing brace, before the struct's closing brace) add:

```swift
    /// Non-optional membership convenience; falls back to `[ownerId]` for legacy docs.
    var members: [String] {
        if let memberIds, !memberIds.isEmpty { return memberIds }
        if let ownerId { return [ownerId] }
        return []
    }
```

- [ ] **Step 2: Add fields + accessor to `Location`**

In `MyStuff/Models/Location.swift`, add after `parentId` (before `createdAt`):

```swift
    var parentId: String?
    /// Owner's uid. Writes route to `users/{ownerId}/locations`. nil on legacy docs until migrated.
    var ownerId: String?
    /// `[ownerId] + sharedWith`. The array queried for visibility. nil on legacy docs until migrated.
    var memberIds: [String]?
    var createdAt: Date
```

Add init params (after `parentId`, before `createdAt`) + assignments:

```swift
        parentId: String? = nil,
        ownerId: String? = nil,
        memberIds: [String]? = nil,
        createdAt: Date = .now
```

```swift
        self.parentId = parentId
        self.ownerId = ownerId
        self.memberIds = memberIds
        self.createdAt = createdAt
```

Add accessor at end of struct:

```swift
    /// Non-optional membership convenience; falls back to `[ownerId]` for legacy docs.
    var members: [String] {
        if let memberIds, !memberIds.isEmpty { return memberIds }
        if let ownerId { return [ownerId] }
        return []
    }
```

- [ ] **Step 3: Build to verify it compiles**

Run: `xcodebuild -project MyStuff.xcodeproj -scheme MyStuff -destination 'generic/platform=iOS Simulator' -configuration Debug build 2>&1 | tail -20`
Expected: `** BUILD SUCCEEDED **`. (Adding optional fields with defaulted init params does not break existing call sites.)

- [ ] **Step 4: Commit**

```bash
git add MyStuff/Models/Item.swift MyStuff/Models/Location.swift
git commit -m "feat: add ownerId + memberIds to Item and Location models

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: Owner-aware write routing in the data layer

**Files:**
- Modify: `MyStuff/Services/DataService.swift`
- Modify: `MyStuff/Services/FirebaseDataService.swift`
- Modify: `MyStuff/Services/MockDataService.swift`

**Interfaces:**
- Consumes: `Item.ownerId`, `Item.memberIds`, `Location.ownerId`, `Location.memberIds` (Task 1).
- Produces: `DataService.currentUserId: String` (protocol requirement). All Item/Location writes route to `users/{ownerId}/…`; `addItem`/`addLocation` stamp `ownerId`/`memberIds` if absent.

- [ ] **Step 1: Add `currentUserId` to the protocol**

In `MyStuff/Services/DataService.swift`, add to the `protocol DataService` body (after the opening brace, before `// MARK: - Items`):

```swift
    /// Current authenticated user's uid. Empty string if unauthenticated (Firebase) or a stable
    /// constant (Mock). Used to stamp `ownerId`/`memberIds` on new entities.
    var currentUserId: String { get }
```

- [ ] **Step 2: Implement owner-aware routing in `FirebaseDataService`**

In `MyStuff/Services/FirebaseDataService.swift`, replace the computed collection properties and Item/Location CRUD. Replace lines from `private var userDoc` through the end of the Locations section with:

```swift
    var currentUserId: String { Auth.auth().currentUser?.uid ?? "" }

    private func userDoc(_ owner: String) -> DocumentReference {
        db.collection("users").document(owner)
    }
    private func itemsCollection(owner: String) -> CollectionReference {
        userDoc(owner).collection("items")
    }
    private func locationsCollection(owner: String) -> CollectionReference {
        userDoc(owner).collection("locations")
    }
    private var categoriesCollection: CollectionReference {
        userDoc(uid).collection("categories")
    }

    /// Owner path for a write. Falls back to the current user for brand-new local entities.
    private func owner(of ownerId: String?) -> String { ownerId ?? uid }

    // MARK: - Items

    func fetchItems(source: FetchSource) async throws -> [Item] {
        let snapshot = try await itemsCollection(owner: uid)
            .order(by: "createdAt", descending: true)
            .getDocuments(source: source.firestoreSource)
        return try snapshot.documents.map { try $0.data(as: Item.self) }
    }

    func addItem(_ item: Item) async throws {
        var item = item
        let owner = owner(of: item.ownerId)
        item.ownerId = owner
        if item.memberIds == nil || item.memberIds?.isEmpty == true { item.memberIds = [owner] }
        try itemsCollection(owner: owner).document(item.id).setData(from: item)
    }

    func updateItem(_ item: Item) async throws {
        try itemsCollection(owner: owner(of: item.ownerId)).document(item.id).setData(from: item, merge: true)
    }

    func deleteItem(_ item: Item) async throws {
        try await itemsCollection(owner: owner(of: item.ownerId)).document(item.id).delete()
    }

    // MARK: - Locations

    func fetchLocations(source: FetchSource) async throws -> [Location] {
        let snapshot = try await locationsCollection(owner: uid)
            .order(by: "createdAt", descending: true)
            .getDocuments(source: source.firestoreSource)
        return try snapshot.documents.map { try $0.data(as: Location.self) }
    }

    func addLocation(_ location: Location) async throws {
        var location = location
        let owner = owner(of: location.ownerId)
        location.ownerId = owner
        if location.memberIds == nil || location.memberIds?.isEmpty == true { location.memberIds = [owner] }
        try locationsCollection(owner: owner).document(location.id).setData(from: location)
    }

    func updateLocation(_ location: Location) async throws {
        try locationsCollection(owner: owner(of: location.ownerId)).document(location.id).setData(from: location, merge: true)
    }

    func deleteLocation(_ location: Location) async throws {
        try await locationsCollection(owner: owner(of: location.ownerId)).document(location.id).delete()
    }
```

> Note: the private `uid` computed property (which `fatalError`s when unauthenticated) stays as-is and is still used by `fetchItems`/`fetchLocations`/`categoriesCollection`. The Categories CRUD section below it is unchanged.

- [ ] **Step 3: Implement `currentUserId` in `MockDataService`**

In `MyStuff/Services/MockDataService.swift`, add near the top of the class body (after the stored properties, before `init()`):

```swift
    let currentUserId = "mock-user"
```

Then stamp ownership in `addItem`/`addLocation` so mock parity holds. Replace `addItem` and `addLocation`:

```swift
    func addItem(_ item: Item) async throws {
        var item = item
        if item.ownerId == nil { item.ownerId = currentUserId }
        if item.memberIds == nil { item.memberIds = [item.ownerId ?? currentUserId] }
        items.append(item)
    }
```

```swift
    func addLocation(_ location: Location) async throws {
        var location = location
        if location.ownerId == nil { location.ownerId = currentUserId }
        if location.memberIds == nil { location.memberIds = [location.ownerId ?? currentUserId] }
        locations.append(location)
    }
```

- [ ] **Step 4: Build to verify**

Run: `xcodebuild -project MyStuff.xcodeproj -scheme MyStuff -destination 'generic/platform=iOS Simulator' -configuration Debug build 2>&1 | tail -20`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add MyStuff/Services/DataService.swift MyStuff/Services/FirebaseDataService.swift MyStuff/Services/MockDataService.swift
git commit -m "feat: route Item/Location writes to owner subcollection

Adds DataService.currentUserId and stamps ownerId/memberIds on create.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: Stamp new entities + backfill legacy docs in `StuffViewModel`

**Files:**
- Modify: `MyStuff/ViewModels/StuffViewModel.swift`

**Interfaces:**
- Consumes: `DataService.currentUserId` (Task 2), `Item.ownerId/memberIds`, `Location.ownerId/memberIds` (Task 1).
- Produces: new entities carry `ownerId`/`memberIds` in local state; legacy docs are backfilled on load and persisted (mirrors the existing photo-migration pattern).

- [ ] **Step 1: Stamp ownership when creating entities**

In `StuffViewModel.addItem(name:notes:locationId:categoryId:)`, change the `Item(...)` construction to stamp ownership:

```swift
    func addItem(name: String, notes: String?, locationId: String?, categoryId: String?) async {
        let owner = service.currentUserId
        let item = Item(name: name, notes: notes, locationId: locationId, categoryId: categoryId, locationChangedAt: locationId != nil ? .now : nil, ownerId: owner, memberIds: [owner])
        do {
            try await service.addItem(item)
            if !items.contains(where: { $0.id == item.id }) {
                items.append(item)
            }
            HapticManager.success()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
```

In `StuffViewModel.addLocation(name:emoji:parentId:)`:

```swift
    func addLocation(name: String, emoji: String?, parentId: String? = nil) async {
        let owner = service.currentUserId
        let location = Location(name: name, emoji: emoji, parentId: parentId, ownerId: owner, memberIds: [owner])
        do {
            try await service.addLocation(location)
            locations.append(location)
            HapticManager.success()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
```

- [ ] **Step 2: Add sharing-field migration helpers**

In `StuffViewModel`, near the photo-migration helpers (after `migratedPhotoFields(_ item:)`), add:

```swift
    // MARK: - Sharing schema migration
    //
    // Legacy Item/Location docs predate `ownerId`/`memberIds`. Backfill on load so
    // collectionGroup `memberIds arrayContains` queries (P2) find them, and writes
    // route to the correct owner subcollection.

    private static func migratedSharingFields(_ item: Item, currentUid: String) -> Item {
        var u = item
        let owner = u.ownerId ?? currentUid
        u.ownerId = owner
        if u.memberIds == nil || (u.memberIds?.isEmpty ?? true) { u.memberIds = [owner] }
        return u
    }

    private static func migratedSharingFields(_ location: Location, currentUid: String) -> Location {
        var u = location
        let owner = u.ownerId ?? currentUid
        u.ownerId = owner
        if u.memberIds == nil || (u.memberIds?.isEmpty ?? true) { u.memberIds = [owner] }
        return u
    }
```

- [ ] **Step 3: Apply + persist backfill in `loadData`**

In `loadData()`, in the Stage 2 server block, after the existing lines that assign `items`/`locations`, thread the current uid and persist. Replace the Stage-2 `do { … }` server block body up to and including `await persistPhotoMigrationsIfNeeded(...)` with:

```swift
        do {
            let currentUid = service.currentUserId
            async let serverItems = service.fetchItems(source: .server)
            async let serverLocations = service.fetchLocations(source: .server)
            async let serverCategories = service.fetchCategories(source: .server)
            let rawItems = try await serverItems
            let rawLocations = try await serverLocations
            items = Self.deduped(Self.migratedPhotoFields(rawItems).map { Self.migratedSharingFields($0, currentUid: currentUid) })
            locations = Self.deduped(rawLocations.map { Self.migratedSharingFields($0, currentUid: currentUid) })
            categories = Self.deduped(try await serverCategories)
            // Persist any in-place migrations back to Firestore.
            await persistPhotoMigrationsIfNeeded(rawItems: rawItems)
            await persistSharingMigrationsIfNeeded(rawItems: rawItems, rawLocations: rawLocations, currentUid: currentUid)
        } catch {
```

- [ ] **Step 4: Add the sharing-migration persistence method**

After `persistPhotoMigrationsIfNeeded(rawItems:)`, add:

```swift
    private func persistSharingMigrationsIfNeeded(rawItems: [Item], rawLocations: [Location], currentUid: String) async {
        for raw in rawItems {
            let migrated = Self.migratedSharingFields(raw, currentUid: currentUid)
            if raw.ownerId != migrated.ownerId || raw.memberIds != migrated.memberIds {
                try? await service.updateItem(migrated)
            }
        }
        for raw in rawLocations {
            let migrated = Self.migratedSharingFields(raw, currentUid: currentUid)
            if raw.ownerId != migrated.ownerId || raw.memberIds != migrated.memberIds {
                try? await service.updateLocation(migrated)
            }
        }
    }
```

- [ ] **Step 5: Build to verify**

Run: `xcodebuild -project MyStuff.xcodeproj -scheme MyStuff -destination 'generic/platform=iOS Simulator' -configuration Debug build 2>&1 | tail -20`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Behavioral check (simulator)**

Run the app against the real Firestore account. Confirm: existing items/locations still load and display unchanged; no duplication; no errors surfaced. In Firebase Console, spot-check a previously-existing item doc now has `ownerId` (your uid) and `memberIds: [your uid]`. This is the "no visible change + backfill happened" gate.

- [ ] **Step 7: Commit**

```bash
git add MyStuff/ViewModels/StuffViewModel.swift
git commit -m "feat: stamp + backfill ownerId/memberIds on items and locations

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: Deploy forward-compatible security rules + collectionGroup indexes

**Files:**
- Modify: `firestore.rules`
- Create: `firestore.indexes.json`
- Modify: `firebase.json`
- Create: `.firebaserc`

**Interfaces:**
- Consumes: `memberIds` field written by Tasks 2–3.
- Produces: rules permitting owner access by path + member access by `memberIds`; `friendRequests` collection rules (used in P1); collectionGroup indexes for `items`/`locations` on `(memberIds CONTAINS, createdAt DESC)` (used in P2).

- [ ] **Step 1: Add `.firebaserc` (default project)**

Create `.firebaserc`:

```json
{
  "projects": {
    "default": "mystuff-b072d"
  }
}
```

- [ ] **Step 2: Rewrite `firestore.rules`**

Replace the entire contents of `firestore.rules` with:

```
rules_version = '2';

service cloud.firestore {
  match /databases/{database}/documents {

    function signedIn() {
      return request.auth != null;
    }
    function isMember() {
      return signedIn()
        && resource.data.memberIds is list
        && request.auth.uid in resource.data.memberIds;
    }
    function createdAsMember() {
      return signedIn()
        && request.resource.data.memberIds is list
        && request.auth.uid in request.resource.data.memberIds;
    }

    match /users/{uid} {
      // Profile doc (populated in P1). Owner-only for now.
      allow read, write: if signedIn() && request.auth.uid == uid;

      match /friends/{friendUid} {
        allow read, write: if signedIn() && request.auth.uid == uid;
      }

      match /categories/{categoryId} {
        allow read, write: if signedIn() && request.auth.uid == uid;
      }

      match /items/{itemId} {
        allow read:          if request.auth.uid == uid || isMember();
        allow create:        if request.auth.uid == uid && createdAsMember();
        allow update, delete: if request.auth.uid == uid || isMember();
      }

      match /locations/{locationId} {
        allow read:          if request.auth.uid == uid || isMember();
        allow create:        if request.auth.uid == uid && createdAsMember();
        allow update, delete: if request.auth.uid == uid || isMember();
      }
    }

    match /friendRequests/{requestId} {
      allow create: if signedIn() && request.resource.data.fromUid == request.auth.uid;
      allow read, update: if signedIn()
        && (request.auth.uid == resource.data.fromUid
            || request.auth.uid == resource.data.toUid);
    }
  }
}
```

> The old catch-all `match /users/{uid}/{document=**}` is intentionally removed in favor of explicit per-subcollection rules. The escalation guard for non-owner writes (can't drop the owner from `memberIds` / change `ownerId`) is deferred to the P2 plan, where non-owner members first exist.

- [ ] **Step 3: Create `firestore.indexes.json`**

Create `firestore.indexes.json`:

```json
{
  "indexes": [
    {
      "collectionGroup": "items",
      "queryScope": "COLLECTION_GROUP",
      "fields": [
        { "fieldPath": "memberIds", "arrayConfig": "CONTAINS" },
        { "fieldPath": "createdAt", "order": "DESCENDING" }
      ]
    },
    {
      "collectionGroup": "locations",
      "queryScope": "COLLECTION_GROUP",
      "fields": [
        { "fieldPath": "memberIds", "arrayConfig": "CONTAINS" },
        { "fieldPath": "createdAt", "order": "DESCENDING" }
      ]
    }
  ],
  "fieldOverrides": []
}
```

- [ ] **Step 4: Reference indexes in `firebase.json`**

Replace `firebase.json` with:

```json
{
  "firestore": {
    "rules": "firestore.rules",
    "indexes": "firestore.indexes.json"
  },
  "storage": {
    "rules": "storage.rules"
  }
}
```

- [ ] **Step 5: Deploy rules + indexes**

Run from repo root:

```bash
firebase deploy --only firestore:rules,firestore:indexes --project mystuff-b072d
```

Expected: `Deploy complete!`. If prompted to authenticate, run `firebase login` first. Index builds may take several minutes to finish in the Console (they build asynchronously; the P0 read path does not depend on them, so this does not block).

- [ ] **Step 6: Behavioral check — no regression under new rules**

With the new rules live, run the app and confirm normal item/location CRUD (add, edit, move, delete, photo) still works — this proves the owner-by-path clause (`request.auth.uid == uid`) preserves existing single-user behavior. Watch the Xcode console for any `PERMISSION_DENIED` Firestore errors; there should be none.

- [ ] **Step 7: Commit**

```bash
git add firestore.rules firestore.indexes.json firebase.json .firebaserc
git commit -m "feat: forward-compatible Firestore rules + collectionGroup indexes for sharing

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage (P0 slice of the spec):**
- Model fields `ownerId`/`memberIds` → Task 1. ✅
- Owner-aware write routing → Task 2. ✅
- Stamp-on-create + backfill migration (ordering: backfill before P2 read switch) → Task 3. ✅
- Security rules (owner-by-path + member-by-memberIds, friendRequests, categories owner-only) → Task 4. ✅
- Composite collectionGroup indexes deployed ahead of P2 → Task 4. ✅
- "No visible behavior change" → Tasks 3 Step 6 + 4 Step 6 behavioral gates. ✅

Deferred to later plans (correctly out of P0 scope): collectionGroup read switch, friend flow + Cloud Function + profile write (P1), sharing UI + move/share dialog + orphan handling + unfriend + storage rules (P2), push (P3).

**Placeholder scan:** No TBD/TODO/"handle edge cases"; every code step shows complete code. ✅

**Type consistency:** `currentUserId` (String) used identically in Firebase/Mock/VM; `ownerId: String?` and `memberIds: [String]?` consistent across models, services, VM, migration helpers; `migratedSharingFields` overloaded for Item and Location with matching `currentUid:` label. ✅

## Roadmap (subsequent plans — written when P0 lands)

- **P1 — Friends:** `UserProfile` write on sign-in; `SocialService` + `MockSocialService`; `SocialViewModel`; `lookupUserByEmail` callable Cloud Function (first Functions deploy); account-sheet Friends UI (add by email, incoming/outgoing requests, accept/deny); incoming-request badge on the account button.
- **P2 — Sharing:** switch `loadData` to collectionGroup `memberIds arrayContains` reads; share/unshare locations & items; create-shared-item; the move/share confirmation dialog (`moveItem`, `applyNFCUpdate`, share-item, shared-create); orphan sub-location display at root; unfriend auto-unshare; shared badges + owner labels; owner-scoped Storage paths + storage rules.
- **P3 — Push:** FCM token registration; push-sender Cloud Function on friendRequest/share create; APNs setup.
