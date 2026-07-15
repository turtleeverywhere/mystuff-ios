# Move Location — Design

## Goal

In the Locations tab, long-pressing a location currently offers only **Add Sub-location**. Add a **Move** action that lets the user reparent the selected location — either under another location (making it a sub-location) or to the top level (root). Primary use case: boxes that get physically moved between rooms/locations frequently.

## Scope

- **In:** "Move" context-menu item + a dedicated `MoveLocationSheet` picker.
- **In:** Move any *visible* location, including locations shared with the user.
- **In (revision, 2026-07-15):** share-membership propagation on move — see "Revision: share propagation" below.
- **Out (YAGNI):** QR-scan-to-move; multi-select move; drag-and-drop reordering.

## UI

### Context menu (`LocationsView.swift`, `.contextMenu` ~line 184)

Add a second item below the existing "Add Sub-location":

```swift
Button {
    movingLocation = entry.location
} label: {
    Label("Move", systemImage: "folder")
}
```

New `@State private var movingLocation: Location?` on `LocationsView`.

### MoveLocationSheet (new, in `LocationsView.swift`)

Mirrors the existing `MoveItemSheet` pattern (List-based tree picker with size-class-aware detents).

- Presented via `.sheet(item: $movingLocation) { location in MoveLocationSheet(...) }`.
- Body switches sizing on `horizontalSizeClass`: `.presentationSizing(.page)` in regular width (iPad form sheet), `.presentationDetents([.medium])` otherwise — identical to `MoveItemSheet`.
- `NavigationStack` → `List` with a single section titled `Move "<name>" to…`:
  - **Root row:** `Button` labeled "Root (top level)", icon `house`, selects `parentId = nil`. Tinted `.accentColor` when the location is already a root (`location.parentId == nil`), else `.primary`.
  - **Target rows:** `ForEach(viewModel.flattenedLocationTree(excluding: location.id), id: \.location.id)`. Each row is a `Button` with the location emoji (fallback `📍`) as icon and name as label, indented `CGFloat(entry.depth) * 20`. Tinted `.accentColor` when `entry.location.id == location.parentId` (current parent), else `.primary`.
- Navigation title "Move Location", inline; Cancel toolbar button dismisses.

`flattenedLocationTree(excluding: location.id)` already excludes the location itself **and all its descendants** (via `allDescendantIds`), so cycles are structurally impossible — no extra guard needed.

## Behavior / data flow

On tapping a target (root or a location):

1. Look up the live location from `viewModel.locations` (fallback to the passed-in value).
2. Build an updated copy with the new `parentId` (`nil` for root).
3. `await viewModel.updateLocation(updated)` — this already persists via `service.updateLocation` and updates the local `locations` array + fires success haptic.
4. If moved under a parent, `expandedIds.insert(newParentId)` in `LocationsView` so the moved node is visible in the tree after the sheet dismisses.
5. `dismiss()`.

Selecting the current parent is a harmless no-op re-save (allowed).

Because the sheet needs to mutate `LocationsView`'s `expandedIds`, the move/expand logic lives in a closure passed from `LocationsView` (e.g. `onMove: (String?) -> Void`), matching how `MoveItemSheet` takes an `onMove` closure. `MoveLocationSheet` itself owns dismissal and calls `onMove(newParentId)`.

## No new viewModel API

`StuffViewModel.updateLocation(_:)` already handles persistence and local state for a changed `parentId`. No new method required.

## Revision: share propagation (2026-07-15)

**Motivation:** Moving a location under a *shared* parent failed silently. The move wrote the child with `memberIds = [me]` while its new parent is shared; Firestore security rules reject the inconsistent parent/child membership, and the known "errorMessage-never-shown" bug hid the failure — so it looked like "can't move to a shared location." Users also want the moved location (a box) to become visible to the parent's collaborators automatically.

**Behavior:** Introduce `StuffViewModel.moveLocation(_ location: Location, toParentId newParentId: String?) async` as the single move entry point. It:

1. Reparents the location (`parentId = newParentId`).
2. Resolves `destMembers` = the new parent's `members` (empty when moving to root).
3. When `destMembers` is non-empty, **additively** unions those members into `memberIds` of every entity in the moved subtree that the current user owns (`canManageSharing == true`):
   - the moved location itself — its membership is set in the **same write** as the reparent, which is what satisfies the security rules and unblocks the move;
   - every descendant location (`allDescendantIds(of: location.id)`);
   - every item whose `locationId` is the moved location or any descendant.
4. Skips entities owned by someone else, and skips writes where the union adds no new members.
5. Moving to **root** (`newParentId == nil`) changes no membership.
6. **Additive only** — moving a shared location out to root or a private parent never removes members (users un-share manually via the share sheet).

Membership union is order-insensitive because `ownerId` is a separate field, so `Array(Set(existing + destMembers))` is used.

**UI:** The picker is unchanged (shared locations already appear via `flattenedLocationTree`). `MoveLocationSheet` gains a section footer: "Moving into a shared location shares this location and its contents with the same people." The sheet's `onMove` closure calls `moveLocation` instead of `updateLocation`; `expandedIds.insert(newParentId)` stays in the view.

**Pattern precedent:** owner-managed, additive membership union already used by `MoveItemsHereSheet.confirmMove` (`addMembers`) and the `LocationDetailView` share flow.

## Testing

No test target exists in this project. Manual verification:

1. Long-press a root location → **Move** → pick another location → it becomes a sub-location, parent auto-expands, count badges update.
2. Long-press a sub-location → **Move** → **Root (top level)** → it returns to top level.
3. Confirm the moved location's own descendants and the location itself are absent from the target list (no self/descendant targets).
4. Current parent (or Root, when already root) row shows accent tint.
5. A location shared with you can be moved.
6. iPad: sheet renders as a page-sized form; iPhone: medium detent.
7. Move a private location (with items + a sub-location containing items) under a location shared with a friend → the move succeeds, and the moved location, its sub-location, and all their items gain the friend as a member (collaborator sees the whole box). Verify from the friend's account if possible.
8. Move that now-shared location back to root → it stays shared (additive-only; membership unchanged).
9. Move a location under a **private** parent or to root → no membership changes.
