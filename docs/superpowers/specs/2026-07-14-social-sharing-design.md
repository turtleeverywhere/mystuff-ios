# Social Sharing — Design

**Date:** 2026-07-14
**Status:** Approved (brainstorming), pending implementation plan

## Goal

Let a user share locations and items with other MyStuff users (e.g. a partner).
Support: sharing existing locations, sharing existing items, creating already-shared
items. Connect to people by email → friend request → accept/deny. Recipients with
"view + edit" rights see shared content merged into their normal tabs. Unshared
items inside a shared location stay invisible to the recipient.

## Decisions (locked)

| Topic | Decision |
|---|---|
| Recipient rights | **View + edit** (edit/move/add photos, add items to shared locations) |
| Notifications | In-app now; **push deferred to a later phase** |
| Invite target | Recipient **must already have** a MyStuff account |
| Recipient view | Shared content **merged into normal tabs**, badged |
| Data model | **Approach A** — keep `users/{ownerId}/…` subcollections + `memberIds` + collectionGroup query |
| Email lookup | **Cloud Function** (profiles stay private) |
| Share-time parity | Sharing an item in a not-shared location prompts the same dialog as moving |
| Move into private location | Confirmation dialog: *share location too* / *make item private* |
| Orphan sub-locations | Shown at root for the viewer |
| Unfriend | Auto-unshares everything between the two users |

## Data Model

### Item / Location — new fields
- `ownerId: String` — owner uid; used to route writes to `users/{ownerId}/…`.
- `memberIds: [String]` — `[ownerId] + sharedWith`. The single array queried for
  visibility. Owner is always a member.

Backfill for existing docs (migration): `ownerId = currentUid`,
`memberIds = [currentUid]`. Done transparently on load and persisted, mirroring the
existing photo-field migration in `StuffViewModel`.

### Category
Stays per-user and unshared. A shared item's `categoryId` will not resolve for a
recipient → recipient sees it uncategorized. Accepted.

### New models
- **`UserProfile`** — `users/{uid}` doc: `{ uid, email, displayName, photoURL }`.
  Written on sign-in. Private (readable only by self); email→uid resolution happens
  via Cloud Function, so profiles need not be world-readable.
- **`FriendRequest`** — `friendRequests/{id}` (top-level):
  `{ id, fromUid, fromEmail, fromName, toUid, status: pending|accepted|declined,
  createdAt, respondedAt? }`. Denormalized from-name/email so the recipient renders
  the request without reading the sender's profile.
- **`Friend`** — `users/{uid}/friends/{friendUid}`:
  `{ uid, email, displayName, photoURL, since }`. Written on both sides at accept
  time (each user writes only their own subcollection). Gives each side the other's
  display info locally — used to label shared entities with the owner's name.

## Loading (merged own + shared)

Replace the current per-subcollection fetch with one collectionGroup query each:

```
collectionGroup("items").where("memberIds", arrayContains: myUid)
collectionGroup("locations").where("memberIds", arrayContains: myUid)
```

Returns own **and** shared entities together. Categories remain a plain per-user
fetch (`users/{uid}/categories`). Requires composite indexes on
`(memberIds arrayContains, createdAt desc)` for both collections — deployed via
`firestore.indexes.json`.

**Migration ordering:** backfill `memberIds`/`ownerId` on existing docs *before*
switching the read path to collectionGroup (otherwise legacy docs without
`memberIds` are missed by `arrayContains`). Backfill runs on first load of the new
build, writing to the current per-user subcollections (still owner-scoped).

## Write routing & edit semantics

Every write targets `users/{entity.ownerId}/…` — **not** the caller's uid.
`DataService` add/update/delete methods become owner-aware (derive path from
`ownerId`, falling back to current uid for new local entities). A recipient editing
a shared item writes into the owner's subcollection; the security rule permits it
because the recipient is in `memberIds`. Conflict policy: last-write-wins via
`setData(merge:)` — acceptable for a small trusted group.

## Friend flow

1. Account sheet → **Friends** → "Add by email".
2. Client calls Cloud Function `lookupUserByEmail(email)` → `{ uid, displayName,
   photoURL }` or null. Null → "No MyStuff user with that email."
3. Guard against self, duplicate pending, and existing friendship.
4. Create `friendRequest` (status `pending`).
5. Recipient sees incoming requests in the account sheet, with Accept / Deny, plus a
   badge on the account button (count of incoming pending).
6. **Accept** → set status `accepted`, write `friends` doc on both sides.
   **Deny** → status `declined`.
7. Push notification for new requests/shares: deferred to the push phase.

## Sharing mechanics & privacy

Sharing = mutating `memberIds`. You can only share with existing friends.

- **Share location** → add friendUid to `location.memberIds`. Optional toggle "also
  share its N items" (default **off** — items stay private).
- **Share item** → add friendUid to `item.memberIds`. If the item's location is not
  shared with that friend, show the **share-time dialog** (below).
- **Create shared item** → item form gains a "Share with" friend picker; sets
  `memberIds` at creation. Same dialog logic if placed in a not-shared location.
- **Unshare** → remove friendUid from `memberIds`.

**Privacy requirement (falls out for free):** a recipient's collectionGroup query
only returns entities where they are in `memberIds`. Visibility is strictly
per-entity and never inherited from the parent location — so unshared items inside a
shared location never appear for the recipient.

### The share/move dialog (shared item ↔ not-shared location)

Triggered when a shared item would end up in a location not shared with (at least
one of) the item's members — via **moving** the item, **sharing** the item, or
**creating** a shared item in a private location.

> "This item is shared, but this location isn't. Share the location too, or keep the
> item private?"
> - **Share location** → add the item's shared members to the location's `memberIds`.
> - **Make item private** → remove sharing from the item (`memberIds = [ownerId]`).

Applies to `moveItem`, the NFC move path (`applyNFCUpdate`), the share-item action,
and shared-item creation.

### Orphan display (recipient side)
- Shared child location whose parent isn't shared → shown at root for that viewer
  (VM treats `parentId` as nil when the parent isn't visible).
- The move/share dialog prevents shared items from landing in invisible locations,
  so a shared item should normally always have a visible location for its members.

### Unfriend
Removes the friendship on both sides and removes each user from every entity the
other shared with them (strip the uid from `memberIds` across shared items/locations).

## Security rules

Rewrite `firestore.rules`:

- `users/{uid}` (profile doc): read/write only by `uid`.
- `users/{uid}/friends/{fid}`: read/write only by `uid` (each side writes its own).
- `users/{uid}/categories/{id}`: read/write only by `uid`.
- `users/{uid}/{items|locations}/{id}`:
  - **read**: `request.auth.uid in resource.data.memberIds`.
  - **update/delete**: `request.auth.uid in resource.data.memberIds`; a non-owner
    write must not change `ownerId` and must not remove the owner from `memberIds`.
  - **create**: `request.resource.data.ownerId == uid` and
    `request.auth.uid in request.resource.data.memberIds`.
- `friendRequests/{id}`: **create** if `request.resource.data.fromUid ==
  request.auth.uid`; **read/update** if `request.auth.uid in [fromUid, toUid]`.

Rules must be tested carefully (prior expired-rules incident, 2026-07). Include the
collectionGroup read-rule form so `arrayContains` queries pass.

Storage rules: photo paths become owner-scoped
(`users/{ownerId}/…`); allow read/write to a member. (Refine in the plan — Storage
rules can't read Firestore, so gate by path ownership + authed; acceptable given
photos aren't highly sensitive. Revisit if needed.)

## Cloud Function

`lookupUserByEmail` (callable): input email → queries the profiles by email
server-side (admin SDK, bypasses client rules) → returns minimal `{ uid,
displayName, photoURL }` or null. Keeps profiles private on the client. This is the
first Firebase Functions deployment for the repo; the push-notification sender is a
second Function added in the push phase.

## Service / ViewModel layer

- **`SocialService`** protocol + `FirebaseSocialService` / `MockSocialService`:
  `lookupUser(email)`, `sendRequest`, `fetchIncomingRequests`,
  `fetchOutgoingRequests`, `respond(to:accept:)`, `fetchFriends`, `removeFriend`.
- **`SocialViewModel`** (new) — owns friends + requests state and the account-area
  logic. Keeps the already-large `StuffViewModel` focused.
- Sharing mutations (add/remove `memberIds`, the dialog resolution) live on
  `StuffViewModel` since they operate on items/locations. `DataService` write methods
  become owner-aware.

## UI touchpoints

- **Account sheet** (`ProfileSheet`): new **Friends** section — friends list,
  incoming requests (Accept/Deny), outgoing pending, "Add by email".
- **Account button** (`ContentView`/`HomeView`): badge = incoming pending count.
- **`LocationDetailView`**: "Share" action → friend picker (+ optional include-items).
- **`ItemDetailSheet`**: "Share" action → friend picker (may trigger share dialog).
- **Item form**: "Share with" picker at create.
- **Lists** (`ItemsView`, `LocationsView`): shared badge (people icon) + owner name
  on entities you don't own.

## Phasing

- **P0 — Foundation.** Add `ownerId`/`memberIds` to models; backfill migration;
  owner-aware read/write; security rules; composite indexes. No visible behavior
  change (`memberIds = [self]`).
- **P1 — Friends.** `SocialService` + `SocialViewModel`; `lookupUserByEmail` Cloud
  Function; profile-doc write on sign-in; account UI (add/accept/deny); in-app
  notifier badge.
- **P2 — Sharing.** Switch loading to collectionGroup; share/unshare locations &
  items; create-shared-item; the move/share dialog; orphan handling; unfriend
  auto-unshare; shared badges + owner labels.
- **P3 — Push.** FCM token registration; push-sender Cloud Function on
  friendRequest/share create; APNs setup.

## Out of scope
- Group sharing / roles beyond a single member list.
- Real-time presence or activity feed.
- Sharing categories.
- Per-field/partial-edit permissions (edit is all-or-nothing on a shared entity).

## Open risks
- Security-rule correctness for cross-user writes (test thoroughly — past incident).
- Storage rules can't consult Firestore `memberIds`; photo access gated by path +
  auth only. Acceptable for now; revisit if sensitive.
- collectionGroup composite indexes must be deployed before the P2 read switch.
