# Item Home Location ("Misplaced" tracking) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let every item declare the location it is *supposed* to live in, surface items that have drifted away from it, and offer one-tap and bulk "put back".

**Architecture:** One new optional field on `Item` (`homeLocationId`) drives a derived `isMisplaced` predicate. `StuffViewModel` owns the authoritative version of that predicate (it also checks the home location still exists) plus list accessors and a `putBackItems` mutation. The Home tab's inline filter bar is extracted into a shared `ItemFilterBar` + `ItemFilter` value type, gains a "Misplaced" chip, and is reused by the Items tab. `LocationDetailView` gains a "Missing from here" section.

**Tech Stack:** Swift 6, SwiftUI (iOS 26), `@Observable` / `@Bindable`, Firestore via `Codable` (`setData(from:merge:true)`), no third-party additions.

**Spec:** `docs/superpowers/specs/2026-08-06-item-home-location-design.md`

## Global Constraints

- **There is no test target in this project.** Do not create one. Verification for every task is: a clean build, plus the manual simulator checks written into that task. Never claim a task passes without pasting the build result.
- Build command, run from `/Users/lars/coding_projects/mystuff-ios`:
  ```bash
  xcodebuild -project MyStuff.xcodeproj -scheme MyStuff -destination 'generic/platform=iOS Simulator' -configuration Debug build 2>&1 | tail -30
  ```
  Success marker: `** BUILD SUCCEEDED **`. Takes ~30–90s.
- New `.swift` files placed under `MyStuff/` join the target automatically — the project uses `PBXFileSystemSynchronizedRootGroup`. **Never hand-edit `MyStuff.xcodeproj/project.pbxproj`.**
- Misplaced matching is **exact**. An item homed at `Living Room` sitting in `Living Room > Shelf A` is misplaced. An item with a home and `locationId == nil` is misplaced.
- An item with `homeLocationId == nil` is never misplaced.
- All UI reads `viewModel.isMisplaced(item)`, never `item.isMisplaced` directly. Reason: Firestore `merge: true` writes omit nil, so clearing `homeLocationId` does not remove the field remotely; the view-model predicate additionally requires the home location to still exist, which makes a stale pointer harmless.
- Exact user-facing copy (do not paraphrase): `Supposed location`, `Same as current location`, `Misplaced`, `Put Back`, `Put All Back`, `Missing from here`, `Put all back here`, `No items match these filters`.
- Follow existing house style: `@Observable` view model passed as `@Bindable`/`let`, `.ultraThinMaterial` capsules for badges, `HapticManager` on mutations, comments only where the *why* is non-obvious.
- Commit after every task with a `feat:`/`refactor:` prefix and this trailer:
  ```
  Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
  ```
- The working tree already has unrelated uncommitted changes in `HomeView.swift`, `ItemDetailSheet.swift`, `ItemsView.swift`, `MoveItemsHereSheet.swift`, `NFCScanButton.swift`. **Stage only the files each task names** — never `git add -A`.

---

## File Structure

| File | Responsibility | Task |
|---|---|---|
| `MyStuff/Models/Item.swift` | `homeLocationId` field + raw `isMisplaced` predicate | 1 |
| `MyStuff/ViewModels/StuffViewModel.swift` | `isMisplaced(_:)`, `misplacedItems`, `missingItems(for:)`, `putBackItems(_:)`, `addItem` param, `deleteLocation` cleanup | 1 |
| `MyStuff/Views/ItemsView.swift` | `ItemFormResult.homeLocationId`, form picker, add/edit call sites, Items-tab filter bar, badges, Put Back menu | 2, 3, 5 |
| `MyStuff/Views/LocationDetailView.swift` | add-item call site, badges, Put Back menu, "Missing from here" section | 2, 3, 6 |
| `MyStuff/Views/MisplacedBadge.swift` | **new** — the ⚠️ capsule | 3 |
| `MyStuff/Views/ItemGalleryGrid.swift` | badge on gallery tiles | 3 |
| `MyStuff/Views/ItemDetailSheet.swift` | home location chip in `infoSection` | 3 |
| `MyStuff/Views/ItemFilterBar.swift` | **new** — `ItemFilter` value type + shared filter bar view | 4 |
| `MyStuff/Views/HomeView.swift` | adopt `ItemFilterBar`, badges, Put Back menu | 3, 4 |

---

## Task 1: Data model and view-model logic

**Files:**
- Modify: `MyStuff/Models/Item.swift`
- Modify: `MyStuff/ViewModels/StuffViewModel.swift:401` (`addItem`), `:846` (`deleteLocation`), and append a new section after `moveItems` (~`:720`)

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `Item.homeLocationId: String?` (stored, defaults to `nil` in the memberwise init)
  - `Item.isMisplaced: Bool` (raw predicate — internal use only)
  - `StuffViewModel.isMisplaced(_ item: Item) -> Bool` (**the predicate all UI uses**)
  - `StuffViewModel.misplacedItems: [Item]`
  - `StuffViewModel.missingItems(for location: Location) -> [Item]`
  - `StuffViewModel.putBackItems(_ items: [Item]) async`
  - `StuffViewModel.addItem(id:name:notes:locationId:categoryId:homeLocationId:) async`

- [ ] **Step 1: Add the stored field to `Item`**

In `MyStuff/Models/Item.swift`, directly below `var locationId: String?`:

```swift
    /// Location this item is *supposed* to live in. nil = no expected place, so the
    /// item can never be misplaced. Optional so legacy docs decode cleanly — same
    /// idiom as ownerId/memberIds.
    var homeLocationId: String?
```

Add the matching init parameter directly after `locationId: String? = nil,`:

```swift
        homeLocationId: String? = nil,
```

and the matching assignment directly after `self.locationId = locationId`:

```swift
        self.homeLocationId = homeLocationId
```

- [ ] **Step 2: Add the raw predicate to `Item`**

In the same file, directly above the existing `var members: [String] {` computed property:

```swift
    /// True when this item has a home location and is not currently in it.
    /// Matching is exact: sitting in a *child* of the home location still counts as
    /// misplaced, and a nil `locationId` counts as misplaced. Views must not read
    /// this directly — go through `StuffViewModel.isMisplaced(_:)`, which also
    /// verifies the home location still exists.
    var isMisplaced: Bool {
        guard let homeLocationId else { return false }
        return locationId != homeLocationId
    }
```

- [ ] **Step 3: Add the view-model predicate and accessors**

In `MyStuff/ViewModels/StuffViewModel.swift`, immediately after the `moveItems(_:toLocationId:)` function, add:

```swift
    // MARK: - Misplaced Items

    /// Authoritative misplaced check. Adds an existence guard on top of
    /// `Item.isMisplaced`: a `merge: true` write omits nil, so clearing
    /// `homeLocationId` never removes the field in Firestore. Requiring the home
    /// location to still exist makes a stale pointer harmless.
    func isMisplaced(_ item: Item) -> Bool {
        guard item.isMisplaced, let homeId = item.homeLocationId else { return false }
        return locations.contains { $0.id == homeId }
    }

    /// Every item that is away from its home location.
    var misplacedItems: [Item] {
        items.filter { isMisplaced($0) }
    }

    /// Items whose home is `location` but which are not currently there.
    func missingItems(for location: Location) -> [Item] {
        items.filter { $0.homeLocationId == location.id && $0.locationId != location.id }
    }

    /// Send each item back to its own home location. Unlike `moveItems`, destinations
    /// differ per item, so this resolves each one individually and fires a single
    /// success haptic for the whole batch. Items whose home no longer exists are skipped.
    func putBackItems(_ items: [Item]) async {
        let targets = items.filter { isMisplaced($0) }
        guard !targets.isEmpty else { return }
        do {
            for target in targets {
                guard var updated = self.items.first(where: { $0.id == target.id }) else { continue }
                updated.locationId = updated.homeLocationId
                updated.locationChangedAt = .now
                updated.updatedAt = .now
                try await service.updateItem(updated)
                if let index = self.items.firstIndex(where: { $0.id == updated.id }) {
                    self.items[index] = updated
                }
            }
            HapticManager.success()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
```

- [ ] **Step 4: Thread `homeLocationId` through `addItem`**

Replace the existing `addItem` signature and `Item(...)` construction (currently lines 401–403) with:

```swift
    func addItem(id: String = UUID().uuidString, name: String, notes: String?, locationId: String?, categoryId: String?, homeLocationId: String? = nil) async {
        let owner = service.currentUserId
        let item = Item(id: id, name: name, notes: notes, locationId: locationId, homeLocationId: homeLocationId, categoryId: categoryId, locationChangedAt: locationId != nil ? .now : nil, ownerId: owner, memberIds: [owner])
```

The parameter is defaulted so the existing call sites keep compiling; Task 2 updates them to pass a real value.

> Note the argument order inside `Item(...)`: `homeLocationId` sits between `locationId` and `categoryId`, matching the declaration order from Step 1. Swift enforces this for memberwise inits.

- [ ] **Step 5: Clear dangling home pointers on location delete**

In `deleteLocation`, replace the existing "Unassign items that were at this location" loop (currently lines 855–860) with:

```swift
            // Unassign items that were at this location, and drop home pointers aimed
            // at it. One combined pass so an item that was both here and homed here
            // takes a single write.
            for i in items.indices where items[i].locationId == location.id || items[i].homeLocationId == location.id {
                if items[i].locationId == location.id { items[i].locationId = nil }
                if items[i].homeLocationId == location.id { items[i].homeLocationId = nil }
                items[i].updatedAt = .now
                try await service.updateItem(items[i])
            }
```

- [ ] **Step 6: Build**

Run:
```bash
xcodebuild -project MyStuff.xcodeproj -scheme MyStuff -destination 'generic/platform=iOS Simulator' -configuration Debug build 2>&1 | tail -30
```
Expected: `** BUILD SUCCEEDED **`. Nothing in the UI changes yet — this task is model + logic only.

- [ ] **Step 7: Commit**

```bash
git add MyStuff/Models/Item.swift MyStuff/ViewModels/StuffViewModel.swift
git commit -m "$(cat <<'EOF'
feat: add item home location and misplaced predicate

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Set the supposed location from the item form

**Files:**
- Modify: `MyStuff/Views/ItemsView.swift` (`ItemFormResult` ~`:372`, `ItemFormSheet` state/init ~`:390-445`, Location section ~`:548`, Save button ~`:643`, add call site `:64`, edit call site `:92`)
- Modify: `MyStuff/Views/LocationDetailView.swift:186` (add call site)

**Interfaces:**
- Consumes: `Item.homeLocationId`, `StuffViewModel.addItem(..., homeLocationId:)` from Task 1.
- Produces: `ItemFormResult.homeLocationId: String?` — every `ItemFormSheet` `onSave` closure receives it.

- [ ] **Step 1: Add the field to `ItemFormResult`**

In `MyStuff/Views/ItemsView.swift`, in `struct ItemFormResult`, directly after `let locationId: String?`:

```swift
    let homeLocationId: String?
```

- [ ] **Step 2: Add form state and its sentinel**

In `ItemFormSheet`, directly after `@State private var selectedLocationId: String`:

```swift
    @State private var selectedHomeLocationId: String
```

Directly after the existing `private let uncategorizedSentinel = "__uncategorized__"`:

```swift
    private let noHomeSentinel = "__nohome__"
```

In `init`, directly after the `_selectedLocationId = ...` line:

```swift
        _selectedHomeLocationId = State(initialValue: item?.homeLocationId ?? "__nohome__")
```

> The literal is repeated rather than referencing `noHomeSentinel` because `init` runs before `self` is available — the same reason the existing code writes `"__unassigned__"` inline.

- [ ] **Step 3: Add the picker and the copy button**

In the `Section("Location")` block, directly after the closing brace of the `HStack` that holds the existing location `Picker` and QR button, insert:

```swift
                    Picker("Supposed location", selection: $selectedHomeLocationId) {
                        Text("None").tag(noHomeSentinel)
                        ForEach(viewModel.flattenedLocationTree(), id: \.location.id) { entry in
                            Text(String(repeating: "  ", count: entry.depth) + (entry.location.emoji ?? "📍") + " " + entry.location.name)
                                .tag(entry.location.id)
                        }
                    }

                    Button("Same as current location") {
                        selectedHomeLocationId = selectedLocationId
                    }
                    .disabled(selectedLocationId == unassignedSentinel || selectedHomeLocationId == selectedLocationId)
```

- [ ] **Step 4: Pass it back on Save**

In the Save button action, directly after the existing `let locationId = ...` line:

```swift
                        let homeLocationId = selectedHomeLocationId == noHomeSentinel ? nil : selectedHomeLocationId
```

and inside the `ItemFormResult(...)` construction, directly after `locationId: locationId,`:

```swift
                            homeLocationId: homeLocationId,
```

- [ ] **Step 5: Update the "add" call site in `ItemsView`**

In the `.sheet(isPresented: $showingAddSheet)` closure, extend the `addItem` call:

```swift
                            await viewModel.addItem(
                                id: result.id,
                                name: result.name,
                                notes: result.notes,
                                locationId: result.locationId,
                                categoryId: result.categoryId,
                                homeLocationId: result.homeLocationId
                            )
```

- [ ] **Step 6: Update the "edit" call site in `ItemsView`**

In the `.sheet(item: $editingItem)` closure, directly after `updated.locationId = result.locationId`:

```swift
                        updated.homeLocationId = result.homeLocationId
```

- [ ] **Step 7: Update the add call site in `LocationDetailView`**

In `MyStuff/Views/LocationDetailView.swift`, in the `.sheet(isPresented: $showingAddItem)` closure, extend the `addItem` call the same way:

```swift
                        await viewModel.addItem(
                            id: result.id,
                            name: result.name,
                            notes: result.notes,
                            locationId: result.locationId,
                            categoryId: result.categoryId,
                            homeLocationId: result.homeLocationId
                        )
```

- [ ] **Step 8: Build**

Run:
```bash
xcodebuild -project MyStuff.xcodeproj -scheme MyStuff -destination 'generic/platform=iOS Simulator' -configuration Debug build 2>&1 | tail -30
```
Expected: `** BUILD SUCCEEDED **`. If it fails with "missing argument for parameter 'homeLocationId'", a third `ItemFormResult(...)` construction exists — search with `grep -rn "ItemFormResult(" MyStuff/` and fix it.

- [ ] **Step 9: Manual check in the simulator**

Launch the app, then:
1. Items tab → **+** → the Location section shows a **Supposed location** picker defaulting to **None** and a **Same as current location** button.
2. Pick a location, tap **Same as current location** → the supposed-location picker follows it and the button greys out.
3. Save, reopen the item for edit → the supposed location persisted.
4. With Location set to **Unassigned**, the button is disabled.

- [ ] **Step 10: Commit**

```bash
git add MyStuff/Views/ItemsView.swift MyStuff/Views/LocationDetailView.swift
git commit -m "$(cat <<'EOF'
feat: set an item's supposed location from the item form

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Misplaced badge and single-item "Put Back"

**Files:**
- Create: `MyStuff/Views/MisplacedBadge.swift`
- Modify: `MyStuff/Views/HomeView.swift` (`itemRowBody` ~`:574`, `itemMenuItems` ~`:523`)
- Modify: `MyStuff/Views/ItemsView.swift` (`itemRowBody` ~`:197`, `itemMenuItems` ~`:245`)
- Modify: `MyStuff/Views/LocationDetailView.swift` (`itemRowBody` ~`:256`, `itemMenuItems` ~`:266`)
- Modify: `MyStuff/Views/ItemGalleryGrid.swift` (`tileBody` overlay ~`:130`)
- Modify: `MyStuff/Views/ItemDetailSheet.swift` (`infoSection` ~`:270`)

**Interfaces:**
- Consumes: `StuffViewModel.isMisplaced(_:)`, `StuffViewModel.putBackItems(_:)` from Task 1.
- Produces: `MisplacedBadge(iconOnly: Bool = false)`.

- [ ] **Step 1: Create the badge**

Create `MyStuff/Views/MisplacedBadge.swift`:

```swift
import SwiftUI

/// Small capsule marking an item as away from its supposed location.
struct MisplacedBadge: View {
    var iconOnly: Bool = false

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
            if !iconOnly {
                Text("Misplaced")
                    .font(.caption2)
            }
        }
        .foregroundStyle(.orange)
        .padding(.horizontal, iconOnly ? 6 : 8)
        .padding(.vertical, 3)
        .background(.ultraThinMaterial, in: Capsule())
        .accessibilityLabel("Misplaced")
    }
}
```

- [ ] **Step 2: Show it in the Home row**

In `MyStuff/Views/HomeView.swift`, in `itemRowBody`, directly **above** the existing `if !item.pairedTags.isEmpty {` block:

```swift
            if viewModel.isMisplaced(item) {
                MisplacedBadge(iconOnly: true)
            }
```

- [ ] **Step 3: Show it in the Items row**

In `MyStuff/Views/ItemsView.swift`, in `itemRowBody`, directly **above** the existing `if !item.pairedTags.isEmpty {` block:

```swift
                if viewModel.isMisplaced(item) {
                    MisplacedBadge(iconOnly: true)
                }
```

- [ ] **Step 4: Show it in the Location detail row**

In `MyStuff/Views/LocationDetailView.swift`, replace `itemRowBody` with:

```swift
    private func itemRowBody(_ item: Item) -> some View {
        HStack {
            Text(item.name)
                .foregroundStyle(.primary)
            Spacer()
            if viewModel.isMisplaced(item) {
                MisplacedBadge(iconOnly: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityAddTraits(.isButton)
        .contextMenu { itemMenuItems(item) }
    }
```

- [ ] **Step 5: Show it on gallery tiles**

`ItemGalleryGrid` has no view model, so the flag is injected as a closure. Note this
file declares **two explicit inits** (the generic one and the `TileMenu == EmptyView`
extension) — both need the new parameter, or the second one will not compile.

In `MyStuff/Views/ItemGalleryGrid.swift`:

(a) Add the stored property directly after `let items: [Item]`:

```swift
    /// Per-item misplaced flag. Injected because this grid has no view model.
    let isMisplaced: (Item) -> Bool
```

(b) In **both** inits, add this parameter directly after `items: [Item],`:

```swift
        isMisplaced: @escaping (Item) -> Bool = { _ in false },
```

and in **both** init bodies, add this assignment directly after `self.items = items`:

```swift
        self.isMisplaced = isMisplaced
```

(c) In `tile(_:)`, pass it to the tile — directly after `item: item,`:

```swift
            isMisplaced: isMisplaced(item),
```

(d) In `private struct GalleryTile`, add the stored property directly after `let item: Item`:

```swift
    let isMisplaced: Bool
```

> Placement matters: `GalleryTile` has no explicit init, so its memberwise init
> follows declaration order — which is why (c) passes `isMisplaced:` right after `item:`.

(e) Replace the `.overlay(alignment: .topTrailing)` block in `tileBody` with:

```swift
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 4) {
                    if isMisplaced {
                        MisplacedBadge(iconOnly: true)
                    }
                    if !item.pairedTags.isEmpty {
                        NFCBadge(iconOnly: true)
                    }
                }
                .padding(6)
            }
```

- [ ] **Step 6: Feed the flag from the three grid call sites**

In `MyStuff/Views/HomeView.swift` (`galleryGrid`), `MyStuff/Views/ItemsView.swift` (`itemsGallery`), and `MyStuff/Views/LocationDetailView.swift` (the `ItemGalleryGrid(...)` inside `Section("Items")`), add this argument to each `ItemGalleryGrid(...)` call, directly after the `items:` argument:

```swift
            isMisplaced: { viewModel.isMisplaced($0) },
```

- [ ] **Step 7: Show the home location in `ItemDetailSheet`**

In `MyStuff/Views/ItemDetailSheet.swift`, in `infoSection`, directly after the `if let category = viewModel.category(for: liveItem) { ... }` block and still inside the same `HStack(spacing: 8)`:

```swift
                if viewModel.isMisplaced(liveItem),
                   let home = viewModel.locations.first(where: { $0.id == liveItem.homeLocationId }) {
                    Label {
                        Text("Belongs in \(viewModel.displayPath(for: home))")
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                }
```

- [ ] **Step 8: Add "Put Back" to all three context menus**

Add this block as the **first** entry inside `itemMenuItems(_:)` in each of `HomeView.swift`, `ItemsView.swift`, and `LocationDetailView.swift` (identical in all three — repeat it verbatim):

```swift
        if viewModel.isMisplaced(item) {
            Button {
                Task { await viewModel.putBackItems([item]) }
            } label: {
                Label("Put Back", systemImage: "arrow.uturn.left.circle")
            }
        }
```

- [ ] **Step 9: Build**

Run:
```bash
xcodebuild -project MyStuff.xcodeproj -scheme MyStuff -destination 'generic/platform=iOS Simulator' -configuration Debug build 2>&1 | tail -30
```
Expected: `** BUILD SUCCEEDED **`. If `ItemGalleryGrid` fails with "extra argument 'isMisplaced'", the property added in Step 5 landed on the wrong struct — it belongs on both the grid and its tile subview.

- [ ] **Step 10: Manual check in the simulator**

1. Give an item a supposed location, then move it somewhere else.
2. The ⚠️ badge appears on that item in the Home tab, the Items tab, the location's detail list, and on gallery tiles in all three (toggle gallery mode with the toolbar button).
3. Open the item's detail sheet → an orange "Belongs in …" chip shows the home path.
4. Long-press the item anywhere → **Put Back** appears as the first menu entry; tapping it moves the item home, the badge disappears, and a success haptic fires.
5. Long-press an item with no supposed location → no **Put Back** entry.

- [ ] **Step 11: Commit**

```bash
git add MyStuff/Views/MisplacedBadge.swift MyStuff/Views/HomeView.swift MyStuff/Views/ItemsView.swift MyStuff/Views/LocationDetailView.swift MyStuff/Views/ItemGalleryGrid.swift MyStuff/Views/ItemDetailSheet.swift
git commit -m "$(cat <<'EOF'
feat: misplaced badge and per-item put back

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Extract `ItemFilterBar` and adopt it in the Home tab

**Files:**
- Create: `MyStuff/Views/ItemFilterBar.swift`
- Modify: `MyStuff/Views/HomeView.swift` (state `:18-20`, `homeFilteredItems` `:28-47`, `isFiltering` `:49-51`, `filterBar` `:195-280`, `filterChip` `:282-292`, `mainContent` `:180`)

**Interfaces:**
- Consumes: `StuffViewModel.isMisplaced(_:)`, `putBackItems(_:)` from Task 1; existing `viewModel.allDescendantIds(of:)`, `viewModel.flattenedLocationTree()`, `viewModel.categories`.
- Produces:
  - `ItemFilter` — `categoryIds: Set<String>`, `locationIds: Set<String>`, `misplacedOnly: Bool`, `isActive: Bool`, `activeCount: Int`, `apply(to:searchText:viewModel:) -> [Item]`
  - `ItemFilterBar(filter:isExpanded:viewModel:isFiltering:putBackTargets:onPutAllBack:onClearAll:)`

- [ ] **Step 1: Create the shared filter file**

Create `MyStuff/Views/ItemFilterBar.swift`:

```swift
import SwiftUI

/// The filter selection shared by the Home and Items tabs. A value type so each
/// host view owns its own state; search text stays with the host because the two
/// tabs source it differently.
struct ItemFilter: Equatable {
    var categoryIds: Set<String> = []
    var locationIds: Set<String> = []
    var misplacedOnly = false

    var isActive: Bool {
        !categoryIds.isEmpty || !locationIds.isEmpty || misplacedOnly
    }

    /// Facets currently narrowing the list — drives the count badge in the header.
    var activeCount: Int {
        (categoryIds.isEmpty ? 0 : 1) + (locationIds.isEmpty ? 0 : 1) + (misplacedOnly ? 1 : 0)
    }

    /// Applies every facet plus `searchText`. Selecting a location also matches its
    /// descendants. Pass an empty `searchText` when the caller has already searched.
    func apply(to items: [Item], searchText: String, viewModel: StuffViewModel) -> [Item] {
        var result = items
        if !searchText.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(searchText)
                || ($0.notes?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
        if !categoryIds.isEmpty {
            result = result.filter { categoryIds.contains($0.categoryId ?? "") }
        }
        if !locationIds.isEmpty {
            let allIds = locationIds.reduce(into: locationIds) { acc, id in
                acc.formUnion(viewModel.allDescendantIds(of: id))
            }
            result = result.filter { allIds.contains($0.locationId ?? "") }
        }
        if misplacedOnly {
            result = result.filter { viewModel.isMisplaced($0) }
        }
        return result
    }
}

/// Collapsible chip bar: Categories, Locations, Status, and the action row.
struct ItemFilterBar: View {
    @Binding var filter: ItemFilter
    @Binding var isExpanded: Bool
    let viewModel: StuffViewModel
    /// Host-computed: true when search text *or* any facet is active. Drives "Clear All".
    let isFiltering: Bool
    /// Items "Put All Back" would act on — already narrowed by the host's visible list.
    let putBackTargets: [Item]
    let onPutAllBack: () -> Void
    let onClearAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation { isExpanded.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "line.3.horizontal.decrease")
                    Text("Filters")
                        .font(.subheadline)
                    if filter.activeCount > 0 {
                        Text("\(filter.activeCount)")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor, in: Capsule())
                            .foregroundStyle(.white)
                    }
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            if isExpanded {
                if !viewModel.categories.isEmpty {
                    Text("Categories")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(viewModel.categories) { category in
                                chip(
                                    label: category.name,
                                    isSelected: filter.categoryIds.contains(category.id)
                                ) {
                                    toggle(category.id, in: &filter.categoryIds)
                                }
                            }
                        }
                    }
                }

                if !viewModel.locations.isEmpty {
                    Text("Locations")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(viewModel.flattenedLocationTree(), id: \.location.id) { entry in
                                chip(
                                    label: String(repeating: "  ", count: entry.depth) + (entry.location.emoji ?? "📍") + " " + entry.location.name,
                                    isSelected: filter.locationIds.contains(entry.location.id)
                                ) {
                                    toggle(entry.location.id, in: &filter.locationIds)
                                }
                            }
                        }
                    }
                }

                Text("Status")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                chip(label: "⚠️ Misplaced", isSelected: filter.misplacedOnly) {
                    filter.misplacedOnly.toggle()
                }

                if filter.misplacedOnly && !putBackTargets.isEmpty {
                    Button("Put All Back (\(putBackTargets.count))", action: onPutAllBack)
                        .font(.caption)
                }

                if isFiltering {
                    Button("Clear All", action: onClearAll)
                        .font(.caption)
                }
            }
        }
    }

    private func toggle(_ id: String, in set: inout Set<String>) {
        if set.contains(id) { set.remove(id) } else { set.insert(id) }
    }

    private func chip(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor.opacity(0.2) : .clear, in: Capsule())
                .overlay(Capsule().stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 2: Swap `HomeView`'s filter state**

In `MyStuff/Views/HomeView.swift`, replace these two lines:

```swift
    @State private var filterCategoryIds: Set<String> = []
    @State private var filterLocationIds: Set<String> = []
```

with:

```swift
    @State private var filter = ItemFilter()
```

(`@State private var showFilters = false` stays as is.)

- [ ] **Step 3: Delegate the filtering computed properties**

Replace `homeFilteredItems`, `isFiltering`, and `filtered(_:)` (currently lines 27–56) with:

```swift
    /// Items matching current search + filters
    private var homeFilteredItems: Set<String> {
        Set(visibleItems.map(\.id))
    }

    private var visibleItems: [Item] {
        filter.apply(to: viewModel.items, searchText: homeSearchText, viewModel: viewModel)
    }

    private var isFiltering: Bool {
        !homeSearchText.isEmpty || filter.isActive
    }

    private func filtered(_ items: [Item]) -> [Item] {
        guard isFiltering else { return items }
        return items.filter { homeFilteredItems.contains($0.id) }
    }

    /// What "Put All Back" acts on: everything currently visible that is misplaced.
    private var putBackTargets: [Item] {
        guard filter.misplacedOnly else { return [] }
        return visibleItems
    }
```

- [ ] **Step 4: Replace the inline bar with the shared one**

Delete the entire `// MARK: - Filter Bar` section — both `private var filterBar: some View { ... }` and `private func filterChip(...) -> some View { ... }` (currently lines 193–292).

In `mainContent`, replace the `filterBar` line with:

```swift
                ItemFilterBar(
                    filter: $filter,
                    isExpanded: $showFilters,
                    viewModel: viewModel,
                    isFiltering: isFiltering,
                    putBackTargets: putBackTargets,
                    onPutAllBack: {
                        let targets = putBackTargets
                        Task { await viewModel.putBackItems(targets) }
                    },
                    onClearAll: {
                        filter = ItemFilter()
                        homeSearchText = ""
                    }
                )
```

- [ ] **Step 5: Build**

Run:
```bash
xcodebuild -project MyStuff.xcodeproj -scheme MyStuff -destination 'generic/platform=iOS Simulator' -configuration Debug build 2>&1 | tail -30
```
Expected: `** BUILD SUCCEEDED **`. If it fails with "cannot find 'filterChip' in scope", a leftover call to the deleted helper remains in `HomeView` — remove it.

- [ ] **Step 6: Manual check in the simulator**

1. Home tab → **Filters** expands and collapses; Categories and Locations chips behave exactly as before (including a parent location matching items in its children).
2. A new **Status** row shows a **⚠️ Misplaced** chip; enabling it leaves only misplaced items.
3. The header count badge reads 1 with only the Misplaced chip on, 2 with Misplaced + a category.
4. With Misplaced on, **Put All Back (n)** appears; tapping it returns every listed item to its home and the list empties.
5. **Clear All** resets the chips *and* the search field.

- [ ] **Step 7: Commit**

```bash
git add MyStuff/Views/ItemFilterBar.swift MyStuff/Views/HomeView.swift
git commit -m "$(cat <<'EOF'
refactor: extract shared ItemFilterBar, add misplaced filter

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Filter bar in the Items tab

**Files:**
- Modify: `MyStuff/Views/ItemsView.swift` (state ~`:16`, `body` `:22-34`, `itemsList` `:164-170`, `itemsGallery` `:222-240`, `emptyState` `:354`)

**Interfaces:**
- Consumes: `ItemFilter`, `ItemFilterBar` from Task 4; `StuffViewModel.putBackItems(_:)` from Task 1.
- Produces: nothing consumed by later tasks.

- [ ] **Step 1: Add filter state and the visible-items derivation**

In `MyStuff/Views/ItemsView.swift`, directly after `@State private var isUploading = false`:

```swift
    @State private var filter = ItemFilter()
    @State private var showFilters = false
```

Directly after `private var isGallery: Bool { viewMode == "gallery" }`:

```swift
    /// `viewModel.filteredItems` has already applied the search field, so the
    /// filter runs with an empty query to avoid searching twice.
    private var visibleItems: [Item] {
        filter.apply(to: viewModel.filteredItems, searchText: "", viewModel: viewModel)
    }

    private var isFiltering: Bool {
        !viewModel.searchText.isEmpty || filter.isActive
    }

    private var putBackTargets: [Item] {
        guard filter.misplacedOnly else { return [] }
        return visibleItems
    }

    private var filterBar: some View {
        ItemFilterBar(
            filter: $filter,
            isExpanded: $showFilters,
            viewModel: viewModel,
            isFiltering: isFiltering,
            putBackTargets: putBackTargets,
            onPutAllBack: {
                let targets = putBackTargets
                Task { await viewModel.putBackItems(targets) }
            },
            onClearAll: {
                filter = ItemFilter()
                viewModel.searchText = ""
            }
        )
    }
```

- [ ] **Step 2: Host the bar in the list path**

Replace `itemsList` with:

```swift
    private var itemsList: some View {
        List {
            Section {
                filterBar
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
            }

            if visibleItems.isEmpty {
                noMatchesState
                    .listRowBackground(Color.clear)
            } else {
                ForEach(visibleItems) { item in
                    itemRow(item)
                }
            }
        }
    }
```

- [ ] **Step 3: Host the bar in the gallery path**

Replace `itemsGallery` with:

```swift
    private var itemsGallery: some View {
        ScrollView {
            VStack(spacing: 16) {
                filterBar

                if visibleItems.isEmpty {
                    noMatchesState
                } else {
                    ItemGalleryGrid(
                        items: visibleItems,
                        isMisplaced: { viewModel.isMisplaced($0) },
                        kind: .item,
                        columns: horizontalSizeClass == .regular ? galleryColumns : 2,
                        onTap: { editingItem = $0 },
                        onAddPhoto: { item in
                            photoSourceItem = item
                            showPhotoSource = true
                        },
                        onDoubleTap: { previewItem = $0 },
                        tileMenu: { item in
                            itemMenuItems(item)
                        }
                    )
                }
            }
            .padding()
        }
    }
```

- [ ] **Step 4: Add the filtered-to-empty state**

Directly after the existing `emptyState` property:

```swift
    /// Shown when items exist but none survive the active filters — the full-empty
    /// `emptyState` would wrongly suggest the user has no items at all.
    private var noMatchesState: some View {
        ContentUnavailableView {
            Label("No items match these filters", systemImage: "line.3.horizontal.decrease")
        } description: {
            Text("Try clearing a filter or the search field.")
        }
    }
```

- [ ] **Step 5: Build**

Run:
```bash
xcodebuild -project MyStuff.xcodeproj -scheme MyStuff -destination 'generic/platform=iOS Simulator' -configuration Debug build 2>&1 | tail -30
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Manual check in the simulator**

1. Items tab (list mode) → the **Filters** bar sits above the list and its chips narrow the list.
2. Switch to gallery mode with the toolbar button → the same bar appears above the grid and keeps its selection.
3. Enable **⚠️ Misplaced** → only misplaced items remain; **Put All Back (n)** appears and works.
4. Select a category with no matching items → **No items match these filters** shows and the filter bar stays visible so it can be cleared.
5. Type in the search field, then **Clear All** → both the chips and the search field reset.
6. Delete every item (or start from a fresh account) → the original "No Items Yet" empty state still shows.

- [ ] **Step 7: Commit**

```bash
git add MyStuff/Views/ItemsView.swift
git commit -m "$(cat <<'EOF'
feat: filter bar in the Items tab

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: "Missing from here" section in location detail

**Files:**
- Modify: `MyStuff/Views/LocationDetailView.swift` (computed properties ~`:39`, `body` list ~`:100`)

**Interfaces:**
- Consumes: `StuffViewModel.missingItems(for:)`, `putBackItems(_:)` from Task 1; existing `viewModel.moveItems(_:toLocationId:)`, `canManageSharing(of:)`, `membersMissing(from:forItemMembers:)`, `sharedMembers(of:)`, `addMembers(_:toLocation:)`, `displayPath(for:)`, `location(for:)`.
- Produces: nothing consumed by later tasks.

- [ ] **Step 1: Add the missing-items derivation**

In `MyStuff/Views/LocationDetailView.swift`, directly after the existing `directItems` computed property:

```swift
    /// Items homed here but currently somewhere else.
    private var missingItems: [Item] {
        viewModel.missingItems(for: live)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func currentPlace(of item: Item) -> String {
        guard let location = viewModel.location(for: item) else { return "Unassigned" }
        return viewModel.displayPath(for: location)
    }
```

- [ ] **Step 2: Add the bulk put-back action**

Directly after `currentPlace(of:)`:

```swift
    /// Bulk-returns everything homed here. Mirrors `MoveItemsHereSheet.confirmMove`:
    /// collaborators on the moved items are added to the destination first, or they
    /// would lose sight of items that just moved into a location they can't see.
    private func putAllBackHere() {
        let dest = live
        let targets = missingItems
        Task {
            if viewModel.canManageSharing(of: dest) {
                var missingMembers: [String] = []
                for item in targets where viewModel.canManageSharing(of: item) {
                    missingMembers.append(contentsOf: viewModel.membersMissing(
                        from: dest,
                        forItemMembers: viewModel.sharedMembers(of: item)
                    ))
                }
                let union = Array(Set(missingMembers))
                if !union.isEmpty {
                    await viewModel.addMembers(union, toLocation: dest)
                }
            }
            await viewModel.moveItems(targets, toLocationId: dest.id)
        }
    }
```

- [ ] **Step 3: Add the section**

In `body`, directly **above** the existing `Section("Items") {`:

```swift
            if !missingItems.isEmpty {
                Section {
                    ForEach(missingItems) { item in
                        Button {
                            Task { await viewModel.putBackItems([item]) }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name)
                                        .foregroundStyle(.primary)
                                    Text(currentPlace(of: item))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "arrow.uturn.left.circle")
                                    .foregroundStyle(.tint)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    HStack {
                        Text("Missing from here")
                        Spacer()
                        Button("Put all back here", action: putAllBackHere)
                            .font(.caption)
                            .textCase(nil)
                    }
                }
            }
```

- [ ] **Step 4: Build**

Run:
```bash
xcodebuild -project MyStuff.xcodeproj -scheme MyStuff -destination 'generic/platform=iOS Simulator' -configuration Debug build 2>&1 | tail -30
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Manual check in the simulator**

1. Home two items at location A, then move both to location B.
2. Open A → a **Missing from here** section lists both, each showing "B" as its current place.
3. Tap one row → that item returns to A, leaves the section, and appears in A's **Items** section.
4. Tap **Put all back here** → the remaining item returns and the whole section disappears.
5. Open a location with nothing homed to it → no **Missing from here** section at all.
6. Delete a location that was some item's home → that item stops showing the ⚠️ badge anywhere and no orphan section appears.

- [ ] **Step 6: Commit**

```bash
git add MyStuff/Views/LocationDetailView.swift
git commit -m "$(cat <<'EOF'
feat: missing-from-here section with bulk put back

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Final verification

- [ ] Full build is clean: `xcodebuild ... build 2>&1 | tail -30` shows `** BUILD SUCCEEDED **`
- [ ] `git status` shows no unintended files staged or left behind (the pre-existing unrelated modifications to `ItemDetailSheet.swift`, `MoveItemsHereSheet.swift`, `NFCScanButton.swift` may still be dirty — that is expected unless a task touched them)
- [ ] End-to-end pass in the simulator: create an item with a supposed location → move it away → it appears under the Home Misplaced filter, the Items Misplaced filter, and the home location's "Missing from here" section → put it back from each of those three surfaces in turn
