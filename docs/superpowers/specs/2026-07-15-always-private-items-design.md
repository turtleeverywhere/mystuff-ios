# Always-Private Items — Design

**Date:** 2026-07-15
**Status:** Approved

## Problem

Items can be pulled into a shared state automatically. Today the only such path is
`StuffViewModel.moveLocation`: when a location is reparented under a shared parent, the
destination's members are additively propagated across the moved subtree — including every
item within. A user may want specific items to stay private regardless of what happens to
their surrounding location. There is no way to opt an individual item out of automatic
sharing.

## Goal

Let a user flag an individual item as **always private**. Any flow that would automatically
add members to that item skips it. Manual, deliberate sharing of a flagged item is still
allowed.

## Decisions

- **Scope:** the flag blocks *automatic* propagation only. Manual "Share with friend" stays
  fully functional — a deliberate override.
- **On enable:** if the item is currently shared, turning the flag on immediately resets it to
  private (`memberIds = [owner]`), in the same write that sets the flag.
- **On disable:** clears the flag only; does not re-share or otherwise touch membership.

## Model

`MyStuff/Models/Item.swift`

Add:

```swift
/// When true, automatic member-propagation flows (e.g. moveLocation subtree share) skip
/// this item. Manual sharing is unaffected. Optional so legacy docs missing the field
/// decode cleanly — same idiom as ownerId/memberIds.
var isPrivate: Bool?
```

Wire the parameter through `init` (default `nil`). Callers test `item.isPrivate == true`.
No change to `Location`.

## View model

`MyStuff/ViewModels/StuffViewModel.swift`

**1. Guard the auto-share flow.** In `moveLocation`'s subtree *item* loop, skip flagged items:

```swift
for itemId in subtreeItemIds {
    guard let it = items.first(where: { $0.id == itemId }),
          canManageSharing(of: it),
          it.isPrivate != true else { continue }   // always-private opt-out
    ...
}
```

Descendant *locations* continue to propagate normally; only flagged items opt out. This is
the only current auto-share-item path. A comment documents that future automatic
member-adding flows over items must apply the same `isPrivate != true` guard.

**2. Toggle method.**

```swift
/// Set/clear the always-private flag. Enabling also resets the item to private
/// (members = [owner]) in a single write; disabling only clears the flag.
func setItemPrivate(_ item: Item, _ isPrivate: Bool) async
```

- Resolve the live item from `items`.
- Set `updated.isPrivate = isPrivate`.
- If `isPrivate == true`: also set `updated.memberIds = [updated.ownerId ?? currentUserId]`.
- Persist via the existing `persistItemMembers` helper (sets `updatedAt`, writes, reconciles
  local state, haptic).

## UI

`MyStuff/Views/ItemDetailSheet.swift`

Add a privacy card styled like `nfcSection` (icon + title row, `.ultraThinMaterial`
rounded background), placed in the main `VStack` after `nfcSection`:

- A `Toggle` labeled **"Always private"**, caption **"Excluded from automatic sharing."**
- Bound to `liveItem.isPrivate == true`; on change call
  `await viewModel.setItemPrivate(liveItem, newValue)`.
- The existing share toolbar button stays enabled regardless of the flag.

Enabling silently unshares an already-shared item (no confirmation dialog).

## Non-changes

- **MockDataService** — in-memory, no Codable path; new field needs no work.
- **Firestore rules** — `isPrivate` is not a security boundary. The owner writes their own
  doc; visibility is still governed by `memberIds`. No rule change.

## Out of scope (YAGNI)

- Lock/private badge on item cards in list/gallery views.
- A global "private by default" preference.

## Test / verification

No test target exists. Verify by building and driving the app:
1. Flag an item private in item detail; confirm toggle persists across sheet reopen.
2. Flag an already-shared item private; confirm it resets to unshared.
3. Move its location under a shared parent; confirm sibling (non-flagged) items gain the
   members but the flagged item does not.
4. Manually share a flagged item; confirm it still shares.
