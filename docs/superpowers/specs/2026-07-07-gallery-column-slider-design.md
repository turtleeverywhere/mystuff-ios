# iPad Gallery Column-Count Slider

**Date:** 2026-07-07
**Status:** Approved

## Problem

Gallery grids (Home + Items) are hardcoded to 2 columns. On iPad there is room for more; user wants to pick 2–4 columns with a slider in the toolbar, left of the list/gallery toggle.

## Solution

Shared, persisted column count (2–4) driven by a toolbar slider, visible only on iPad (regular width) while gallery mode is active. Applies to both Home and Items galleries.

## Changes

### `MyStuff/Views/ItemGalleryGrid.swift`

- Add `let columns: Int` to `ItemGalleryGrid` with init param `columns: Int = 2` (both inits: main + `EmptyView` convenience).
- Replace the hardcoded `private let columns = [GridItem...]` with a computed property:

```swift
private var gridColumns: [GridItem] {
    Array(repeating: GridItem(.flexible(), spacing: 12), count: max(1, columns))
}
```

- `LazyVGrid(columns: gridColumns, spacing: 12)`.
- Default `2` keeps existing callers/behavior unchanged until they pass a value.

### Both `HomeView.swift` and `ItemsView.swift`

- Add:
  - `@AppStorage("galleryColumns") private var galleryColumns = 2` (same key in both → shared setting).
  - `@Environment(\.horizontalSizeClass) private var horizontalSizeClass`.
- Pass `columns: horizontalSizeClass == .regular ? galleryColumns : 2` to their `ItemGalleryGrid` call — iPhone stays at 2 regardless of what was set on iPad.
- New toolbar item, declared BEFORE the existing list/gallery toggle `ToolbarItem` so it renders to its left, same placement family as that view's toggle (Home: `.primaryAction`; Items: `.topBarTrailing`):

```swift
if isGallery && horizontalSizeClass == .regular {
    ToolbarItem(placement: <same as toggle>) {
        Slider(
            value: Binding(
                get: { Double(galleryColumns) },
                set: { newValue in
                    withAnimation { galleryColumns = Int(newValue.rounded()) }
                }
            ),
            in: 2...4,
            step: 1
        )
        .frame(width: 140)
        .accessibilityLabel("Gallery columns")
    }
}
```

- Slider snaps to 2/3/4; grid re-lays out with animation.

## Not Changing

- iPhone (compact width): never shows the slider, always renders 2 columns.
- List modes, context menus, photo behaviors.

## Testing

No test target. Build (`xcodebuild`) + manual on iPad simulator: slider appears left of toggle only in gallery mode; drag 2→4 reflows both tabs' grids; value persists across relaunch; iPhone unaffected.
