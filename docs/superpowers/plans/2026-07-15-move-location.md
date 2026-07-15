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

## Self-Review

- **Spec coverage:** Context-menu "Move" item (Task 1 Step 2) ✓; MoveLocationSheet with Root row + excluding-tree targets (Step 4) ✓; accent tint for current parent/root (Step 4) ✓; update via `updateLocation` + expand new parent (Step 3) ✓; any-visible-location movable — no owner guard added, `.contextMenu` applies to every row ✓; size-class detents (Step 4) ✓; no share reconciliation / no QR (excluded, not implemented) ✓.
- **Placeholders:** none — full code shown for every code step.
- **Type consistency:** `onMove: (String?) -> Void`, `select(parentId:)`, `movingLocation`, `MoveLocationSheet(location:viewModel:onMove:)`, `flattenedLocationTree(excluding:)` used consistently across steps. `Location.parentId` is a settable `var` (Location.swift:7), so `updated.parentId = newParentId` is valid.
