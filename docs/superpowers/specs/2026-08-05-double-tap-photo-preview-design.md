# Double-Tap Photo Preview — Design

**Date:** 2026-08-05
**Status:** Approved

## Goal

Double-tapping an item anywhere it is listed opens a large, zoomable preview of that item's photo.

## Scope

Six surfaces, across three views:

| Surface | Photo shown | Single tap | Double tap |
|---|---|---|---|
| Home — list row | location | `detailItem` (`ItemDetailSheet`) | preview if `hasLocationPhoto` |
| Home — gallery tile | location | `detailItem` | preview if `hasLocationPhoto` |
| Items — list row | item | `editingItem` (`ItemFormSheet`) | preview if `hasItemPhoto` |
| Items — gallery tile | item | `editingItem` | preview if `hasItemPhoto` |
| Location detail — list row | location | `detailItem` | preview if `hasLocationPhoto` |
| Location detail — gallery tile | location | `detailItem` | preview if `hasLocationPhoto` |

The previewed photo follows the surface, not a global rule: Home and Location detail are location-photo territory, the Items tab is item-photo territory. This matches the thumbnail each surface already renders.

When the relevant photo is missing, double-tap does nothing — the recognizer is not attached at all.

## Gesture Layer

List rows currently wrap the item name in a `Button`. A button consumes taps, so a row-wide double-tap cannot work while it is there. The inner `Button`s in `HomeView.itemRow`, `ItemsView.itemsList`, and `LocationDetailView`'s items section are replaced by a tappable row container:

```swift
.contentShape(Rectangle())
.onTapGesture(count: 2) { previewItem = item }   // attached only when the photo exists
.onTapGesture { detailItem = item }
.accessibilityAddTraits(.isButton)
```

Gallery tiles get the same pair inside `GalleryTile`, fed by a new `onDoubleTap: (Item) -> Void` parameter on `ItemGalleryGrid` (and on its `TileMenu == EmptyView` convenience initializer).

Consequences:

1. **Single tap is delayed ~0.25s** on rows and tiles that have a photo — SwiftUI waits to see whether a second tap lands. Rows without the relevant photo never attach the double-tap recognizer, so they stay instant.
2. **Button semantics are lost** when the inner `Button` goes away; recovered with `.accessibilityAddTraits(.isButton)`.
3. `swipeActions` and `contextMenu` are unaffected.

Controls that are their own tap targets stay `Button`s and keep swallowing their own taps: Home's trailing move arrow, and the thumbnail / placeholder tap targets described below.

Existing thumbnail behavior is preserved: tapping a row's photo thumbnail opens the preview (now the new viewer), and tapping a placeholder thumbnail opens the photo picker.

## The Viewer

### Prerequisite: a nameable photo kind

`PhotoView.Kind` is nested inside a generic type, so it cannot be spelled as a property type without supplying `Content` and `Placeholder`. `ItemGalleryGrid` already worked around this with a parallel `GalleryPhotoKind` enum plus a mapping at each use.

Lift the enum to file scope in `PhotoView.swift` as `PhotoKind` (cases `location`, `item`) and delete `GalleryPhotoKind`. `PhotoView`'s property becomes `let kind: PhotoKind`, so every existing `kind: .item` / `kind: .location` call site keeps compiling by inference; `ItemGalleryGrid` loses its `kind == .item ? .item : .location` mapping.

### The view

New file `MyStuff/Views/PhotoPreviewViewer.swift`:

```swift
struct PhotoPreviewViewer: View {
    let item: Item
    let kind: PhotoKind           // fixed per call site
    @Bindable var viewModel: StuffViewModel
}
```

Presented with `.fullScreenCover(item: $previewItem)`. Each call site holds its own `@State private var previewItem: Item?` and passes a constant `kind` — `.location` for Home and Location detail, `.item` for Items.

The viewer resolves the live item from `viewModel.items` (falling back to the captured value), matching how the current preview sheets stay in sync when a photo is swapped underneath them.

Contents and interaction:

- Black backdrop, `ignoresSafeArea`. `PhotoView(size: .full)` rendered `scaledToFit`.
- **Pinch to zoom** 1×–5× via `MagnifyGesture`, snapping back to 1× below threshold.
- **Double-tap inside the viewer** toggles 1× ↔ 2.5×, animated.
- **Drag** pans while zoomed. At 1×, a downward drag dismisses: the backdrop fades with distance and snaps back if the drag ends under threshold.
- Close `xmark` button top-trailing over the backdrop; item name top-leading, `.caption`, secondary.

### Replaced

`ItemPhotoPreviewSheet` (`ItemsView.swift:360`) and `LocationPhotoPreviewSheet` (`HomeView.swift:793`) are deleted. Both entry points — thumbnail tap and double-tap — open `PhotoPreviewViewer`, so one photo has exactly one preview UI.

## Loading vs. Failed

`PhotoView` keeps only `uiImage: UIImage?`, so "still resolving" and "every source failed" render identically — a photo that exists on the record but cannot be fetched spins forever.

Fixed additively, so the other eight call sites are untouched (a thumbnail is right to keep showing its placeholder either way):

```swift
/// Called once `resolve()` finishes; `false` means every source failed.
var onResolve: ((Bool) -> Void)? = nil
```

Invoked from the existing `.task(id: cacheKey)` after `resolve()` returns.

The viewer tracks the three states:

- resolving → `ProgressView`
- resolved → the photo
- failed → `ContentUnavailableView("Photo Unavailable", systemImage: "photo.badge.exclamationmark")`, caption "Couldn't load this photo. Check your connection."

No retry button: dismissing tears the viewer down, so double-tapping again re-runs the load.

## Edge Cases

- **No relevant photo** — no double-tap recognizer; a double tap degrades into two single taps, the second landing on the already-presented sheet. Unchanged from today's behavior.
- **Item deleted while the viewer is open** — the live lookup falls back to the captured item; the local photo file still renders.
- **Photo replaced while the viewer is open** — the live lookup picks up the new URL, `PhotoView`'s `cacheKey` changes, and the image reloads.

## Verification

No test target exists in this project, so verification is a clean build plus manual passes:

1. `xcodebuild` clean build succeeds.
2. All six surfaces: double-tap opens the viewer with the correct photo for that surface.
3. Viewer: pinch zoom, double-tap zoom toggle, pan while zoomed, swipe-down dismiss, close button.
4. Single tap still reaches detail / edit on every surface.
5. Rows and tiles without the relevant photo: double tap does nothing beyond the normal single-tap result, and single tap is not delayed.
6. Airplane mode with a remote-only photo: the viewer lands on the failed state, not an endless spinner.
7. Swipe actions and context menus still work on the rewritten rows.
