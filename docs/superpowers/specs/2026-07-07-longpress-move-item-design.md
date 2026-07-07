# Long-Press Context Menu for Item Location Assignment

**Date:** 2026-07-07
**Status:** Approved

## Problem

In Home tab gallery mode there is no way to assign/change an item's location. Long-press currently opens the photo picker. In Home list mode the only entry point is a small `arrow.right.circle` button. Items tab has no move affordance at all.

## Solution

Long-press (iOS context menu) on any item — gallery tile or list row, in both Home and Items tabs — offers **Move to Location**, opening the existing `MoveItemSheet`.

## Changes

### Home tab (`HomeView.swift`)

**Gallery grid** (`galleryGrid(_:)`, ~line 491):
- Remove `onLongPress` parameter (currently opens photo picker).
- Use `ItemGalleryGrid`'s existing `tileMenu` support with menu:
  - **Move to Location** → `selectedItem = item` (opens existing `MoveItemSheet`)
  - **Change Photo** → `photoSourceItem = item; showPhotoSource = true`
  - **Details** → `detailItem = item`
- Context menu applies to all tiles, with or without photo.

**List row** (`itemRow(_:tag:)`, ~line 509):
- Add `.contextMenu` with same entries: Move to Location / Change Photo / Details.
- Existing arrow button (`selectedItem = item`) stays.

Existing post-move "Update photo for new location?" confirmation keeps working unchanged — both paths go through `selectedItem` → `MoveItemSheet` → `onMove`.

### Items tab (`ItemsView.swift`)

**New state + sheet:**
- `@State private var movingItem: Item?`
- `.sheet(item: $movingItem)` presenting `MoveItemSheet(item:viewModel:onMove:)`, `onMove` → `Task { await viewModel.moveItem(item, toLocationId: locationId) }`, `.presentationDetents([.medium])`.
- No photo-update prompt after move (that flow is Home-specific; `ItemDetailSheet` not wired in `ItemsView`).

**Gallery** (`itemsGallery`, ~line 179):
- Add **Move to Location** button to existing `tileMenu` (before Change Photo): `movingItem = item`.

**List row** (`itemsList`, ~line 138):
- Add `.contextMenu`: Move to Location / Edit / Change Photo / Delete (mirrors gallery menu). Existing tap=edit and swipe-delete stay.

### `ItemGalleryGrid.swift`

- `onLongPress` remains supported but Home no longer passes it. If no other caller uses it after this change, remove the parameter and the `onLongPressGesture` branch in `GalleryTile`.

## Not Changing

- `MoveItemSheet` itself — reused as-is.
- Photo-tap behaviors (tap photoless tile = add photo; thumbnail tap = preview).

## Also Removing

- Thumbnail `onLongPressGesture` handlers in Home list rows (`HomeView.swift:565`) and Items list rows (`ItemsView.swift:230`): they'd conflict with the new row context menu. Change Photo lives in the menu instead.

## Testing

No test target exists. Verify by build (`xcodebuild`) + manual: long-press tile/row in each tab & mode, confirm menu, move item, confirm location tag updates, confirm Home photo prompt still fires when item has location photo.
