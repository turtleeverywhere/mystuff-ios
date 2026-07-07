# Long-Press Move-Item Context Menu Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Long-press context menu on item tiles/rows in Home + Items tabs with "Move to Location" opening the existing `MoveItemSheet`.

**Architecture:** SwiftUI `.contextMenu` on gallery tiles (via `ItemGalleryGrid`'s existing `tileMenu` support) and list rows. Home reuses its existing `selectedItem` → `MoveItemSheet` flow; Items tab gets new `movingItem` state + sheet. Thumbnail `onLongPressGesture` handlers removed (conflict with context menus).

**Tech Stack:** SwiftUI, iOS 26, Swift 6. MVVM — `StuffViewModel.moveItem(_:toLocationId:)` already exists.

**Spec:** `docs/superpowers/specs/2026-07-07-longpress-move-item-design.md`

## Global Constraints

- No test target exists. Verification per task = build:
  `xcodebuild -project MyStuff.xcodeproj -scheme MyStuff -destination 'generic/platform=iOS Simulator' -configuration Debug build` (run from repo root, expect `** BUILD SUCCEEDED **`, ~30-90s).
- Menu label copy exactly: "Move to Location", "Change Photo", "Details", "Edit", "Delete".
- SF Symbols: move = `arrow.right.circle`, photo = `camera`, details = `info.circle`, edit = `pencil`, delete = `trash`.
- Working tree has unrelated uncommitted changes — commit ONLY the files named in each task (`git add <exact paths>`, never `git add -A`).

---

### Task 1: Home tab context menus

**Files:**
- Modify: `MyStuff/Views/HomeView.swift` (galleryGrid ~line 491, itemRow ~line 509, itemThumbnail ~line 549)

**Interfaces:**
- Consumes: `ItemGalleryGrid.init(items:kind:onTap:onAddPhoto:tileMenu:)`; existing `@State` vars `selectedItem`, `photoSourceItem`, `showPhotoSource`, `detailItem` in HomeView.
- Produces: private `@ViewBuilder func itemMenuItems(_ item: Item) -> some View` (HomeView-internal only).

- [ ] **Step 1: Add shared menu builder to HomeView**

Insert after the `galleryGrid(_:)` function:

```swift
@ViewBuilder
private func itemMenuItems(_ item: Item) -> some View {
    Button {
        selectedItem = item
    } label: {
        Label("Move to Location", systemImage: "arrow.right.circle")
    }
    Button {
        photoSourceItem = item
        showPhotoSource = true
    } label: {
        Label("Change Photo", systemImage: "camera")
    }
    Button {
        detailItem = item
    } label: {
        Label("Details", systemImage: "info.circle")
    }
}
```

- [ ] **Step 2: Replace gallery onLongPress with tileMenu**

Replace the whole `galleryGrid(_:)` body:

```swift
private func galleryGrid(_ items: [Item]) -> some View {
    ItemGalleryGrid(
        items: items,
        kind: .location,
        onTap: { detailItem = $0 },
        onAddPhoto: { item in
            photoSourceItem = item
            showPhotoSource = true
        },
        tileMenu: { item in
            itemMenuItems(item)
        }
    )
}
```

(The `onLongPress:` argument is gone.)

- [ ] **Step 3: Add context menu to list row**

In `itemRow(_:tag:)`, after `.padding(.vertical, 4)` add:

```swift
.contextMenu {
    itemMenuItems(item)
}
```

- [ ] **Step 4: Remove thumbnail long-press**

In `itemThumbnail(_:)` (~line 565) delete this modifier only (keep `.onTapGesture` above it):

```swift
.onLongPressGesture {
    photoSourceItem = item
    showPhotoSource = true
}
```

- [ ] **Step 5: Build**

Run: `xcodebuild -project MyStuff.xcodeproj -scheme MyStuff -destination 'generic/platform=iOS Simulator' -configuration Debug build 2>&1 | tail -20`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add MyStuff/Views/HomeView.swift
git commit -m "feat: context menu with Move to Location on Home gallery tiles + list rows"
```

---

### Task 2: Items tab move support

**Files:**
- Modify: `MyStuff/Views/ItemsView.swift` (state ~line 7, sheets ~line 96, itemsList row ~line 166, itemsGallery tileMenu ~line 189, itemPhotoCircle ~line 230)

**Interfaces:**
- Consumes: `MoveItemSheet(item:viewModel:onMove:)` (defined in `HomeView.swift:623`, `onMove: (String?) -> Void`); `viewModel.moveItem(_ item: Item, toLocationId: String?) async`; existing `@State` vars `editingItem`, `photoSourceItem`, `showPhotoSource`.
- Produces: nothing consumed by other tasks.

- [ ] **Step 1: Add movingItem state**

After `@State private var editingItem: Item?` add:

```swift
@State private var movingItem: Item?
```

- [ ] **Step 2: Add MoveItemSheet presentation**

After the `.sheet(item: $editingItem) { ... }` block add:

```swift
.sheet(item: $movingItem) { item in
    MoveItemSheet(
        item: item,
        viewModel: viewModel,
        onMove: { locationId in
            Task { await viewModel.moveItem(item, toLocationId: locationId) }
        }
    )
    .presentationDetents([.medium])
}
```

- [ ] **Step 3: Add Move to gallery tileMenu**

In `itemsGallery`'s `tileMenu:` closure, insert as FIRST button (before the Edit button):

```swift
Button {
    movingItem = item
} label: {
    Label("Move to Location", systemImage: "arrow.right.circle")
}
```

- [ ] **Step 4: Add context menu to list row**

In `itemsList`, after the `.swipeActions(edge: .trailing, allowsFullSwipe: true) { ... }` block add:

```swift
.contextMenu {
    Button {
        movingItem = item
    } label: {
        Label("Move to Location", systemImage: "arrow.right.circle")
    }
    Button {
        editingItem = item
    } label: {
        Label("Edit", systemImage: "pencil")
    }
    Button {
        photoSourceItem = item
        showPhotoSource = true
    } label: {
        Label("Change Photo", systemImage: "camera")
    }
    Button(role: .destructive) {
        Task { await viewModel.deleteItem(item) }
    } label: {
        Label("Delete", systemImage: "trash")
    }
}
```

- [ ] **Step 5: Remove itemPhotoCircle long-press**

In `itemPhotoCircle(_:)` (~line 230) delete this modifier only (keep `.onTapGesture` above it):

```swift
.onLongPressGesture {
    photoSourceItem = liveItem
    showPhotoSource = true
}
```

- [ ] **Step 6: Build**

Run: `xcodebuild -project MyStuff.xcodeproj -scheme MyStuff -destination 'generic/platform=iOS Simulator' -configuration Debug build 2>&1 | tail -20`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 7: Commit**

```bash
git add MyStuff/Views/ItemsView.swift
git commit -m "feat: Move to Location in Items tab context menus"
```

---

### Task 3: Remove dead onLongPress from ItemGalleryGrid

**Files:**
- Modify: `MyStuff/Views/ItemGalleryGrid.swift`

**Interfaces:**
- Consumes: nothing (Tasks 1-2 removed the last `onLongPress:` caller; verify with `grep -rn "onLongPress" MyStuff/` — only ItemGalleryGrid.swift hits expected before this task).
- Produces: `ItemGalleryGrid.init(items:kind:onTap:onAddPhoto:tileMenu:)` and `init(items:kind:onTap:onAddPhoto:)` — signatures unchanged apart from dropped `onLongPress` param.

- [ ] **Step 1: Remove onLongPress from ItemGalleryGrid struct**

Delete from `ItemGalleryGrid`:
- property `var onLongPress: ((Item) -> Void)?`
- init param `onLongPress: ((Item) -> Void)? = nil,` and assignment `self.onLongPress = onLongPress`
- in `tile(_:)`, the `onLongPress: onLongPress` argument
- in the `EmptyView` convenience init: param `onLongPress: ((Item) -> Void)? = nil` and its assignment

- [ ] **Step 2: Remove long-press branch from GalleryTile**

Delete property `let onLongPress: ((Item) -> Void)?` and replace `GalleryTile.body`:

```swift
var body: some View {
    tileBody
}
```

(Delete the `if let onLongPress, hasPhoto { ... } else { ... }` branching.)

- [ ] **Step 3: Verify no remaining references**

Run: `grep -rn "onLongPress" MyStuff/`
Expected: no output.

- [ ] **Step 4: Build**

Run: `xcodebuild -project MyStuff.xcodeproj -scheme MyStuff -destination 'generic/platform=iOS Simulator' -configuration Debug build 2>&1 | tail -20`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add MyStuff/Views/ItemGalleryGrid.swift
git commit -m "refactor: drop unused onLongPress from ItemGalleryGrid"
```

---

## Manual Verification (post-plan)

Simulator, per spec Testing section:
1. Home gallery: long-press tile (with + without photo) → menu shows Move/Change Photo/Details; Move → sheet → pick location → tag updates; photo prompt fires if item has location photo.
2. Home list: long-press row → same menu; arrow button still works; thumbnail tap still previews.
3. Items gallery: long-press tile → menu incl. Move; move works (no photo prompt — by design).
4. Items list: long-press row → Move/Edit/Change Photo/Delete; tap=edit and swipe-delete still work.
