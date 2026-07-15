# Bulk Move Items Into Location — Design

## Goal

In a location's detail sheet (`LocationDetailView`, which lists a location's items and
sub-locations), add a **Move items here** action. It opens a multi-select picker of items
elsewhere, grouped by current location or category with a search bar (mirroring the Home
screen), letting the user select any number of items and move them all into this location
at once. Primary use case: filling/refilling a box or room without moving items one at a time.

## Scope

- **In:** "Move items here" button row in the `Items` section of `LocationDetailView`.
- **In:** New `MoveItemsHereSheet` — grouped, searchable, multi-select item picker.
- **In:** New `StuffViewModel.moveItems(_:toLocationId:)` bulk-move API (one haptic, one state update).
- **In:** Auto-share the destination with moved items' collaborators so nobody loses visibility.
- **Out (YAGNI):** per-item photo-update prompt after moving (the single-item mover does this;
  bulk would mean N dialogs); select-all/section-toggle affordances; drag-and-drop; undo.

## UI

### Entry point (`LocationDetailView.swift`)

At the top of the existing `Section("Items")`, above the item rows, add:

```swift
Button {
    showingMoveItemsHere = true
} label: {
    Label("Move items here", systemImage: "tray.and.arrow.down")
}
```

New `@State private var showingMoveItemsHere = false` on `LocationDetailView`, and:

```swift
.sheet(isPresented: $showingMoveItemsHere) {
    MoveItemsHereSheet(destination: live, viewModel: viewModel)
}
```

The button shows whether or not `directItems` is empty (an empty location is a common
move-target).

### MoveItemsHereSheet (new file `MyStuff/Views/MoveItemsHereSheet.swift`)

Self-contained: it owns the move and its own dismissal (no `onMove` closure needed).

- **Props:** `let destination: Location`, `let viewModel: StuffViewModel`.
- **State:**
  - `@State private var selected: Set<String> = []` — selected item ids.
  - `@State private var grouping: GroupingMode = .location` — local, does not touch
    `viewModel.selectedGrouping`.
  - `@State private var searchText = ""`.
  - `@Environment(\.dismiss)`, `@Environment(\.horizontalSizeClass)`.
- **Candidates:** `viewModel.items.filter { $0.locationId != destination.id }` — all items
  except those already directly in the destination (moving those here is a no-op). Items in
  the destination's sub-locations are still shown so they can be pulled up. Then filtered by
  `searchText` against name and notes (case-insensitive), matching HomeView's search.
- **Sizing:** body switches on `horizontalSizeClass` exactly like `MoveItemSheet`:
  `.presentationSizing(.page)` in regular width (iPad form sheet), otherwise
  `.presentationDetents([.medium, .large])` (list can be long → allow large).
- **Body:** `NavigationStack` →
  - Segmented `Picker` (`Location` / `Category`) bound to `grouping`, `.pickerStyle(.segmented)`.
  - `List`:
    - **By location:** one `Section` per `viewModel.flattenedLocationTree()` entry whose
      candidate items are non-empty; header = `emoji + " " + name` (emoji fallback `📍`),
      **name + emoji only, no path/indent**. Items in the section = candidates whose
      `locationId == entry.location.id`. Plus a final "Unassigned" section for candidates with
      `locationId == nil`.
    - **By category:** one `Section` per `viewModel.categories` whose candidate items are
      non-empty; header = category name. Items = candidates with `categoryId == category.id`.
      Plus an "Uncategorized" section for candidates with `categoryId == nil`.
    - **Row:** a `Button` toggling `selected` for that item id; label = item name, with a
      trailing `checkmark` (`.tint(.accentColor)`) shown when selected.
  - `.searchable(text: $searchText, prompt: "Search items")`.
  - When there are **no candidates at all** (nothing movable), show
    `ContentUnavailableView("Nothing to move here", systemImage: "tray")` instead of the list.
  - `.navigationTitle("Move Items")`, `.navigationBarTitleDisplayMode(.inline)`.
  - **Toolbar:** `.cancellationAction` → `Cancel` (dismiss); `.confirmationAction` →
    `Button("Move (\(selected.count))")`, `.disabled(selected.isEmpty)`, runs the confirm action.

## Behavior / data flow

Confirm action (auto-share destination, no per-item dialogs):

1. `let dest = viewModel.locations.first { $0.id == destination.id } ?? destination` (live copy).
2. `let selectedItems = viewModel.items.filter { selected.contains($0.id) }`.
3. **Auto-share reconciliation** — only if `viewModel.canManageSharing(of: dest)`:
   - Build the union of missing members: for each `it` in `selectedItems` where
     `viewModel.canManageSharing(of: it)`, collect
     `viewModel.membersMissing(from: dest, forItemMembers: viewModel.sharedMembers(of: it))`.
   - If the deduped union is non-empty, one call:
     `await viewModel.addMembers(union, toLocation: dest)`.
   - This mirrors the single-item mover's "Share destination too" branch, applied silently in
     bulk so collaborators keep visibility of moved items' location.
4. `await viewModel.moveItems(selectedItems, toLocationId: dest.id)`.
5. `dismiss()`.

Items shared *with* the user (`canManageSharing == false`) are still moved but excluded from
the reconciliation math, matching `MoveItemSheet.selectMove`.

## New viewModel API

Add to `StuffViewModel` (near `moveItem`):

```swift
func moveItems(_ items: [Item], toLocationId: String?) async {
    guard !items.isEmpty else { return }
    let ids = Set(items.map(\.id))
    do {
        for id in ids {
            guard var updated = self.items.first(where: { $0.id == id }) else { continue }
            updated.locationId = toLocationId
            updated.locationChangedAt = .now
            updated.updatedAt = .now
            try await service.updateItem(updated)
            if let index = self.items.firstIndex(where: { $0.id == id }) {
                self.items[index] = updated
            }
        }
        HapticManager.success()   // one haptic for the whole batch
    } catch {
        errorMessage = error.localizedDescription
    }
}
```

Rationale for a new method rather than looping `moveItem`: `moveItem` fires a success haptic
per call, so a bulk move of N items would buzz N times. `moveItems` does one state pass and
one haptic. No batch write API exists on `DataService`; per-item `service.updateItem` in a
loop matches `deleteLocation`'s existing pattern.

## Testing

No test target exists in this project. Manual verification:

1. Open a location's detail → **Move items here** → picker lists all items except those
   already directly in this location.
2. Toggle `Location` / `Category` grouping; both group candidates correctly with name + emoji
   (location) / category-name headers; "Unassigned"/"Uncategorized" sections appear when relevant.
3. Search filters by name and notes across all sections.
4. Select several items across different sections → `Move (N)` reflects the count → confirm →
   all selected items now appear under this location, the header item count updates, one haptic.
5. Move a shared item into a location whose members don't include the item's collaborators →
   destination's members gain those collaborators (auto-share), no dialog shown.
6. A location with no movable candidates shows the `ContentUnavailableView` empty state.
7. iPad: sheet renders page-sized; iPhone: medium/large detents.
```