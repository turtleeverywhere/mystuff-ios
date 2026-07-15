# Shared-location sublocation scope + coalesced notifications

Date: 2026-07-15
Status: Approved (design)

## Problem

Two gaps in the location-sharing flow:

1. **Sublocations are never shared.** Sharing a location ([LocationDetailView.swift](../../../MyStuff/Views/LocationDetailView.swift) share sheet)
   shares only the location and its *direct* items. A location with sublocations gives no way to
   include them.
2. **Notification spam.** Notifications are server-side Firestore triggers, one per doc
   ([functions/index.js](../../../functions/index.js) `onItemUpdated` / `onLocationUpdated`). Sharing a
   location with many items fires one push per item. `moveLocation`'s subtree auto-share has the same
   problem — one push per moved doc, per newly-added member.

## Goals

- When sharing a location that has sublocations, let the user choose scope: **This location only** /
  **All sublocations** / **Choose…** (individual sublocations).
- Shared sublocations also share their items (skipping always-private items), matching direct-item behavior.
- Collapse every location-initiated share (and `moveLocation` subtree auto-share) into **one** push per
  recipient: `Alice shared "Garage" (12 items, 3 sublocations)`.

## Non-goals

- Direct single-item sharing (item-detail path) keeps its per-item push, unchanged.
- No in-app activity feed (the `shareEvents` collection is push-only for now).

## Design

### 1. Sublocation scope UI — `LocationShareSheet` (new)

Replaces the `FriendShareSheet` call in [LocationDetailView.swift:117](../../../MyStuff/Views/LocationDetailView.swift).
`FriendShareSheet` is untouched and still used for item sharing.

- **Scope selection** (only rendered when the location has sublocations): a `Menu`/`Picker` with
  - `This location only` — **default**. Location + its direct items (today's behavior).
  - `All sublocations` — whole subtree.
  - `Choose…` — reveals an inline checklist of descendants (indented via `flattenedLocationTree`
    depth). Checking a sublocation shares **only that node** (+ its own direct items) — descendants
    are NOT auto-included; each must be checked individually.
- **Friend rows** below, same row visual as `FriendShareSheet`. Toggling a friend **on** shares per
  the current scope; **off** unshares the whole subtree.
- Scope is chosen once and applies to subsequent friend toggles in the sheet. Changing scope after a
  toggle only affects later toggles (documented behavior, not retroactive).
- No sublocations → no scope UI; sheet behaves like today (but notification is now coalesced).

### 2. Share logic — `StuffViewModel`

```swift
enum SublocationScope { case locationOnly, all, selected(Set<String>) }
```

- `shareLocationTree(_ location:, withFriend uid: String, scope: SublocationScope) async`
  1. `let batchId = UUID().uuidString`
  2. Resolve target location ids: `[location.id]` plus, per scope: none / `allDescendantIds(of:)` /
     the selected set. Keep only locations where `canManageSharing(of:)`.
  3. Shareable items: `items` whose `locationId` is in the target set, excluding `isPrivate == true`
     and any where `!canManageSharing(of:)`.
  4. For each target location and item not already sharing `uid`: append `uid` to `memberIds`, set
     `shareBatchId = batchId`, persist via `service.updateLocation` / `service.updateItem`, update
     local state.
  5. Write **one** `ShareEvent` via `service.addShareEvent(...)` with
     `itemCount` = items actually shared, `sublocationCount` = sublocations actually shared.
- `unshareLocationTree(_ location:, fromFriend uid: String) async` — remove `uid` from the root, **all**
  descendant locations, and all their items (full subtree cleanup regardless of original scope). No
  `ShareEvent` (removals never notify).
- Existing `shareItem` / `unshareItem` / `shareLocation` / `unshareLocation` remain; the item-detail
  single-item path keeps its per-item push.

### 3. `moveLocation` coalescing

`moveLocation` ([StuffViewModel.swift:626](../../../MyStuff/ViewModels/StuffViewModel.swift)) already
propagates `destMembers` across the moved subtree. Fold it into the same mechanism:

- Generate one `batchId` for the move; set `shareBatchId = batchId` on every propagation write (moved
  root, descendant locations, items).
- Recipients = `destMembers` newly added to the moved root (i.e. not already members, excluding owner).
- Emit one `ShareEvent` per recipient for the moved location, with `itemCount` / `sublocationCount` =
  count of items / descendant locations written in this move (union count; same for all recipients —
  acceptable approximation for a notification).

### 4. Data model

- `Item.shareBatchId: String?` and `Location.shareBatchId: String?` — optional suppression markers.
  Decode cleanly on legacy docs (same idiom as `isPrivate` / `memberIds`). Set only during batch
  writes; normal edits leave them unchanged.
- New model `ShareEvent` (top-level `shareEvents/{autoId}`):
  ```swift
  struct ShareEvent: Codable, Sendable {
      var id: String           // auto
      var ownerId: String
      var recipientUid: String
      var locationId: String
      var locationName: String
      var itemCount: Int
      var sublocationCount: Int
      var createdAt: Date
  }
  ```

### 5. `DataService`

- Add `func addShareEvent(_ event: ShareEvent) async throws`.
- `FirebaseDataService`: writes to top-level `shareEvents` collection (NOT under `users/{uid}`).
- `MockDataService`: no-op (or in-memory append; not surfaced anywhere).

### 6. Server — `functions/index.js`

- `onItemUpdated` / `onLocationUpdated`: after computing `added`, if
  `after.shareBatchId && after.shareBatchId !== before.shareBatchId` → **return** (suppress). This
  covers location-share batches and `moveLocation` batches. Non-batch writes (single item share) are
  unaffected.
- New `onShareEventCreated` (`functions.firestore.document("shareEvents/{id}").onCreate`):
  send exactly one push to `recipientUid`:
  - title: `Location shared with you`
  - body: `${ownerName} shared "${locationName}"` + count suffix:
    - both zero → no suffix
    - `(N items)` / `(N sublocations)` / `(N items, M sublocations)`, singular/plural correct
  - data: `{ type: "locationShared", locationId }` (reuses existing tap→navigate intent in
    `PushNotificationManager`).
  - `ownerName` via existing `displayNameFor(ownerId)`.

### 7. Security rules — `firestore.rules`

```
match /shareEvents/{eventId} {
  allow create: if signedIn() && request.resource.data.ownerId == request.auth.uid;
  // No client read/update/delete; the Cloud Function reads via admin.
}
```

## Edge cases

- Location with zero items and zero sublocations shared → one `ShareEvent`, body has no count suffix.
- `isPrivate` items and not-manageable (owned-by-others) entities are skipped in both share and move
  propagation — consistent with the existing `moveLocation` guard.
- `unshareLocationTree` removing *me* from a doc I co-own drops it from local state via the existing
  member-removal handling.
- Re-sharing the same location with a second friend generates a fresh `batchId` → new `ShareEvent` →
  one push to the second friend only.

## Testing

No test target exists (per CLAUDE.md). Manual verification:
1. Share a location with sublocations → scope prompt appears; each option shares the correct set.
2. Recipient receives exactly one push with correct counts; tapping navigates to the location.
3. Share a location with many direct items → one push, not N.
4. `moveLocation` into a shared parent → recipients each get one push, not one per doc.
5. Single-item share from item detail → still one per-item push (unchanged).
6. Always-private items are never shared by tree-share or move.
