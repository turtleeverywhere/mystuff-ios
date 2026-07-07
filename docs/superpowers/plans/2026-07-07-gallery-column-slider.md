# iPad Gallery Column Slider Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Toolbar slider on iPad (regular width) to set gallery column count 2–4, shared across Home + Items galleries, persisted.

**Architecture:** `ItemGalleryGrid` gains a `columns: Int = 2` init param and builds its `[GridItem]` dynamically. Both views store `@AppStorage("galleryColumns")` (same key → shared) and show a snapping `Slider` `ToolbarItem` left of the existing list/gallery toggle, only when gallery mode is active and `horizontalSizeClass == .regular`. iPhone always renders 2 columns.

**Tech Stack:** SwiftUI, iOS 26, Swift 6.

**Spec:** `docs/superpowers/specs/2026-07-07-gallery-column-slider-design.md`

## Global Constraints

- No test target. Verification per task = build from repo root:
  `xcodebuild -project MyStuff.xcodeproj -scheme MyStuff -destination 'generic/platform=iOS Simulator' -configuration Debug build 2>&1 | tail -3` → `** BUILD SUCCEEDED **` (~30-90s).
- AppStorage key exactly `"galleryColumns"`, default `2`, in BOTH views (shared setting).
- Slider: range `2...4`, `step: 1`, `.frame(width: 140)`, `.accessibilityLabel("Gallery columns")`.
- Slider visible ONLY when `isGallery && horizontalSizeClass == .regular`.
- iPhone (compact) galleries always get `columns: 2`.
- Commit only the files each task names.

---

### Task 1: Dynamic column count in ItemGalleryGrid

**Files:**
- Modify: `MyStuff/Views/ItemGalleryGrid.swift` (struct props ~line 10-19, both inits, `body` ~line 35)

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces: `ItemGalleryGrid.init(items:kind:columns:onTap:onAddPhoto:tileMenu:)` and convenience `init(items:kind:columns:onTap:onAddPhoto:)`, where `columns: Int = 2`. Task 2 passes `columns:` from both views.

- [ ] **Step 1: Replace hardcoded columns with param + computed grid**

In `ItemGalleryGrid`, add `let columns: Int` after `let kind: GalleryPhotoKind`, and replace:

```swift
    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]
```

with:

```swift
    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12), count: max(1, columns))
    }
```

Update `body`: `LazyVGrid(columns: gridColumns, spacing: 12)`.

- [ ] **Step 2: Add columns param to both inits (default 2)**

Main init:

```swift
    init(
        items: [Item],
        kind: GalleryPhotoKind,
        columns: Int = 2,
        onTap: @escaping (Item) -> Void,
        onAddPhoto: @escaping (Item) -> Void,
        @ViewBuilder tileMenu: @escaping (Item) -> TileMenu
    ) {
        self.items = items
        self.kind = kind
        self.columns = columns
        self.onTap = onTap
        self.onAddPhoto = onAddPhoto
        self.tileMenu = tileMenu
    }
```

`EmptyView` convenience init (in the `extension ItemGalleryGrid where TileMenu == EmptyView`): add the same `columns: Int = 2` param after `kind` and `self.columns = columns` assignment. Existing callers compile unchanged via the default.

- [ ] **Step 3: Build**

Run: `xcodebuild -project MyStuff.xcodeproj -scheme MyStuff -destination 'generic/platform=iOS Simulator' -configuration Debug build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add MyStuff/Views/ItemGalleryGrid.swift
git commit -m "feat: configurable column count in ItemGalleryGrid"
```

---

### Task 2: Column slider in Home + Items toolbars

**Files:**
- Create: `MyStuff/Views/GalleryColumnSlider.swift`
- Modify: `MyStuff/Views/HomeView.swift` (state ~line 20, toolbar ~line 76, gallery call ~line 491)
- Modify: `MyStuff/Views/ItemsView.swift` (state ~line 16, toolbar ~line 41, gallery call ~line 194)

**Interfaces:**
- Consumes: `ItemGalleryGrid` `columns: Int = 2` init param (Task 1).
- Produces: `GalleryColumnSlider` (no-arg `View`; owns its own `@AppStorage("galleryColumns")`), used by both toolbars.

- [ ] **Step 0: Create shared slider view**

Create `MyStuff/Views/GalleryColumnSlider.swift`:

```swift
import SwiftUI

/// Toolbar slider controlling the shared gallery column count (iPad only).
struct GalleryColumnSlider: View {
    @AppStorage("galleryColumns") private var galleryColumns = 2

    var body: some View {
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

- [ ] **Step 1: HomeView state**

After `@AppStorage("homeViewMode") private var viewMode = "list"` (line 20) add:

```swift
    @AppStorage("galleryColumns") private var galleryColumns = 2
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
```

(Note: `MoveItemSheet` further down in this file has its own `horizontalSizeClass` — that one stays; this adds one to the `HomeView` struct itself.)

- [ ] **Step 2: HomeView toolbar slider**

Inside `.toolbar { ... }`, directly BEFORE the existing `ToolbarItem(placement: .primaryAction)` containing the list/gallery toggle (line ~76), insert:

```swift
                if isGallery && horizontalSizeClass == .regular {
                    ToolbarItem(placement: .primaryAction) {
                        GalleryColumnSlider()
                    }
                }
```

- [ ] **Step 3: HomeView gallery call**

In `galleryGrid(_ items:)` (~line 491), add after the `kind: .location,` argument:

```swift
            columns: horizontalSizeClass == .regular ? galleryColumns : 2,
```

- [ ] **Step 4: ItemsView state**

After `@AppStorage("itemsViewMode") private var viewMode = "list"` (line 16) add:

```swift
    @AppStorage("galleryColumns") private var galleryColumns = 2
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
```

- [ ] **Step 5: ItemsView toolbar slider**

Inside `.toolbar { ... }`, directly BEFORE the existing `ToolbarItem(placement: .topBarTrailing)` containing the list/gallery toggle (line ~41), insert:

```swift
                if isGallery && horizontalSizeClass == .regular {
                    ToolbarItem(placement: .topBarTrailing) {
                        GalleryColumnSlider()
                    }
                }
```

- [ ] **Step 6: ItemsView gallery call**

In `itemsGallery` (~line 194), add after the `kind: .item,` argument:

```swift
                columns: horizontalSizeClass == .regular ? galleryColumns : 2,
```

- [ ] **Step 7: Build**

Run: `xcodebuild -project MyStuff.xcodeproj -scheme MyStuff -destination 'generic/platform=iOS Simulator' -configuration Debug build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 8: Commit**

```bash
git add MyStuff/Views/GalleryColumnSlider.swift MyStuff/Views/HomeView.swift MyStuff/Views/ItemsView.swift
git commit -m "feat: iPad column-count slider for Home + Items galleries"
```

---

## Manual Verification (post-plan)

iPad simulator: slider appears left of toggle only in gallery mode; drag 2→4 reflows grid with animation; switch tabs — same count (shared); relaunch — persists. iPhone simulator: no slider, 2 columns always.
