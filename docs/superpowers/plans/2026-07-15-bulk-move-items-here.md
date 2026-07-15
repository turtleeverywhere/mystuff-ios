# Bulk Move Items Into Location Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "Move items here" action to a location's detail sheet that opens a grouped, searchable, multi-select picker and moves all chosen items into that location at once.

**Architecture:** A new self-contained `MoveItemsHereSheet` view (segmented Location/Category grouping + search + multi-select `List`, chrome mirroring the existing `MoveItemSheet`) is presented from a button row in `LocationDetailView`'s Items section. It performs the move through a new `StuffViewModel.moveItems(_:toLocationId:)` bulk API and silently auto-shares the destination with moved items' collaborators.

**Tech Stack:** Swift 6, SwiftUI, iOS 26 target. `@Observable` `StuffViewModel`, `@Bindable` in views. No test target — verification is `xcodebuild` compile + manual simulator checks.

## Global Constraints

- iOS 26.0, Swift 6.0, bundle ID `com.flyingturtle.mystuff`.
- No test target exists — do not add one; verify with the build command below and manual steps.
- Follow existing conventions: `@Observable`/`@Bindable`, `ultraThinMaterial`/Liquid Glass, `HapticManager` on CRUD, Firestore `Codable` mapping.
- Build verification command (run from repo root `/Users/lars/coding_projects/mystuff-ios`):
  ```
  xcodebuild -project MyStuff.xcodeproj -scheme MyStuff -destination 'generic/platform=iOS Simulator' -configuration Debug build
  ```
  Success marker: `** BUILD SUCCEEDED **` in the last ~60 lines. Takes ~30-90s.
- Spec: `docs/superpowers/specs/2026-07-15-bulk-move-items-here-design.md`.

---

## File Structure

- **Modify** `MyStuff/ViewModels/StuffViewModel.swift` — add `moveItems(_:toLocationId:)` bulk-move method next to `moveItem` (~line 568).
- **Create** `MyStuff/Views/MoveItemsHereSheet.swift` — the grouped, searchable, multi-select picker view.
- **Modify** `MyStuff/Views/LocationDetailView.swift` — add the "Move items here" button row in the Items section + presenting state and `.sheet`.

Task order: viewModel API first (Task 1, no UI dependency), then the sheet (Task 2, consumes the API), then wire the entry point (Task 3, consumes the sheet).

---

### Task 1: Bulk-move viewModel API

**Files:**
- Modify: `MyStuff/ViewModels/StuffViewModel.swift` (insert after `moveItem`, currently ending ~line 582)

**Interfaces:**
- Consumes: existing `service.updateItem(_:) async throws`, `items` array, `HapticManager.success()`, `errorMessage`.
- Produces: `func moveItems(_ items: [Item], toLocationId: String?) async` — moves each item's `locationId` to `toLocationId`, stamps `locationChangedAt`/`updatedAt`, persists per item, updates local `items`, fires exactly one success haptic.

- [ ] **Step 1: Read the current `moveItem` for the exact surrounding pattern**

Read `MyStuff/ViewModels/StuffViewModel.swift` around lines 568–582 to confirm `moveItem`'s shape (field names `locationId`, `locationChangedAt`, `updatedAt`; `service.updateItem`; `HapticManager.success()`; `errorMessage`). These must match verbatim.

- [ ] **Step 2: Add the `moveItems` method**

Insert immediately after the closing brace of `moveItem` (after ~line 582):

```swift
/// Move several items to the same location in one pass. Unlike calling `moveItem`
/// per item, this fires a single success haptic for the whole batch.
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
        HapticManager.success()
    } catch {
        errorMessage = error.localizedDescription
    }
}
```

- [ ] **Step 3: Build to verify it compiles**

Run the build verification command from the Global Constraints.
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add MyStuff/ViewModels/StuffViewModel.swift
git commit -m "feat: add StuffViewModel.moveItems bulk-move API"
```

---

### Task 2: MoveItemsHereSheet view

**Files:**
- Create: `MyStuff/Views/MoveItemsHereSheet.swift`

**Interfaces:**
- Consumes: `StuffViewModel` — `.items`, `.locations`, `.categories`, `flattenedLocationTree()` returning `[(location: Location, depth: Int)]`, `canManageSharing(of: Location)`, `canManageSharing(of: Item)`, `sharedMembers(of: Item)`, `membersMissing(from:forItemMembers:)`, `addMembers(_:toLocation:)`, and the Task 1 `moveItems(_:toLocationId:)`. `Location` has `id`, `name`, `emoji?`. `Item` has `id`, `name`, `notes?`, `locationId?`, `categoryId?`. `GroupingMode` is a nested enum on `StuffViewModel` (`.location`, `.category`).
- Produces: `struct MoveItemsHereSheet: View` with `init(destination: Location, viewModel: StuffViewModel)`.

- [ ] **Step 1: Confirm the property/type names this view relies on**

Verify against current code (they are used verbatim below):
- `Item.categoryId` exists (used by HomeView filters).
- `viewModel.flattenedLocationTree()` returns elements with `.location` and `.depth`.
- `viewModel.categories` is `[Category]` with `id`, `name`.
- `MoveItemSheet` in `HomeView.swift` for the sizing/toolbar pattern to mirror.

- [ ] **Step 2: Create the file with the full view**

Create `MyStuff/Views/MoveItemsHereSheet.swift`:

```swift
import SwiftUI

/// Multi-select picker to bulk-move items into `destination`.
/// Grouped by current location or category, searchable, mirroring the Home screen.
struct MoveItemsHereSheet: View {
    let destination: Location
    let viewModel: StuffViewModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var selected: Set<String> = []
    @State private var grouping: StuffViewModel.GroupingMode = .location
    @State private var searchText = ""

    /// All items except those already directly in the destination, filtered by search.
    private var candidates: [Item] {
        var result = viewModel.items.filter { $0.locationId != destination.id }
        if !searchText.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(searchText)
                || ($0.notes?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
        return result
    }

    /// True when nothing is movable regardless of search (drives the empty state).
    private var hasAnyCandidate: Bool {
        viewModel.items.contains { $0.locationId != destination.id }
    }

    var body: some View {
        // Detents are ignored in regular width (iPad form sheet); use page sizing there.
        if horizontalSizeClass == .regular {
            content.presentationSizing(.page)
        } else {
            content.presentationDetents([.medium, .large])
        }
    }

    private var content: some View {
        NavigationStack {
            Group {
                if !hasAnyCandidate {
                    ContentUnavailableView("Nothing to move here", systemImage: "tray")
                } else {
                    List {
                        Picker("Group by", selection: $grouping) {
                            ForEach(StuffViewModel.GroupingMode.allCases, id: \.self) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)

                        switch grouping {
                        case .location: locationSections
                        case .category: categorySections
                        }
                    }
                }
            }
            .navigationTitle("Move Items")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search items")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Move (\(selected.count))") { confirmMove() }
                        .disabled(selected.isEmpty)
                }
            }
        }
    }

    // MARK: - Grouped sections

    @ViewBuilder
    private var locationSections: some View {
        ForEach(viewModel.flattenedLocationTree(), id: \.location.id) { entry in
            let items = candidates.filter { $0.locationId == entry.location.id }
            if !items.isEmpty {
                Section((entry.location.emoji ?? "📍") + " " + entry.location.name) {
                    ForEach(items) { item in itemRow(item) }
                }
            }
        }
        let unassigned = candidates.filter { $0.locationId == nil }
        if !unassigned.isEmpty {
            Section("Unassigned") {
                ForEach(unassigned) { item in itemRow(item) }
            }
        }
    }

    @ViewBuilder
    private var categorySections: some View {
        ForEach(viewModel.categories) { category in
            let items = candidates.filter { $0.categoryId == category.id }
            if !items.isEmpty {
                Section(category.name) {
                    ForEach(items) { item in itemRow(item) }
                }
            }
        }
        let uncategorized = candidates.filter { $0.categoryId == nil }
        if !uncategorized.isEmpty {
            Section("Uncategorized") {
                ForEach(uncategorized) { item in itemRow(item) }
            }
        }
    }

    // MARK: - Row

    private func itemRow(_ item: Item) -> some View {
        Button {
            if selected.contains(item.id) {
                selected.remove(item.id)
            } else {
                selected.insert(item.id)
            }
        } label: {
            HStack {
                Text(item.name).foregroundStyle(.primary)
                Spacer()
                if selected.contains(item.id) {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Confirm

    private func confirmMove() {
        let dest = viewModel.locations.first { $0.id == destination.id } ?? destination
        let selectedItems = viewModel.items.filter { selected.contains($0.id) }
        Task {
            // Auto-share the destination with moved items' collaborators (owner-managed only).
            if viewModel.canManageSharing(of: dest) {
                var missing: [String] = []
                for item in selectedItems where viewModel.canManageSharing(of: item) {
                    missing.append(contentsOf: viewModel.membersMissing(
                        from: dest,
                        forItemMembers: viewModel.sharedMembers(of: item)
                    ))
                }
                let union = Array(Set(missing))
                if !union.isEmpty {
                    await viewModel.addMembers(union, toLocation: dest)
                }
            }
            await viewModel.moveItems(selectedItems, toLocationId: dest.id)
            dismiss()
        }
    }
}
```

- [ ] **Step 3: Build to verify it compiles**

Run the build verification command.
Expected: `** BUILD SUCCEEDED **`. If `GroupingMode` is not `CaseIterable`/`String`-raw-valued as assumed, check its definition (`StuffViewModel.swift` ~line 23) and adjust the `Picker` `ForEach`/`Text(mode.rawValue)` to match (HomeView's grouping picker at `HomeView.swift:174` is the reference — copy its exact usage).

- [ ] **Step 4: Commit**

```bash
git add MyStuff/Views/MoveItemsHereSheet.swift
git commit -m "feat: add MoveItemsHereSheet bulk item mover"
```

---

### Task 3: Wire entry point in LocationDetailView

**Files:**
- Modify: `MyStuff/Views/LocationDetailView.swift` (Items section ~lines 61–73; add `@State` ~line 12; add `.sheet` alongside existing sheets ~line 104)

**Interfaces:**
- Consumes: `MoveItemsHereSheet(destination:viewModel:)` from Task 2; existing `live` computed property and `viewModel`.
- Produces: user-visible "Move items here" button + presented sheet.

- [ ] **Step 1: Add presenting state**

In `LocationDetailView`, next to the other `@State` declarations (after `@State private var showShareSheet = false`, ~line 12):

```swift
@State private var showingMoveItemsHere = false
```

- [ ] **Step 2: Add the button row at the top of the Items section**

In `Section("Items")` (~line 61), insert the button as the first child, before the `if directItems.isEmpty` check:

```swift
Section("Items") {
    Button {
        showingMoveItemsHere = true
    } label: {
        Label("Move items here", systemImage: "tray.and.arrow.down")
    }

    if directItems.isEmpty {
        Text("No items here yet.").foregroundStyle(.secondary)
    } else {
        ForEach(directItems) { item in
            Button {
                detailItem = item
            } label: {
                Text(item.name).foregroundStyle(.primary)
            }
        }
    }
}
```

- [ ] **Step 3: Add the sheet presentation**

Alongside the other `.sheet` modifiers (e.g. after the `.sheet(item: $detailItem)` block ~line 106):

```swift
.sheet(isPresented: $showingMoveItemsHere) {
    MoveItemsHereSheet(destination: live, viewModel: viewModel)
}
```

- [ ] **Step 4: Build to verify it compiles**

Run the build verification command.
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add MyStuff/Views/LocationDetailView.swift
git commit -m "feat: add 'Move items here' entry point to location detail"
```

---

### Task 4: Manual verification

**Files:** none (manual simulator run).

- [ ] **Step 1: Run the app and exercise the flow**

Build/run in the simulator and verify against the spec's testing section:

1. Open a location's detail → tap **Move items here** → picker lists all items except those already directly in this location.
2. Toggle `Location` / `Category` grouping → both group candidates correctly; location headers show `emoji name`, category headers show category name; "Unassigned"/"Uncategorized" sections appear when relevant.
3. Type in the search field → filters by name and notes across all sections.
4. Select several items across different sections → `Move (N)` count updates → tap it → all selected items now appear under this location, the header item count updates, one haptic fires.
5. Move a shared item into a location whose members don't include the item's collaborators → destination's members gain those collaborators (verify via the share sheet), no dialog shown.
6. Open a location where no items are movable → picker shows the "Nothing to move here" empty state.
7. On iPad the sheet is page-sized; on iPhone it uses medium/large detents.

- [ ] **Step 2: Note any deviations**

If any check fails, fix in the relevant task's file and re-commit before considering the feature done.

---

## Self-Review

- **Spec coverage:** Entry point (Task 3), `MoveItemsHereSheet` grouping/search/multi-select/empty-state/sizing (Task 2), `moveItems` bulk API (Task 1), auto-share reconciliation (Task 2 `confirmMove`), manual testing (Task 4). All spec sections mapped.
- **Placeholder scan:** none — every code step is complete.
- **Type consistency:** `moveItems(_:toLocationId:)` signature identical in Tasks 1 & 2; `MoveItemsHereSheet(destination:viewModel:)` identical in Tasks 2 & 3; field names (`locationId`, `categoryId`, `emoji`, `name`) and viewModel methods used as verified in the spec.
```