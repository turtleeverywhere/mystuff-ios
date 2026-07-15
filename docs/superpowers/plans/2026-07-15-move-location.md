# Move Location Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "Move" action to the Locations-tab long-press menu that reparents a location under another location or back to the top level (root).

**Architecture:** A new `MoveLocationSheet` (List-based tree picker) is added to `LocationsView.swift`, mirroring the existing `MoveItemSheet`. A "Move" context-menu item sets a `@State` selection that presents the sheet. Selection calls `StuffViewModel.updateLocation(_:)` with a changed `parentId`; no new viewModel API is needed.

**Tech Stack:** Swift 6, SwiftUI, iOS 26. `@Observable` viewModel via `@Bindable`.

## Global Constraints

- Target iOS 26.0, Swift 6.0, bundle ID `com.flyingturtle.mystuff`.
- No test target exists — verification is `xcodebuild build` + manual checks, not unit tests.
- Follow existing patterns: `MoveItemSheet` (HomeView.swift:660) is the reference for sheet structure, size-class detents, and the `onMove` closure convention.
- Cycle safety comes from `viewModel.flattenedLocationTree(excluding:)`, which excludes the passed id and all its descendants — do not add a redundant guard.

---

### Task 1: Add MoveLocationSheet and wire the Move context-menu action

**Files:**
- Modify: `MyStuff/Views/LocationsView.swift` (add `@State`, context-menu button, `.sheet`, and new `MoveLocationSheet` struct)

**Interfaces:**
- Consumes: `StuffViewModel.updateLocation(_ location: Location) async` (persists changed `parentId`, updates local `locations`, fires haptic); `StuffViewModel.flattenedLocationTree(excluding: String?) -> [(location: Location, depth: Int)]`; `StuffViewModel.locations: [Location]`.
- Produces: `MoveLocationSheet(location: Location, viewModel: StuffViewModel, onMove: (String?) -> Void)` — calls `onMove(newParentId)` where `newParentId` is `nil` for root, then dismisses itself.

- [ ] **Step 1: Add the selection state**

In `LocationsView`, add below the existing `@State private var addingSublocationParent: Location?` (line 10):

```swift
    @State private var movingLocation: Location?
```

- [ ] **Step 2: Add the "Move" context-menu item**

In `locationsList`, extend the existing `.contextMenu` (currently only "Add Sub-location", ~line 184) to:

```swift
                .contextMenu {
                    Button {
                        addingSublocationParent = entry.location
                    } label: {
                        Label("Add Sub-location", systemImage: "plus")
                    }
                    Button {
                        movingLocation = entry.location
                    } label: {
                        Label("Move", systemImage: "folder")
                    }
                }
```

- [ ] **Step 3: Present the sheet**

Add after the existing `.sheet(item: $addingSublocationParent) { ... }` block (ends ~line 67), before the `.alert("Delete Location?"...)`:

```swift
            .sheet(item: $movingLocation) { location in
                MoveLocationSheet(
                    location: location,
                    viewModel: viewModel,
                    onMove: { newParentId in
                        Task {
                            var updated = viewModel.locations.first(where: { $0.id == location.id }) ?? location
                            updated.parentId = newParentId
                            await viewModel.updateLocation(updated)
                        }
                        if let newParentId { expandedIds.insert(newParentId) }
                    }
                )
            }
```

- [ ] **Step 4: Add the MoveLocationSheet struct**

Append to `LocationsView.swift`, after the `LocationFormSheet` struct's closing brace and before the `#Preview` block (~line 301):

```swift
// MARK: - Move Location Sheet

struct MoveLocationSheet: View {
    let location: Location
    let viewModel: StuffViewModel
    let onMove: (String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        // Detents are ignored in regular width (iPad form sheet); use page sizing there instead.
        if horizontalSizeClass == .regular {
            content.presentationSizing(.page)
        } else {
            content.presentationDetents([.medium])
        }
    }

    private func select(parentId: String?) {
        onMove(parentId)
        dismiss()
    }

    private var content: some View {
        NavigationStack {
            List {
                Section("Move \"\(location.name)\" to…") {
                    Button {
                        select(parentId: nil)
                    } label: {
                        Label("Root (top level)", systemImage: "house")
                    }
                    .tint(location.parentId == nil ? .accentColor : .primary)

                    ForEach(viewModel.flattenedLocationTree(excluding: location.id), id: \.location.id) { entry in
                        Button {
                            select(parentId: entry.location.id)
                        } label: {
                            Label {
                                Text(entry.location.name)
                            } icon: {
                                Text(entry.location.emoji ?? "📍")
                            }
                        }
                        .tint(entry.location.id == location.parentId ? .accentColor : .primary)
                        .padding(.leading, CGFloat(entry.depth) * 20)
                    }
                }
            }
            .navigationTitle("Move Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
```

- [ ] **Step 5: Build to verify it compiles**

Run the project's build command (see `reference_build_command` memory / CLAUDE.md), e.g.:

```bash
xcodebuild -project MyStuff.xcodeproj -scheme MyStuff -destination 'platform=iOS Simulator,name=iPhone 16' build
```

Expected: `BUILD SUCCEEDED`. No errors about `movingLocation`, `MoveLocationSheet`, or `flattenedLocationTree`.

- [ ] **Step 6: Manual verification**

Launch in the simulator and confirm:
1. Long-press a **root** location → menu shows **Add Sub-location** and **Move** → tap Move → pick another location → it becomes a sub-location, the new parent auto-expands, item-count badges update.
2. Long-press a **sub-location** → Move → **Root (top level)** → it returns to top level.
3. In the Move sheet, the location itself and all its descendants are **absent** from the target list.
4. The current parent row (or "Root" when already root) shows the accent tint.
5. A location **shared with you** can be moved.
6. iPad: sheet is page-sized; iPhone: medium detent.

- [ ] **Step 7: Commit**

```bash
git add MyStuff/Views/LocationsView.swift
git commit -m "feat: move locations between parents / to root from long-press menu

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: Share propagation on move (whole subtree + items)

Moving a location under a *shared* parent currently fails silently (Firestore rejects the child whose parent is shared but the child isn't; the failure is hidden by the known errorMessage bug). This task adds a `moveLocation` viewModel method that reparents AND additively propagates the destination's members across the moved subtree, then routes the sheet through it.

**Files:**
- Modify: `MyStuff/ViewModels/StuffViewModel.swift` (add `moveLocation(_:toParentId:)`)
- Modify: `MyStuff/Views/LocationsView.swift` (route `onMove` through `moveLocation`; add section footer)

**Interfaces:**
- Consumes: `service.updateLocation(_:) async throws`, `service.updateItem(_:) async throws`; `allDescendantIds(of: String) -> Set<String>`; `canManageSharing(of: Location) -> Bool`, `canManageSharing(of: Item) -> Bool`; `Location.members`, `Item.members`, both entities' settable `memberIds: [String]?`; `locations`, `items`, `HapticManager.success()`, `errorMessage`.
- Produces: `StuffViewModel.moveLocation(_ location: Location, toParentId newParentId: String?) async`.

- [ ] **Step 1: Add `moveLocation` to StuffViewModel**

Insert immediately AFTER the existing `updateLocation(_:)` method (which ends at the `}` on the line before `func deleteLocation`, ~line 608) in `MyStuff/ViewModels/StuffViewModel.swift`:

```swift
    /// Reparent `location` to `newParentId` (nil = root). When the destination is shared,
    /// additively propagate the destination's members across the moved subtree — the moved
    /// location, its descendant locations, and every item within — but only for entities the
    /// current user owns. The moved location's membership is written together with its new
    /// parentId so the parent/child membership stays consistent (Firestore rules reject a
    /// non-shared child under a shared parent). Additive only: moving out never removes members.
    func moveLocation(_ location: Location, toParentId newParentId: String?) async {
        guard var moved = locations.first(where: { $0.id == location.id }) else { return }

        let destMembers: [String]
        if let newParentId, let dest = locations.first(where: { $0.id == newParentId }) {
            destMembers = dest.members
        } else {
            destMembers = []
        }

        moved.parentId = newParentId
        if !destMembers.isEmpty, canManageSharing(of: moved) {
            moved.memberIds = Array(Set(moved.members + destMembers))
        }

        do {
            // Reparent (+ membership) of the moved location in a single write.
            try await service.updateLocation(moved)
            if let i = locations.firstIndex(where: { $0.id == moved.id }) { locations[i] = moved }

            if !destMembers.isEmpty {
                let subtreeIds = allDescendantIds(of: location.id).union([location.id])
                let destSet = Set(destMembers)

                // Descendant locations (skip the moved location itself, already written).
                for locId in subtreeIds where locId != moved.id {
                    guard let li = locations.firstIndex(where: { $0.id == locId }),
                          canManageSharing(of: locations[li]) else { continue }
                    let current = locations[li].members
                    guard !destSet.isSubset(of: Set(current)) else { continue }
                    var u = locations[li]
                    u.memberIds = Array(Set(current + destMembers))
                    try await service.updateLocation(u)
                    locations[li] = u
                }

                // Items anywhere in the moved subtree.
                for ii in items.indices where subtreeIds.contains(items[ii].locationId ?? "") {
                    guard canManageSharing(of: items[ii]) else { continue }
                    let current = items[ii].members
                    guard !destSet.isSubset(of: Set(current)) else { continue }
                    var u = items[ii]
                    u.memberIds = Array(Set(current + destMembers))
                    u.updatedAt = .now
                    try await service.updateItem(u)
                    items[ii] = u
                }
            }
            HapticManager.success()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
```

- [ ] **Step 2: Route the sheet's `onMove` through `moveLocation`**

In `MyStuff/Views/LocationsView.swift`, replace the existing `.sheet(item: $movingLocation)` closure body (currently reparents via `updateLocation`, ~lines 69-82):

```swift
            .sheet(item: $movingLocation) { location in
                MoveLocationSheet(
                    location: location,
                    viewModel: viewModel,
                    onMove: { newParentId in
                        Task {
                            var updated = viewModel.locations.first(where: { $0.id == location.id }) ?? location
                            updated.parentId = newParentId
                            await viewModel.updateLocation(updated)
                        }
                        if let newParentId { expandedIds.insert(newParentId) }
                    }
                )
            }
```

with:

```swift
            .sheet(item: $movingLocation) { location in
                MoveLocationSheet(
                    location: location,
                    viewModel: viewModel,
                    onMove: { newParentId in
                        Task { await viewModel.moveLocation(location, toParentId: newParentId) }
                        if let newParentId { expandedIds.insert(newParentId) }
                    }
                )
            }
```

- [ ] **Step 3: Add the section footer to MoveLocationSheet**

In `MyStuff/Views/LocationsView.swift`, in `MoveLocationSheet.content`, attach a footer to the existing `Section`. Replace the section header line:

```swift
                Section("Move \"\(location.name)\" to…") {
```

with a header+footer form — change the section opener to:

```swift
                Section {
```

and move the title into a `header:`/`footer:` trailing form by replacing the section's closing `}` (the one closing `Section { … }`) so the section reads:

```swift
                Section {
                    Button {
                        select(parentId: nil)
                    } label: {
                        Label("Root (top level)", systemImage: "house")
                    }
                    .tint(location.parentId == nil ? .accentColor : .primary)

                    ForEach(viewModel.flattenedLocationTree(excluding: location.id), id: \.location.id) { entry in
                        Button {
                            select(parentId: entry.location.id)
                        } label: {
                            Label {
                                Text(entry.location.name)
                            } icon: {
                                Text(entry.location.emoji ?? "📍")
                            }
                        }
                        .tint(entry.location.id == location.parentId ? .accentColor : .primary)
                        .padding(.leading, CGFloat(entry.depth) * 20)
                    }
                } header: {
                    Text("Move \"\(location.name)\" to…")
                } footer: {
                    Text("Moving into a shared location shares this location and its contents with the same people.")
                }
```

- [ ] **Step 4: Build to verify it compiles**

Run:

```bash
xcodebuild -project MyStuff.xcodeproj -scheme MyStuff -destination 'platform=iOS Simulator,name=iPhone 16' build
```

(If `iPhone 16` is unavailable, run `xcrun simctl list devices available` and substitute an available iPhone simulator.) Expected: `** BUILD SUCCEEDED **`. No errors about `moveLocation`, `allDescendantIds`, or `canManageSharing`.

- [ ] **Step 5: Manual verification** (deferred to human — requires a friend account / shared data)

1. Move a private location (containing items + a sub-location with its own items) under a location shared with a friend → move succeeds; the moved location, its sub-location, and all their items gain the friend as member (verify from the friend's account if possible).
2. Move that now-shared location back to root → it stays shared (membership unchanged).
3. Move a location under a private parent or to root → no membership changes.
4. Re-confirm Task 1 checks still hold (tree excludes self+descendants, accent tint, sizing).

- [ ] **Step 6: Commit**

```bash
git add MyStuff/ViewModels/StuffViewModel.swift MyStuff/Views/LocationsView.swift
git commit -m "feat: propagate sharing when moving a location under a shared parent

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Self-Review

- **Spec coverage:** Context-menu "Move" item (Task 1 Step 2) ✓; MoveLocationSheet with Root row + excluding-tree targets (Step 4) ✓; accent tint for current parent/root (Step 4) ✓; update via `updateLocation` + expand new parent (Step 3) ✓; any-visible-location movable — no owner guard added, `.contextMenu` applies to every row ✓; size-class detents (Step 4) ✓; no share reconciliation / no QR (excluded, not implemented) ✓.
- **Placeholders:** none — full code shown for every code step.
- **Type consistency:** `onMove: (String?) -> Void`, `select(parentId:)`, `movingLocation`, `MoveLocationSheet(location:viewModel:onMove:)`, `flattenedLocationTree(excluding:)` used consistently across steps. `Location.parentId` is a settable `var` (Location.swift:7), so `updated.parentId = newParentId` is valid.

### Task 2 (share propagation)

- **Spec coverage:** `moveLocation(_:toParentId:)` reparents + additively propagates dest members to moved location (same write), descendant locations, and subtree items, owner-managed only, skipping no-op unions, root = no change, additive-only ✓; sheet routed through `moveLocation` ✓; section footer added ✓; picker unchanged (shared locations already listed) ✓.
- **Placeholders:** none — full method and full edits shown.
- **Type consistency:** `moveLocation(_ location: Location, toParentId newParentId: String?)`; uses `allDescendantIds(of:) -> Set<String>` (defined, StuffViewModel.swift:79-ish, returns a Set — `.union(...)` valid), `canManageSharing(of: Location)` / `(of: Item)` (both exist, lines 728-729), `members` computed convenience + settable `memberIds` on both models. `Item.updatedAt` is settable (used by existing `moveItem`). Membership union is order-insensitive since `ownerId` is separate.
