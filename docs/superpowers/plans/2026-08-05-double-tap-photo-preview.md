# Double-Tap Photo Preview Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Double-tapping an item row or gallery tile opens a full-screen, zoomable preview of that surface's photo.

**Architecture:** A new `PhotoPreviewViewer` replaces the two existing preview sheets and is presented via `.fullScreenCover` from Home, Items, and Location detail. Inner name `Button`s in list rows are replaced by row-level tap gestures so a row-wide double-tap can register, and `ItemGalleryGrid` gains an optional double-tap callback. `PhotoView` gains a resolution callback so the viewer can distinguish "still loading" from "failed".

**Tech Stack:** SwiftUI (iOS 26), Swift 6, MVVM with `@Observable` / `@Bindable`. No third-party additions.

**Spec:** `docs/superpowers/specs/2026-08-05-double-tap-photo-preview-design.md`

## Global Constraints

- Target iOS 26.0, Swift 6.0. Xcode project is `MyStuff.xcodeproj`, scheme `MyStuff`.
- **There is no test target in this project.** Verification for every task is a compile plus, at the end, a manual simulator pass. Do not add a test target — it is out of scope for this plan.
- Build command, run from the repo root:
  ```
  xcodebuild -project MyStuff.xcodeproj -scheme MyStuff -destination 'generic/platform=iOS Simulator' -configuration Debug build
  ```
  Takes 30–90s. Success marker is `** BUILD SUCCEEDED **` near the end of the output.
- Follow existing conventions: `@Observable` view models passed as `@Bindable`, `.ultraThinMaterial` surfaces, haptics only via `HapticManager`.
- New files must be added to the Xcode project. This project uses Xcode 26's synchronized file-system groups, so a new `.swift` file under `MyStuff/Views/` is picked up automatically — no `.pbxproj` edit needed. If a build fails with "cannot find PhotoPreviewViewer in scope", open the project in Xcode once to let it sync.
- Photo choice follows the surface, never a global rule: Home and Location detail preview the **location** photo, the Items tab previews the **item** photo.
- A row or tile whose relevant photo is missing must NOT attach a double-tap recognizer at all — this is what keeps its single tap instant.

## File Structure

| File | Responsibility | Change |
|---|---|---|
| `MyStuff/Utilities/PhotoView.swift` | Local-first photo loading | Lift `Kind` to file-scope `PhotoKind`; add `onResolve` callback |
| `MyStuff/Views/ItemGalleryGrid.swift` | Gallery grid + tile | Use `PhotoKind`; add optional `onDoubleTap` |
| `MyStuff/Views/PhotoPreviewViewer.swift` | Full-screen zoomable viewer | **New** |
| `MyStuff/Views/ItemsView.swift` | Items tab | Row gestures, gallery wiring, cover; delete `ItemPhotoPreviewSheet` |
| `MyStuff/Views/HomeView.swift` | Home tab | Row gestures, gallery wiring, cover; delete `LocationPhotoPreviewSheet` |
| `MyStuff/Views/LocationDetailView.swift` | Location detail | Row gestures, gallery wiring, cover |

---

### Task 1: Lift `PhotoKind` and add resolution reporting to `PhotoView`

`PhotoView.Kind` is nested inside a generic type, so `PhotoPreviewViewer` cannot declare a property of that type without supplying `Content` and `Placeholder`. Lifting it to file scope also lets `ItemGalleryGrid` drop its parallel `GalleryPhotoKind` enum and the mapping that went with it. Every existing call site passes `kind: .item` / `kind: .location` by inference, so none of them change.

**Files:**
- Modify: `MyStuff/Utilities/PhotoView.swift:10-65`
- Modify: `MyStuff/Views/ItemGalleryGrid.swift:1-100`

**Interfaces:**
- Consumes: nothing (first task).
- Produces:
  - `enum PhotoKind { case location, item }` at file scope in `PhotoView.swift`.
  - `PhotoView` property `let kind: PhotoKind`.
  - `PhotoView` property `var onResolve: ((Bool) -> Void)? = nil`, called once per resolution with `true` when an image was produced and `false` when every source failed. Positioned after `size` and before the two `@ViewBuilder` properties, so the memberwise initializer reads `PhotoView(item:kind:size:onResolve:content:placeholder:)`.
  - `GalleryPhotoKind` no longer exists.

- [ ] **Step 1: Replace the nested `Kind` enum with a file-scope `PhotoKind`**

In `MyStuff/Utilities/PhotoView.swift`, delete the nested `enum Kind` (lines 12-21) and add this above `struct PhotoView`, below the existing doc comment block:

```swift
/// Which of an item's two photos to render: the item itself, or the place it is stored.
enum PhotoKind {
    case location, item

    fileprivate var filename: String {
        switch self {
        case .location: return "photo"
        case .item: return "item_photo"
        }
    }
}
```

- [ ] **Step 2: Point `PhotoView` at the new type and add `onResolve`**

Replace the property block (was lines 35-41) with:

```swift
    let item: Item
    let kind: PhotoKind
    let size: TargetSize
    /// Called once resolution finishes. `false` means every source failed —
    /// callers use it to tell "still loading" apart from "gave up".
    var onResolve: ((Bool) -> Void)? = nil
    @ViewBuilder var content: (Image) -> Content
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var uiImage: UIImage?
```

- [ ] **Step 3: Report the outcome from the existing task**

Replace the `.task(id: cacheKey)` modifier in `body` with:

```swift
        .task(id: cacheKey) {
            let resolved = await resolve()
            uiImage = resolved
            onResolve?(resolved != nil)
        }
```

Leave `cacheKey` and `resolve()` alone — `kind.filename` and the `kind == .location` comparisons still compile, because a payload-free enum is automatically `Equatable`.

- [ ] **Step 4: Delete `GalleryPhotoKind` and use `PhotoKind` in the grid**

In `MyStuff/Views/ItemGalleryGrid.swift`, delete this declaration entirely (lines 3-6):

```swift
/// Which of an item's two photos a gallery tile shows.
enum GalleryPhotoKind {
    case item, location
}
```

Then replace every remaining `GalleryPhotoKind` with `PhotoKind` — four sites: `ItemGalleryGrid.kind` (line 11), the designated `init` parameter (line 23), the `TileMenu == EmptyView` convenience `init` parameter (line 64), and `GalleryTile.kind` (line 82).

- [ ] **Step 5: Drop the now-pointless kind mapping in the tile**

In `GalleryTile.tileBody`, the `PhotoView` call currently translates between the two enums. Replace:

```swift
                    PhotoView(
                        item: item,
                        kind: kind == .item ? .item : .location,
                        size: .thumbnail(480)
                    ) { image in
```

with:

```swift
                    PhotoView(
                        item: item,
                        kind: kind,
                        size: .thumbnail(480)
                    ) { image in
```

- [ ] **Step 6: Build**

Run: `xcodebuild -project MyStuff.xcodeproj -scheme MyStuff -destination 'generic/platform=iOS Simulator' -configuration Debug build`
Expected: `** BUILD SUCCEEDED **`. No call site outside these two files should need an edit; if one fails to compile, it is passing `kind:` explicitly typed somewhere and should be changed to rely on inference.

- [ ] **Step 7: Commit**

```bash
git add MyStuff/Utilities/PhotoView.swift MyStuff/Views/ItemGalleryGrid.swift
git commit -m "refactor: file-scope PhotoKind + PhotoView resolution callback"
```

---

### Task 2: Build `PhotoPreviewViewer`

The viewer, not yet wired to anything. Building it standalone means a compile failure here is unambiguous.

**Files:**
- Create: `MyStuff/Views/PhotoPreviewViewer.swift`

**Interfaces:**
- Consumes: `PhotoKind` and `PhotoView(item:kind:size:onResolve:content:placeholder:)` from Task 1. `viewModel.location(for:)` and `viewModel.items` from `StuffViewModel` (both already exist). `Item.hasItemPhoto` / `Item.hasLocationPhoto` from the extension at the bottom of `PhotoView.swift`.
- Produces:
  - `PhotoPreviewViewer(item: Item, kind: PhotoKind, viewModel: StuffViewModel)`, presented by Tasks 4–6 via `.fullScreenCover`.
  - `View.itemTapGestures(previewEnabled:onPreview:onOpen:)`, the single place the "no recognizer without a photo" rule lives. Used by Tasks 3–6.

- [ ] **Step 1: Write the file**

Create `MyStuff/Views/PhotoPreviewViewer.swift` with exactly this content:

```swift
import SwiftUI

/// Full-screen photo viewer: pinch to zoom, drag to pan, swipe down to dismiss.
/// Reached by double-tapping an item row or gallery tile, or by tapping a row's
/// photo thumbnail.
struct PhotoPreviewViewer: View {
    let item: Item
    let kind: PhotoKind
    @Bindable var viewModel: StuffViewModel

    @Environment(\.dismiss) private var dismiss

    /// Resolution outcome reported by `PhotoView` — nil while still resolving.
    @State private var didResolve: Bool?
    /// Committed zoom, and the live delta from an in-flight pinch.
    @State private var zoom: CGFloat = 1
    @State private var gestureZoom: CGFloat = 1
    /// Committed pan, and the live delta from an in-flight drag.
    @State private var offset: CGSize = .zero
    @State private var gestureOffset: CGSize = .zero
    /// Vertical travel of a swipe-to-dismiss drag. Only ever non-zero at 1x.
    @State private var dismissDrag: CGFloat = 0

    private let maxZoom: CGFloat = 5
    private let doubleTapZoom: CGFloat = 2.5
    private let dismissThreshold: CGFloat = 150

    /// Follow the view model so a photo swapped underneath the viewer redraws.
    private var liveItem: Item {
        viewModel.items.first(where: { $0.id == item.id }) ?? item
    }

    private var hasPhoto: Bool {
        kind == .item ? liveItem.hasItemPhoto : liveItem.hasLocationPhoto
    }

    private var currentZoom: CGFloat { zoom * gestureZoom }

    /// Slack of 0.01 keeps float noise from reading as "zoomed".
    private var isZoomed: Bool { currentZoom > 1.01 }

    private var backdropOpacity: Double {
        max(0, 1 - Double(abs(dismissDrag) / (dismissThreshold * 3)))
    }

    var body: some View {
        ZStack {
            Color.black
                .opacity(backdropOpacity)
                .ignoresSafeArea()

            photoLayer
                .scaleEffect(currentZoom)
                .offset(
                    x: offset.width + gestureOffset.width,
                    y: offset.height + gestureOffset.height + dismissDrag
                )
                .gesture(magnifyGesture)
                .simultaneousGesture(dragGesture)
                .onTapGesture(count: 2) { toggleZoom() }
        }
        .overlay(alignment: .topLeading) { caption }
        .overlay(alignment: .topTrailing) { closeButton }
        .statusBarHidden()
    }

    // MARK: - Photo

    @ViewBuilder
    private var photoLayer: some View {
        if hasPhoto {
            PhotoView(
                item: liveItem,
                kind: kind,
                size: .full,
                onResolve: { didResolve = $0 }
            ) { image in
                image
                    .resizable()
                    .scaledToFit()
            } placeholder: {
                if didResolve == false {
                    unavailableState
                } else {
                    ProgressView()
                        .tint(.white)
                }
            }
        } else {
            unavailableState
        }
    }

    private var unavailableState: some View {
        ContentUnavailableView {
            Label("Photo Unavailable", systemImage: "photo.badge.exclamationmark")
        } description: {
            Text("Couldn't load this photo. Check your connection.")
        }
        .foregroundStyle(.white)
    }

    // MARK: - Chrome

    private var caption: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(liveItem.name)
                .font(.headline)
                .foregroundStyle(.white)
            if let location = viewModel.location(for: liveItem) {
                HStack(spacing: 4) {
                    Text(location.emoji ?? "📍")
                    Text(location.name)
                }
                .font(.caption)
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial, in: Capsule())
            }
        }
        .padding()
        .opacity(isZoomed ? 0 : 1)
        .animation(.easeInOut(duration: 0.2), value: isZoomed)
        .allowsHitTesting(false)
    }

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.headline)
                .foregroundStyle(.white)
                .padding(10)
                .background(.ultraThinMaterial, in: Circle())
        }
        .padding()
        .accessibilityLabel("Close")
    }

    // MARK: - Gestures

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                gestureZoom = value.magnification
            }
            .onEnded { _ in
                let combined = zoom * gestureZoom
                gestureZoom = 1
                withAnimation(.spring(duration: 0.25)) {
                    zoom = min(max(combined, 1), maxZoom)
                    if zoom <= 1.01 {
                        zoom = 1
                        offset = .zero
                    }
                }
            }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if isZoomed {
                    gestureOffset = value.translation
                } else if value.translation.height > 0 {
                    dismissDrag = value.translation.height
                }
            }
            .onEnded { value in
                if isZoomed {
                    offset.width += value.translation.width
                    offset.height += value.translation.height
                    gestureOffset = .zero
                } else if value.translation.height > dismissThreshold {
                    dismiss()
                } else {
                    withAnimation(.spring(duration: 0.25)) { dismissDrag = 0 }
                }
            }
    }

    private func toggleZoom() {
        withAnimation(.spring(duration: 0.25)) {
            if isZoomed {
                zoom = 1
                offset = .zero
            } else {
                zoom = doubleTapZoom
            }
        }
    }
}

// MARK: - Row & Tile Gestures

extension View {
    /// Single tap opens the row's usual destination; double tap previews the photo.
    ///
    /// The double-tap recognizer is attached only when there is a photo to
    /// preview. That is deliberate: an attached recognizer makes SwiftUI hold
    /// every single tap back to see whether a second one lands, so rows without
    /// a photo would pay a delay for a gesture that does nothing.
    @ViewBuilder
    func itemTapGestures(
        previewEnabled: Bool,
        onPreview: @escaping () -> Void,
        onOpen: @escaping () -> Void
    ) -> some View {
        if previewEnabled {
            self
                .onTapGesture(count: 2, perform: onPreview)
                .onTapGesture(perform: onOpen)
        } else {
            self.onTapGesture(perform: onOpen)
        }
    }
}
```

- [ ] **Step 2: Build**

Run: `xcodebuild -project MyStuff.xcodeproj -scheme MyStuff -destination 'generic/platform=iOS Simulator' -configuration Debug build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add MyStuff/Views/PhotoPreviewViewer.swift
git commit -m "feat: full-screen zoomable photo viewer"
```

---

### Task 3: Give gallery tiles an optional double-tap

The callback is optional and defaults to `nil` so the three call sites keep compiling until each is wired in Tasks 4–6. A tile only attaches the double-tap recognizer when it has a photo AND a handler — that is what keeps photo-less tiles tapping instantly.

**Files:**
- Modify: `MyStuff/Views/ItemGalleryGrid.swift`

**Interfaces:**
- Consumes: `PhotoKind` from Task 1; `View.itemTapGestures(previewEnabled:onPreview:onOpen:)` from Task 2.
- Produces: `onDoubleTap: ((Item) -> Void)? = nil` on both `ItemGalleryGrid` initializers, positioned after `onAddPhoto`.

- [ ] **Step 1: Add the property and thread it through both initializers**

Add to the stored properties of `ItemGalleryGrid`, immediately after `let onAddPhoto: (Item) -> Void`:

```swift
    let onDoubleTap: ((Item) -> Void)?
```

In the designated initializer, add the parameter after `onAddPhoto` and assign it:

```swift
    init(
        items: [Item],
        kind: PhotoKind,
        columns: Int = 2,
        onTap: @escaping (Item) -> Void,
        onAddPhoto: @escaping (Item) -> Void,
        onDoubleTap: ((Item) -> Void)? = nil,
        @ViewBuilder tileMenu: @escaping (Item) -> TileMenu
    ) {
        self.items = items
        self.kind = kind
        self.columns = columns
        self.onTap = onTap
        self.onAddPhoto = onAddPhoto
        self.onDoubleTap = onDoubleTap
        self.tileMenu = tileMenu
    }
```

Make the same two additions to the `extension ItemGalleryGrid where TileMenu == EmptyView` initializer (which sets `self.tileMenu = nil`).

- [ ] **Step 2: Pass it to the tile**

In `ItemGalleryGrid.tile(_:)`, update the `GalleryTile` construction:

```swift
        let base = GalleryTile(
            item: item,
            kind: kind,
            onTap: onTap,
            onAddPhoto: onAddPhoto,
            onDoubleTap: onDoubleTap
        )
```

And add the matching stored property to `GalleryTile`, after `let onAddPhoto: (Item) -> Void`:

```swift
    let onDoubleTap: ((Item) -> Void)?
```

- [ ] **Step 3: Move the tap handling out of `tileBody` and onto the shared modifier**

Delete this trailing modifier from the end of `tileBody` (keep the `.contentShape` line immediately above it):

```swift
            .onTapGesture {
                if hasPhoto {
                    onTap(item)
                } else {
                    onAddPhoto(item)
                }
            }
```

Then replace `GalleryTile.body` with:

```swift
    var body: some View {
        tileBody
            .itemTapGestures(
                previewEnabled: hasPhoto && onDoubleTap != nil,
                onPreview: { onDoubleTap?(item) },
                onOpen: {
                    if hasPhoto {
                        onTap(item)
                    } else {
                        onAddPhoto(item)
                    }
                }
            )
    }
```

- [ ] **Step 4: Build**

Run: `xcodebuild -project MyStuff.xcodeproj -scheme MyStuff -destination 'generic/platform=iOS Simulator' -configuration Debug build`
Expected: `** BUILD SUCCEEDED **`. The three existing call sites and the `#Preview` at the bottom of the file compile untouched, because `onDoubleTap` defaults to `nil`.

- [ ] **Step 5: Commit**

```bash
git add MyStuff/Views/ItemGalleryGrid.swift
git commit -m "feat: optional double-tap callback on gallery tiles"
```

---

### Task 4: Wire the Items tab

Items previews the **item** photo. The inner name `Button` goes away so the whole row can carry a double-tap.

**Files:**
- Modify: `MyStuff/Views/ItemsView.swift:124-127` (sheet → cover), `:165-209` (list rows), `:213-230` (gallery), `:358-392` (delete sheet)

**Interfaces:**
- Consumes: `PhotoPreviewViewer(item:kind:viewModel:)` and `View.itemTapGestures(previewEnabled:onPreview:onOpen:)` from Task 2; `onDoubleTap` from Task 3.
- Produces: nothing consumed by later tasks.

- [ ] **Step 1: Swap the preview sheet for the full-screen cover**

Replace lines 124-127:

```swift
            .sheet(item: $previewItem) { item in
                ItemPhotoPreviewSheet(item: item, viewModel: viewModel)
                    .presentationDetents([.medium, .large])
            }
```

with:

```swift
            .fullScreenCover(item: $previewItem) { item in
                PhotoPreviewViewer(item: item, kind: .item, viewModel: viewModel)
            }
```

- [ ] **Step 2: Rewrite the list row with gestures instead of a Button**

Replace the whole `itemsList` computed property (lines 165-209) with these three members:

```swift
    private var itemsList: some View {
        List {
            ForEach(viewModel.filteredItems) { item in
                itemRow(item)
            }
        }
    }

    private func itemRow(_ item: Item) -> some View {
        let liveItem = viewModel.items.first(where: { $0.id == item.id }) ?? item
        return itemRowBody(item)
            .itemTapGestures(
                previewEnabled: liveItem.hasItemPhoto,
                onPreview: { previewItem = liveItem },
                onOpen: { editingItem = item }
            )
    }

    private func itemRowBody(_ item: Item) -> some View {
        HStack(spacing: 12) {
            itemPhotoCircle(item)
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(.body)
                        .foregroundStyle(.primary)
                    if let notes = item.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                if !item.pairedTags.isEmpty {
                    NFCBadge(iconOnly: true)
                }
                categoryBadge(for: item)
                locationBadge(for: item)
                sharedBadge(for: item)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .accessibilityAddTraits(.isButton)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                Task { await viewModel.deleteItem(item) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .contextMenu {
            itemMenuItems(item)
        }
    }
```

The nested `HStack` is kept deliberately: it preserves the original spacing between the text block and the trailing badges. `itemPhotoCircle` keeps its own single-tap handlers, and being an inner gesture it wins over the row's within its own bounds.

- [ ] **Step 3: Wire the gallery**

In `itemsGallery`, add an `onDoubleTap` argument after `onAddPhoto`:

```swift
                onDoubleTap: { previewItem = $0 },
```

- [ ] **Step 4: Delete `ItemPhotoPreviewSheet`**

Remove the `// MARK: - Item Photo Preview Sheet` comment and the entire `struct ItemPhotoPreviewSheet` (lines 358-392). Nothing else references it.

- [ ] **Step 5: Build**

Run: `xcodebuild -project MyStuff.xcodeproj -scheme MyStuff -destination 'generic/platform=iOS Simulator' -configuration Debug build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add MyStuff/Views/ItemsView.swift
git commit -m "feat: double-tap photo preview in Items tab"
```

---

### Task 5: Wire the Home tab

Home previews the **location** photo. Note the trailing move-arrow stays a `Button` — it is its own tap target and must keep swallowing its own taps.

**Files:**
- Modify: `MyStuff/Views/HomeView.swift:133-136` (sheet → cover), `:505-518` (gallery), `:544-587` (item row), `:791-853` (delete sheet)

**Interfaces:**
- Consumes: `PhotoPreviewViewer(item:kind:viewModel:)` and `View.itemTapGestures(previewEnabled:onPreview:onOpen:)` from Task 2; `onDoubleTap` from Task 3.
- Produces: nothing consumed by later tasks.

- [ ] **Step 1: Swap the preview sheet for the full-screen cover**

Replace lines 133-136:

```swift
            .sheet(item: $previewItem) { item in
                LocationPhotoPreviewSheet(item: item, viewModel: viewModel)
                    .presentationDetents([.medium, .large])
            }
```

with:

```swift
            .fullScreenCover(item: $previewItem) { item in
                PhotoPreviewViewer(item: item, kind: .location, viewModel: viewModel)
            }
```

- [ ] **Step 2: Rewrite the item row with gestures instead of a Button**

Replace the whole `itemRow(_:tag:)` function (lines 544-587) with:

```swift
    private func itemRow(_ item: Item, tag: some View) -> some View {
        itemRowBody(item, tag: tag)
            .itemTapGestures(
                previewEnabled: item.hasLocationPhoto,
                onPreview: { previewItem = item },
                onOpen: { detailItem = item }
            )
    }

    private func itemRowBody(_ item: Item, tag: some View) -> some View {
        HStack {
            itemThumbnail(item)

            VStack(alignment: .leading) {
                Text(item.name)
                    .font(.subheadline)
                if let notes = item.notes {
                    Text(notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let changedAt = item.locationChangedAt {
                    Text("Stored \(changedAt, format: .relative(presentation: .named))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()
            if !item.pairedTags.isEmpty {
                NFCBadge(iconOnly: true)
            }
            tag

            Button {
                selectedItem = item
            } label: {
                Image(systemName: "arrow.right.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityAddTraits(.isButton)
        .contextMenu {
            itemMenuItems(item)
        }
    }
```

- [ ] **Step 3: Wire the gallery**

In `galleryGrid(_:)`, add an `onDoubleTap` argument after `onAddPhoto`:

```swift
            onDoubleTap: { previewItem = $0 },
```

- [ ] **Step 4: Delete `LocationPhotoPreviewSheet`**

Remove the `// MARK: - Location Photo Preview Sheet` comment and the entire `struct LocationPhotoPreviewSheet`, including its `storageInfo(for:)` helper (lines 791-853). Keep the `#Preview` block at the very bottom of the file. Nothing else references the struct.

This deliberately drops two details the old sheet showed and the new viewer does not: the full location breadcrumb (`viewModel.locationPath`) and the absolute "Stored <date>" line. Both remain available on `ItemDetailSheet`, and the row itself still shows a relative "Stored …" caption.

- [ ] **Step 5: Build**

Run: `xcodebuild -project MyStuff.xcodeproj -scheme MyStuff -destination 'generic/platform=iOS Simulator' -configuration Debug build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add MyStuff/Views/HomeView.swift
git commit -m "feat: double-tap photo preview in Home tab"
```

---

### Task 6: Wire Location detail

Location detail previews the **location** photo. Its list rows are plain text with no thumbnail, so this view needs a new `previewItem` state of its own.

**Files:**
- Modify: `MyStuff/Views/LocationDetailView.swift:13` (state), `:99-125` (items section), plus one new cover modifier

**Interfaces:**
- Consumes: `PhotoPreviewViewer(item:kind:viewModel:)` and `View.itemTapGestures(previewEnabled:onPreview:onOpen:)` from Task 2; `onDoubleTap` from Task 3.
- Produces: nothing.

- [ ] **Step 1: Add the state**

Directly below `@State private var detailItem: Item?` (line 13), add:

```swift
    @State private var previewItem: Item?
```

- [ ] **Step 2: Wire the gallery**

In the `ItemGalleryGrid` inside `Section("Items")`, add an `onDoubleTap` argument after the `onAddPhoto` closure:

```swift
                        onDoubleTap: { previewItem = $0 },
```

- [ ] **Step 3: Rewrite the list rows with gestures instead of a Button**

Replace the `else` branch's `ForEach` (the one building `Button { detailItem = item } label: { Text(item.name)... }`) with:

```swift
                    ForEach(directItems) { item in
                        itemRow(item)
                    }
```

Then add these two functions next to the view's other private helpers, above `itemMenuItems`:

```swift
    private func itemRow(_ item: Item) -> some View {
        itemRowBody(item)
            .itemTapGestures(
                previewEnabled: item.hasLocationPhoto,
                onPreview: { previewItem = item },
                onOpen: { detailItem = item }
            )
    }

    private func itemRowBody(_ item: Item) -> some View {
        Text(item.name)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .accessibilityAddTraits(.isButton)
            .contextMenu { itemMenuItems(item) }
    }
```

- [ ] **Step 4: Present the viewer**

Add this modifier alongside the view's other `.sheet(...)` modifiers, immediately after `.sheet(isPresented: $showingQR) { ... }`:

```swift
        .fullScreenCover(item: $previewItem) { item in
            PhotoPreviewViewer(item: item, kind: .location, viewModel: viewModel)
        }
```

- [ ] **Step 5: Build**

Run: `xcodebuild -project MyStuff.xcodeproj -scheme MyStuff -destination 'generic/platform=iOS Simulator' -configuration Debug build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add MyStuff/Views/LocationDetailView.swift
git commit -m "feat: double-tap photo preview in location detail"
```

---

### Task 7: Manual verification pass

No test target exists, so this is the acceptance gate. Run it in the simulator with the app's normal Firebase data, or switch `StuffViewModel`'s service line to `MockDataService()` if the signed-in account has no photos — revert that line before committing.

**Files:**
- Modify: none (verification only). Any defect found is fixed in the task that owns the file.

**Interfaces:**
- Consumes: everything from Tasks 1–6.
- Produces: a pass/fail report.

- [ ] **Step 1: Launch the app in the simulator**

Boot a simulator and install a Debug build. Sign in and confirm the item list is populated with at least one item that has an item photo, one that has a location photo, and one with neither.

- [ ] **Step 2: Verify double-tap on all six surfaces**

For each, double-tap an item that has the relevant photo and confirm the viewer opens showing that surface's photo:

1. Home, list mode → location photo
2. Home, gallery mode → location photo
3. Items, list mode → item photo
4. Items, gallery mode → item photo
5. Location detail (Locations tab → a location), list mode → location photo
6. Location detail, gallery mode → location photo

- [ ] **Step 3: Verify the viewer's interactions**

In an open viewer: pinch to zoom in and back out (it should snap to fit below 1×), double-tap to toggle 1× ↔ 2.5×, drag to pan while zoomed, drag down at 1× to dismiss (backdrop fades; a short drag snaps back), and tap the ✕ to close. Confirm the item name and the location badge appear top-left and fade out while zoomed.

- [ ] **Step 4: Verify single tap still works everywhere**

On each of the six surfaces, single-tap a row/tile and confirm the old destination still opens: `ItemDetailSheet` from Home and Location detail, `ItemFormSheet` from Items. Also confirm a row's photo thumbnail still opens the viewer on one tap, and a placeholder thumbnail still opens the photo picker.

- [ ] **Step 5: Verify photo-less rows**

Double-tap an item with no relevant photo on each surface. Expected: no viewer; behaves exactly as a single tap, with no perceptible delay before the sheet appears.

- [ ] **Step 6: Verify the failed-load state**

Pick an item whose photo exists only remotely (a photo added on another device, or delete the app's local container and relaunch without letting it re-download). Turn on airplane mode in the simulator's host or disable network, then open the viewer for it. Expected: the "Photo Unavailable" state with the "Check your connection." description — not an endless spinner.

- [ ] **Step 7: Verify swipe actions and context menus**

On the rewritten rows: swipe left on an Items row to reveal Delete, and long-press rows on all three views to confirm the context menu still appears with its full set of actions.

- [ ] **Step 8: Report**

Report each numbered check as pass or fail with what was observed. Do not claim the feature is complete unless every check passed — a failure goes back to the owning task.

---

## Self-Review

**Spec coverage:**

| Spec section | Task |
|---|---|
| Six surfaces table | 4, 5, 6 |
| Photo follows surface | 4 (`.item`), 5 & 6 (`.location`) |
| Missing photo → no recognizer | 3 (tiles), 4/5/6 (rows) |
| Gesture layer, `.accessibilityAddTraits(.isButton)` | 4, 5, 6 |
| Prerequisite `PhotoKind` lift | 1 |
| `PhotoPreviewViewer` + zoom/pan/dismiss/badge | 2 |
| Old sheets deleted | 4 (`ItemPhotoPreviewSheet`), 5 (`LocationPhotoPreviewSheet`) |
| `onResolve` + three-state rendering | 1 (property), 2 (consumption) |
| Thumbnail tap preserved | 4, 5 (`itemPhotoCircle` / `itemThumbnail` untouched) |
| Verification list | 7 |

**Type consistency:** `PhotoKind` (Task 1) is the type used in Tasks 2 and 3. `onResolve: ((Bool) -> Void)?` (Task 1) matches `onResolve: { didResolve = $0 }` (Task 2). `onDoubleTap: ((Item) -> Void)?` (Task 3) matches `onDoubleTap: { previewItem = $0 }` (Tasks 4–6). `PhotoPreviewViewer(item:kind:viewModel:)` (Task 2) matches all three call sites.

**Known consequence, recorded in Task 5:** deleting `LocationPhotoPreviewSheet` drops the location breadcrumb and the absolute stored-date line it displayed; both remain on `ItemDetailSheet`.
