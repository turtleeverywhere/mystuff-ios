# Shared-location Scope + Coalesced Notifications Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users scope which sublocations get shared with a friend, and collapse every location-initiated (and location-move) share into a single push notification per recipient.

**Architecture:** Client resolves a share scope and writes membership across the chosen subtree, tagging every write with a per-action `shareBatchId`. A new top-level `shareEvents` collection carries one summary doc per recipient. Cloud Functions suppress the per-doc push when `shareBatchId` changed and send exactly one push from the `shareEvents` create trigger.

**Tech Stack:** Swift 6 / SwiftUI (`@Observable` + `@Bindable`), Firebase Firestore (Codable mapping), Cloud Functions (firebase-functions v1, Node).

## Global Constraints

- iOS 26.0, Swift 6.0, bundle ID `com.flyingturtle.mystuff`.
- No test target exists. Every client task verifies via build; behavior is checked manually. Build command (run from repo root, look for `** BUILD SUCCEEDED **`):
  ```
  xcodebuild -project MyStuff.xcodeproj -scheme MyStuff -destination 'generic/platform=iOS Simulator' -configuration Debug build
  ```
- New optional model fields must decode cleanly on legacy docs (declare as `Optional`, same idiom as `isPrivate` / `memberIds`).
- Sharing is owner-only: skip any entity where `!canManageSharing(of:)`. Always-private items (`isPrivate == true`) are never auto-shared.
- Notification push title stays `Location shared with you`. Summary body format: `${owner} shared "${name}"` + suffix — `(N items)`, `(M sublocations)`, `(N items, M sublocations)`, or no suffix when both are zero; singular/plural correct.
- Cloud Functions stay on the v1 API (`require("firebase-functions/v1")`).

---

### Task 1: Model fields, `ShareEvent` model, and `DataService.addShareEvent`

**Files:**
- Modify: `MyStuff/Models/Item.swift`
- Modify: `MyStuff/Models/Location.swift`
- Create: `MyStuff/Models/ShareEvent.swift`
- Modify: `MyStuff/Services/DataService.swift`
- Modify: `MyStuff/Services/FirebaseDataService.swift`
- Modify: `MyStuff/Services/MockDataService.swift`

**Interfaces:**
- Produces:
  - `Item.shareBatchId: String?`, `Location.shareBatchId: String?` (both with matching `init` params defaulting to `nil`).
  - `struct ShareEvent: Identifiable, Codable, Sendable` with `id, ownerId, recipientUid, locationId, locationName, itemCount, sublocationCount, createdAt`.
  - `func addShareEvent(_ event: ShareEvent) async throws` on `DataService`.

- [ ] **Step 1: Add `shareBatchId` to `Item`**

In `MyStuff/Models/Item.swift`, add the stored property after `memberIds` (line 26):

```swift
    /// Transient marker set on every write in a coalesced share/move batch. Cloud Functions
    /// use it to suppress per-doc push notifications (one summary push covers the batch).
    /// Optional so legacy docs missing the field decode cleanly.
    var shareBatchId: String?
```

Add the `init` parameter (after `memberIds: [String]? = nil,` on line 44) and assignment:

```swift
        memberIds: [String]? = nil,
        shareBatchId: String? = nil,
```

```swift
        self.memberIds = memberIds
        self.shareBatchId = shareBatchId
```

- [ ] **Step 2: Add `shareBatchId` to `Location`**

In `MyStuff/Models/Location.swift`, add after `memberIds` (line 11):

```swift
    /// Transient marker set on every write in a coalesced share/move batch. Cloud Functions
    /// use it to suppress per-doc push notifications (one summary push covers the batch).
    var shareBatchId: String?
```

Add to `init` (after `memberIds: [String]? = nil,` on line 20) and body:

```swift
        memberIds: [String]? = nil,
        shareBatchId: String? = nil,
```

```swift
        self.memberIds = memberIds
        self.shareBatchId = shareBatchId
```

- [ ] **Step 3: Create the `ShareEvent` model**

Create `MyStuff/Models/ShareEvent.swift`:

```swift
import Foundation

/// A single coalesced-share event. One doc per recipient in top-level `shareEvents`.
/// A Cloud Function turns each into exactly one push notification.
struct ShareEvent: Identifiable, Codable, Sendable {
    var id: String
    var ownerId: String
    var recipientUid: String
    var locationId: String
    var locationName: String
    var itemCount: Int
    var sublocationCount: Int
    var createdAt: Date

    init(
        id: String = UUID().uuidString,
        ownerId: String,
        recipientUid: String,
        locationId: String,
        locationName: String,
        itemCount: Int,
        sublocationCount: Int,
        createdAt: Date = .now
    ) {
        self.id = id
        self.ownerId = ownerId
        self.recipientUid = recipientUid
        self.locationId = locationId
        self.locationName = locationName
        self.itemCount = itemCount
        self.sublocationCount = sublocationCount
        self.createdAt = createdAt
    }
}
```

- [ ] **Step 4: Add `addShareEvent` to the `DataService` protocol**

In `MyStuff/Services/DataService.swift`, add after the location CRUD block (after line 43, `func deleteLocation`):

```swift
    // MARK: - Share Events
    func addShareEvent(_ event: ShareEvent) async throws
```

- [ ] **Step 5: Implement `addShareEvent` in `FirebaseDataService`**

In `MyStuff/Services/FirebaseDataService.swift`, add after `deleteLocation` (near line 140). `shareEvents` is a top-level collection (NOT under `users/{uid}`):

```swift
    // MARK: - Share Events

    func addShareEvent(_ event: ShareEvent) async throws {
        try db.collection("shareEvents").document(event.id).setData(from: event)
    }
```

- [ ] **Step 6: Implement no-op `addShareEvent` in `MockDataService`**

In `MyStuff/Services/MockDataService.swift`, add after `deleteLocation` (near line 110):

```swift
    func addShareEvent(_ event: ShareEvent) async throws {
        // No-op: mock data has no notification backend.
    }
```

- [ ] **Step 7: Build**

Run: `xcodebuild -project MyStuff.xcodeproj -scheme MyStuff -destination 'generic/platform=iOS Simulator' -configuration Debug build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 8: Commit**

```bash
git add MyStuff/Models/Item.swift MyStuff/Models/Location.swift MyStuff/Models/ShareEvent.swift MyStuff/Services/DataService.swift MyStuff/Services/FirebaseDataService.swift MyStuff/Services/MockDataService.swift
git commit -m "feat: add shareBatchId markers + ShareEvent model and addShareEvent"
```

---

### Task 2: Firestore rules for `shareEvents`

**Files:**
- Modify: `firestore.rules`

**Interfaces:**
- Produces: create-only access to `shareEvents` for the authenticated owner; no client reads (the function reads via admin).

- [ ] **Step 1: Add the `shareEvents` match block**

In `firestore.rules`, add inside the top-level `match /databases/{database}/documents { ... }` block, right after the `friendRequests` block (after line 67):

```
    match /shareEvents/{eventId} {
      // Client only creates its own share events; the Cloud Function reads via admin.
      allow create: if signedIn() && request.resource.data.ownerId == request.auth.uid;
    }
```

- [ ] **Step 2: Verify rules compile (optional deploy)**

If the Firebase CLI is available and authed:
Run: `firebase deploy --only firestore:rules`
Expected: `✔  Deploy complete!` (or `cloud.firestore: rules file firestore.rules compiled successfully` in a dry run).

If the CLI is not available, visually confirm the block is well-formed (balanced braces, `signedIn()` helper already defined at line 6).

- [ ] **Step 3: Commit**

```bash
git add firestore.rules
git commit -m "feat: firestore rules for shareEvents (create-only, owner-scoped)"
```

---

### Task 3: Cloud Functions — suppress per-doc pushes, send one summary push

**Files:**
- Modify: `functions/index.js`

**Interfaces:**
- Consumes: `sendPushToUser`, `displayNameFor`, `newlyAddedMembers` (existing helpers), and `after.shareBatchId` written by the client (Tasks 4–5).
- Produces: `onShareEventCreated` trigger on `shareEvents/{eventId}`.

- [ ] **Step 1: Suppress the per-item push for batch writes**

In `functions/index.js`, replace the body of `onItemUpdated` (lines 111-123) so it reads `before`/`after` and returns early when `shareBatchId` changed:

```javascript
exports.onItemUpdated = functions.firestore
    .document("users/{ownerId}/items/{itemId}")
    .onUpdate(async (change, context) => {
      const before = change.before.data();
      const after = change.after.data();
      const added = newlyAddedMembers(before, after, context.params.ownerId);
      if (added.length === 0) return;
      // Coalesced location/move shares tag every write with a fresh shareBatchId;
      // a single shareEvents push covers them, so suppress the per-item push.
      if (after.shareBatchId && after.shareBatchId !== before.shareBatchId) return;
      const name = await displayNameFor(context.params.ownerId);
      const itemName = after.name || "an item";
      await Promise.all(added.map((uid) => sendPushToUser(
          uid,
          {title: "Item shared with you", body: `${name} shared "${itemName}"`},
          {type: "itemShared", itemId: context.params.itemId},
      )));
    });
```

- [ ] **Step 2: Suppress the per-location push for batch writes**

Replace the body of `onLocationUpdated` (lines 126-138):

```javascript
exports.onLocationUpdated = functions.firestore
    .document("users/{ownerId}/locations/{locationId}")
    .onUpdate(async (change, context) => {
      const before = change.before.data();
      const after = change.after.data();
      const added = newlyAddedMembers(before, after, context.params.ownerId);
      if (added.length === 0) return;
      // Coalesced shares/moves are covered by a single shareEvents push.
      if (after.shareBatchId && after.shareBatchId !== before.shareBatchId) return;
      const name = await displayNameFor(context.params.ownerId);
      const locName = after.name || "a location";
      await Promise.all(added.map((uid) => sendPushToUser(
          uid,
          {title: "Location shared with you", body: `${name} shared "${locName}"`},
          {type: "locationShared", locationId: context.params.locationId},
      )));
    });
```

- [ ] **Step 3: Add the `onShareEventCreated` summary trigger**

Append to the end of `functions/index.js`:

```javascript
/** Coalesced location/subtree share → exactly one push to the recipient. */
exports.onShareEventCreated = functions.firestore
    .document("shareEvents/{eventId}")
    .onCreate(async (snap) => {
      const e = snap.data();
      if (!e || !e.recipientUid || !e.ownerId) return;
      const name = await displayNameFor(e.ownerId);
      const locName = e.locationName || "a location";
      const items = Number(e.itemCount) || 0;
      const subs = Number(e.sublocationCount) || 0;
      const parts = [];
      if (items > 0) parts.push(`${items} item${items === 1 ? "" : "s"}`);
      if (subs > 0) parts.push(`${subs} sublocation${subs === 1 ? "" : "s"}`);
      const suffix = parts.length ? ` (${parts.join(", ")})` : "";
      await sendPushToUser(
          e.recipientUid,
          {title: "Location shared with you", body: `${name} shared "${locName}"${suffix}`},
          {type: "locationShared", locationId: e.locationId || ""},
      );
    });
```

- [ ] **Step 4: Syntax-check**

Run: `node --check functions/index.js`
Expected: no output (exit 0). Any syntax error prints a location.

- [ ] **Step 5: Deploy (when Firebase CLI is available and authed)**

Run: `firebase deploy --only functions`
Expected: `✔  Deploy complete!` listing `onItemUpdated`, `onLocationUpdated`, `onShareEventCreated`.
(If the CLI is unavailable in this environment, note that the deploy is required before the client tasks can be verified end-to-end on device.)

- [ ] **Step 6: Commit**

```bash
git add functions/index.js
git commit -m "feat: coalesce share pushes via shareEvents; suppress per-doc pushes on batch writes"
```

---

### Task 4: `StuffViewModel` — scope enum, tree share/unshare, descendant helper

**Files:**
- Modify: `MyStuff/ViewModels/StuffViewModel.swift`

**Interfaces:**
- Consumes: `addShareEvent` (Task 1), existing `allDescendantIds(of:)`, `childLocations(for:)`, `canManageSharing(of:)`, `currentUserId`, `items`, `locations`, `HapticManager`.
- Produces:
  - `enum SublocationScope { case locationOnly, all, selected(Set<String>) }`
  - `func shareLocationTree(_ location: Location, withFriend uid: String, scope: SublocationScope) async`
  - `func unshareLocationTree(_ location: Location, fromFriend uid: String) async`
  - `func flattenedDescendantLocations(of location: Location) -> [(location: Location, depth: Int)]`

- [ ] **Step 1: Add the descendant-flattening helper**

In `MyStuff/ViewModels/StuffViewModel.swift`, add right after `flattenedDescendantItems(for:)` (after line 166):

```swift
    /// Descendant locations under `location`, depth-first, with depth relative to `location`
    /// (direct children = 0). Drives the "Choose sublocations" checklist.
    func flattenedDescendantLocations(of location: Location) -> [(location: Location, depth: Int)] {
        var result: [(Location, Int)] = []
        func walk(_ loc: Location, depth: Int) {
            let children = childLocations(for: loc)
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            for child in children {
                result.append((child, depth))
                walk(child, depth: depth + 1)
            }
        }
        walk(location, depth: 0)
        return result
    }
```

- [ ] **Step 2: Add the scope enum and `shareLocationTree`**

Add after `addMembers(_:toLocation:)` (after line 811). This shares the root + scoped, manageable sublocations + their non-private items, tagging each write with one `batchId`, then writes one `ShareEvent`:

```swift
    /// Which sublocations to include when sharing a location tree.
    enum SublocationScope: Equatable {
        case locationOnly
        case all
        case selected(Set<String>)
    }

    /// Share `location` (and scoped sublocations + their items) with `uid`, coalescing the
    /// recipient's notifications into a single `ShareEvent`. Skips entities I can't manage and
    /// always-private items. Assumes the caller only invokes this when `uid` is not yet a member
    /// of the root (toggle-on path).
    func shareLocationTree(_ location: Location, withFriend uid: String, scope: SublocationScope) async {
        let batchId = UUID().uuidString

        let subIds: Set<String>
        switch scope {
        case .locationOnly: subIds = []
        case .all: subIds = allDescendantIds(of: location.id)
        case .selected(let ids): subIds = ids
        }
        // Root + scoped sublocations, restricted to ones I own/manage.
        let targetLocationIds = ([location.id] + subIds).filter { id in
            guard let loc = locations.first(where: { $0.id == id }) else { return false }
            return canManageSharing(of: loc)
        }
        let targetSet = Set(targetLocationIds)

        var sharedSubCount = 0
        var sharedItemCount = 0
        do {
            // Locations (only those that don't already include uid).
            for id in targetLocationIds {
                guard var loc = locations.first(where: { $0.id == id }), !loc.members.contains(uid) else { continue }
                loc.memberIds = loc.members + [uid]
                loc.shareBatchId = batchId
                try await service.updateLocation(loc)
                if let i = locations.firstIndex(where: { $0.id == id }) { locations[i] = loc }
                if id != location.id { sharedSubCount += 1 }
            }
            // Items in any target location — skip private + not-manageable + already-shared.
            let shareableItems = items.filter {
                targetSet.contains($0.locationId ?? "")
                    && $0.isPrivate != true
                    && canManageSharing(of: $0)
                    && !$0.members.contains(uid)
            }
            for item in shareableItems {
                guard var it = items.first(where: { $0.id == item.id }) else { continue }
                it.memberIds = it.members + [uid]
                it.shareBatchId = batchId
                it.updatedAt = .now
                try await service.updateItem(it)
                if let i = items.firstIndex(where: { $0.id == it.id }) { items[i] = it }
                sharedItemCount += 1
            }
            try await service.addShareEvent(ShareEvent(
                ownerId: currentUserId,
                recipientUid: uid,
                locationId: location.id,
                locationName: location.name,
                itemCount: sharedItemCount,
                sublocationCount: sharedSubCount
            ))
            HapticManager.success()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
```

- [ ] **Step 3: Add `unshareLocationTree`**

Add directly after `shareLocationTree`. Full-subtree cleanup; no `ShareEvent` (removals don't notify). Mirrors the local-state handling in `persistLocationMembers` / `persistItemMembers` (drop docs that no longer include me):

```swift
    /// Remove `uid` from `location`, all descendant locations, and all their items.
    func unshareLocationTree(_ location: Location, fromFriend uid: String) async {
        let ids = allDescendantIds(of: location.id).union([location.id])
        do {
            for id in ids {
                guard var loc = locations.first(where: { $0.id == id }),
                      loc.members.contains(uid), canManageSharing(of: loc) else { continue }
                loc.memberIds = loc.members.filter { $0 != uid }
                try await service.updateLocation(loc)
                if loc.members.contains(currentUserId) {
                    if let i = locations.firstIndex(where: { $0.id == id }) { locations[i] = loc }
                } else {
                    locations.removeAll { $0.id == id }
                }
            }
            let treeItems = items.filter {
                ids.contains($0.locationId ?? "") && $0.members.contains(uid) && canManageSharing(of: $0)
            }
            for item in treeItems {
                guard var it = items.first(where: { $0.id == item.id }) else { continue }
                it.memberIds = it.members.filter { $0 != uid }
                it.updatedAt = .now
                try await service.updateItem(it)
                if it.members.contains(currentUserId) {
                    if let i = items.firstIndex(where: { $0.id == it.id }) { items[i] = it }
                } else {
                    items.removeAll { $0.id == it.id }
                }
            }
            HapticManager.success()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
```

- [ ] **Step 4: Build**

Run: `xcodebuild -project MyStuff.xcodeproj -scheme MyStuff -destination 'generic/platform=iOS Simulator' -configuration Debug build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add MyStuff/ViewModels/StuffViewModel.swift
git commit -m "feat: SublocationScope + shareLocationTree/unshareLocationTree + descendant helper"
```

---

### Task 5: Fold `moveLocation` subtree auto-share into the batch mechanism

**Files:**
- Modify: `MyStuff/ViewModels/StuffViewModel.swift:626-683`

**Interfaces:**
- Consumes: `SublocationScope`-era helpers plus `addShareEvent`, `shareBatchId` fields (Tasks 1, 4).
- Produces: `moveLocation` writes a `shareBatchId` on every propagation write and emits one `ShareEvent` per newly-added recipient.

- [ ] **Step 1: Rewrite `moveLocation` to tag writes and emit summary events**

Replace the whole method body (lines 626-683) with the version below. Changes vs. current: capture `preMembers` and a `batchId`; set `moved.shareBatchId` only when propagating; set `u.shareBatchId` on every descendant location/item write; count what was written; after the writes, emit one `ShareEvent` per recipient (destination members newly gaining the moved root, excluding the owner):

```swift
    func moveLocation(_ location: Location, toParentId newParentId: String?) async {
        guard var moved = locations.first(where: { $0.id == location.id }) else { return }

        let destMembers: [String]
        if let newParentId, let dest = locations.first(where: { $0.id == newParentId }) {
            destMembers = dest.members
        } else {
            destMembers = []
        }

        let batchId = UUID().uuidString
        let preMembers = Set(moved.members)

        moved.parentId = newParentId
        let propagating = !destMembers.isEmpty && canManageSharing(of: moved)
        if propagating {
            moved.memberIds = Array(Set(moved.members + destMembers))
            moved.shareBatchId = batchId
        }

        do {
            // Reparent + membership in one write.
            try await service.updateLocation(moved)
            if let i = locations.firstIndex(where: { $0.id == moved.id }) { locations[i] = moved }

            var movedSubCount = 0
            var movedItemCount = 0

            if propagating {
                let subtreeIds = allDescendantIds(of: location.id).union([location.id])
                let destSet = Set(destMembers)

                // Descendant locations (skip the moved location itself, already written).
                for locId in subtreeIds where locId != moved.id {
                    guard let loc = locations.first(where: { $0.id == locId }),
                          canManageSharing(of: loc) else { continue }
                    let current = loc.members
                    guard !destSet.isSubset(of: Set(current)) else { continue }
                    var u = loc
                    u.memberIds = Array(Set(current + destMembers))
                    u.shareBatchId = batchId
                    try await service.updateLocation(u)
                    if let i = locations.firstIndex(where: { $0.id == locId }) { locations[i] = u }
                    movedSubCount += 1
                }

                // Items anywhere in the moved subtree (snapshot ids first; re-find after each await).
                let subtreeItemIds = items.filter { subtreeIds.contains($0.locationId ?? "") }.map(\.id)
                for itemId in subtreeItemIds {
                    // Always-private items opt out of automatic member propagation.
                    guard let it = items.first(where: { $0.id == itemId }),
                          canManageSharing(of: it),
                          it.isPrivate != true else { continue }
                    let current = it.members
                    guard !destSet.isSubset(of: Set(current)) else { continue }
                    var u = it
                    u.memberIds = Array(Set(current + destMembers))
                    u.shareBatchId = batchId
                    u.updatedAt = .now
                    try await service.updateItem(u)
                    if let i = items.firstIndex(where: { $0.id == itemId }) { items[i] = u }
                    movedItemCount += 1
                }

                // One coalesced push per recipient who newly gains the moved root.
                let owner = moved.ownerId ?? currentUserId
                let recipients = destSet.subtracting(preMembers).subtracting([owner])
                for uid in recipients {
                    try await service.addShareEvent(ShareEvent(
                        ownerId: currentUserId,
                        recipientUid: uid,
                        locationId: moved.id,
                        locationName: moved.name,
                        itemCount: movedItemCount,
                        sublocationCount: movedSubCount
                    ))
                }
            }
            HapticManager.success()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
```

- [ ] **Step 2: Build**

Run: `xcodebuild -project MyStuff.xcodeproj -scheme MyStuff -destination 'generic/platform=iOS Simulator' -configuration Debug build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add MyStuff/ViewModels/StuffViewModel.swift
git commit -m "feat: coalesce moveLocation subtree auto-share into one push per recipient"
```

---

### Task 6: `LocationShareSheet` UI + wire into `LocationDetailView`

**Files:**
- Create: `MyStuff/Views/LocationShareSheet.swift`
- Modify: `MyStuff/Views/LocationDetailView.swift:117-134`

**Interfaces:**
- Consumes: `StuffViewModel.friends`, `sharedMembers(of:)`, `flattenedDescendantLocations(of:)`, `shareLocationTree`, `unshareLocationTree`, `SublocationScope`; `Location`.
- Produces: `struct LocationShareSheet: View` presented in place of `FriendShareSheet` for locations.

- [ ] **Step 1: Create `LocationShareSheet`**

Create `MyStuff/Views/LocationShareSheet.swift`. Scope selection only appears when the location has sublocations; membership state is read live from the view model so checkmarks update after each write:

```swift
import SwiftUI

/// Share a location with friends, scoping which sublocations are included.
/// Owner-only (the caller gates presentation). Coalesces notifications via the view model.
struct LocationShareSheet: View {
    let location: Location
    let viewModel: StuffViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var scopeMode: ScopeMode = .locationOnly
    @State private var selected: Set<String> = []
    @State private var busy = false

    enum ScopeMode: Hashable { case locationOnly, all, choose }

    private var descendants: [(location: Location, depth: Int)] {
        viewModel.flattenedDescendantLocations(of: location)
    }

    private var hasSublocations: Bool { !descendants.isEmpty }

    private var sharedUids: Set<String> {
        let live = viewModel.locations.first { $0.id == location.id } ?? location
        return Set(viewModel.sharedMembers(of: live))
    }

    private var scope: StuffViewModel.SublocationScope {
        switch scopeMode {
        case .locationOnly: return .locationOnly
        case .all: return .all
        case .choose: return .selected(selected)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if hasSublocations {
                    Section("Sublocations") {
                        Picker("Include", selection: $scopeMode) {
                            Text("This location only").tag(ScopeMode.locationOnly)
                            Text("All sublocations").tag(ScopeMode.all)
                            Text("Choose…").tag(ScopeMode.choose)
                        }
                        if scopeMode == .choose {
                            ForEach(descendants, id: \.location.id) { entry in
                                Button {
                                    if selected.contains(entry.location.id) {
                                        selected.remove(entry.location.id)
                                    } else {
                                        selected.insert(entry.location.id)
                                    }
                                } label: {
                                    HStack {
                                        Text(entry.location.name)
                                            .foregroundStyle(.primary)
                                            .padding(.leading, CGFloat(entry.depth) * 16)
                                        Spacer()
                                        Image(systemName: selected.contains(entry.location.id) ? "checkmark.square.fill" : "square")
                                            .foregroundStyle(selected.contains(entry.location.id) ? .green : .secondary)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                if viewModel.friends.isEmpty {
                    ContentUnavailableView {
                        Label("No Friends Yet", systemImage: "person.2")
                    } description: {
                        Text("Add friends from your account menu to share with them.")
                    }
                } else {
                    Section("Share \"\(location.name)\" with") {
                        ForEach(viewModel.friends) { friend in
                            Button {
                                let isShared = sharedUids.contains(friend.uid)
                                busy = true
                                Task {
                                    if isShared {
                                        await viewModel.unshareLocationTree(location, fromFriend: friend.uid)
                                    } else {
                                        await viewModel.shareLocationTree(location, withFriend: friend.uid, scope: scope)
                                    }
                                    busy = false
                                }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(friend.displayName).foregroundStyle(.primary)
                                        Text(friend.email).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if sharedUids.contains(friend.uid) {
                                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                    } else {
                                        Image(systemName: "circle").foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(busy)
                        }
                    }
                }
            }
            .navigationTitle("Share")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
```

- [ ] **Step 2: Present `LocationShareSheet` from `LocationDetailView`**

In `MyStuff/Views/LocationDetailView.swift`, replace the whole `.sheet(isPresented: $showShareSheet) { ... }` block (lines 117-134) with:

```swift
        .sheet(isPresented: $showShareSheet) {
            LocationShareSheet(location: live, viewModel: viewModel)
        }
```

- [ ] **Step 3: Build**

Run: `xcodebuild -project MyStuff.xcodeproj -scheme MyStuff -destination 'generic/platform=iOS Simulator' -configuration Debug build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Manual verification (simulator/device, requires deployed functions from Task 3)**

1. Open a location **with** sublocations → tap Share. Confirm the "Sublocations" picker appears (default **This location only**).
2. Pick **All sublocations**, toggle a friend on. On the recipient device/account: exactly **one** push, body like `<owner name> shared "Garage" (12 items, 3 sublocations)`. Tapping navigates to the location.
3. Pick **Choose…**, check one sublocation, share with a second friend. Only the root + that sublocation (+ their items) become shared; recipient count reflects it.
4. Toggle a friend **off** → friend loses access to the whole subtree (checkmarks clear).
5. Open a location **without** sublocations → no scope picker; sharing still yields one push.
6. Share a single item from item detail → still one per-item push (unchanged).
7. Move a location into a shared parent → each newly-added recipient gets one push, not one per doc.
8. Confirm an always-private item in a shared tree is never shared.

- [ ] **Step 5: Commit**

```bash
git add MyStuff/Views/LocationShareSheet.swift MyStuff/Views/LocationDetailView.swift
git commit -m "feat: LocationShareSheet with sublocation scope; wire into location detail"
```

---

## Self-Review Notes

- **Spec coverage:** scope prompt (Task 6) · scoped sublocation + item share (Task 4) · always-private/manageable skips (Tasks 4, 5) · coalesced push via `shareEvents` (Tasks 1, 3) · per-doc suppression (Task 3) · moveLocation coalescing (Task 5) · rules (Task 2). All spec sections mapped.
- **Type consistency:** `shareBatchId` (Item/Location), `ShareEvent(ownerId:recipientUid:locationId:locationName:itemCount:sublocationCount:)`, `SublocationScope.{locationOnly,all,selected}`, `shareLocationTree(_:withFriend:scope:)`, `unshareLocationTree(_:fromFriend:)`, `flattenedDescendantLocations(of:)` used identically across tasks and UI.
- **New-friend edge:** `shareLocationTree` assumes toggle-on (root not yet shared); `LocationShareSheet` enforces this by branching on `sharedUids.contains`.
```
