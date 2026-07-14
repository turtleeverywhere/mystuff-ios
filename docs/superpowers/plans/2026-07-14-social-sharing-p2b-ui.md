# Social Sharing — P2b Sharing UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Surface the P2a sharing engine in the UI — share/unshare items & locations with friends, create already-shared items, badge shared/owned-by-others entities, show orphaned shared sub-locations at root, and prompt the move/share dialog when a shared item lands in a not-shared location.

**Architecture:** All sharing UI reads `viewModel.friends` (a mirror of `SocialViewModel.friends`, synced once in `ContentView`) so no view needs a `SocialViewModel` reference. A reusable `FriendShareSheet` drives share/unshare. The move/share dialog lives inside the shared `MoveItemSheet` (used by both Home and Items tabs), the single choke point for tap-to-move. Owner-only sharing controls are gated via `viewModel.canManageSharing`.

**Tech Stack:** Swift 6 / SwiftUI.

## Global Constraints

- iOS 26.0, Swift 6.0. `@Observable` / `@Bindable`. Uses iOS 26 Liquid Glass / `.ultraThinMaterial`. Haptics via `HapticManager`.
- **No test target exists.** Verification = compile via `xcodebuild` + deferred manual gates. Build command (repo root, ~30–90s, look for `** BUILD SUCCEEDED **`):
  ```
  xcodebuild -project MyStuff.xcodeproj -scheme MyStuff -destination 'generic/platform=iOS Simulator' -configuration Debug build
  ```
- New Swift files go under `MyStuff/` (synchronized folder groups auto-include them).
- P2a engine already provides on `StuffViewModel`: `currentUserId`, `sharedMembers(of:)`, `isShared(_:)`, `isSharedWithMe(_:)`, `membersMissing(from:forItemMembers:)`, `shareItem(_:withFriend:)`, `unshareItem(_:fromFriend:)`, `makeItemPrivate(_:)`, `shareLocation(_:withFriend:)`, `unshareLocation(_:fromFriend:)`, `addMembers(_:toLocation:)`. Reuse these — do NOT reimplement.
- `Friend` model: `{ uid, email, displayName, photoURL?, since }`. `SocialViewModel.friends: [Friend]`.
- Sharing controls are **owner-only**: only show share/unshare/make-private UI for entities where `!viewModel.isSharedWithMe(entity)` (closes a P2a-review follow-up — the engine itself doesn't enforce this).

---

### Task 1: ViewModel/UI plumbing — friends mirror, helpers, orphan roots

**Files:**
- Modify: `MyStuff/ViewModels/StuffViewModel.swift`
- Modify: `MyStuff/Views/ContentView.swift`

**Interfaces:**
- Produces on `StuffViewModel`:
  - `var friends: [Friend]` (observable mirror, set by ContentView)
  - `func friend(forUid uid: String) -> Friend?`
  - `func canManageSharing(of item: Item) -> Bool` / `func canManageSharing(of location: Location) -> Bool`
  - orphan-aware `rootLocations` (a shared child whose parent isn't visible appears at root)

- [ ] **Step 1: Add friends mirror + helpers + orphan roots to `StuffViewModel`**

In `MyStuff/ViewModels/StuffViewModel.swift`, add to the observable state (near `var categories: [Category] = []`):

```swift
    /// Mirror of SocialViewModel.friends, synced by ContentView — lets sharing UI read
    /// friends off the already-threaded StuffViewModel without a SocialViewModel reference.
    var friends: [Friend] = []
```

Add these to the `// MARK: - Sharing` section (after `addMembers(_:toLocation:)`):

```swift
    func friend(forUid uid: String) -> Friend? {
        friends.first { $0.uid == uid }
    }

    /// Sharing controls are owner-only — you can't reshare someone else's entity.
    func canManageSharing(of item: Item) -> Bool { !isSharedWithMe(item) }
    func canManageSharing(of location: Location) -> Bool { !isSharedWithMe(location) }
```

Replace the existing `rootLocations` computed property with an orphan-aware version:

```swift
    var rootLocations: [Location] {
        let visibleIds = Set(locations.map(\.id))
        return locations.filter { loc in
            // Root, or a shared child whose parent isn't visible to me (show it at root).
            guard let pid = loc.parentId else { return true }
            return !visibleIds.contains(pid)
        }
    }
```

- [ ] **Step 2: Sync `social.friends` into `viewModel.friends` in `ContentView`**

In `MyStuff/Views/ContentView.swift`, add an `.onChange` that keeps the mirror current, and seed it in the existing social `.task`. In the social `.task` (added in P2a), set the mirror after load:

```swift
        .task {
            social.onUnfriend = { friendUid in
                await viewModel.unshareEverything(withFriend: friendUid)
            }
            await social.load()
            viewModel.friends = social.friends
        }
        .onChange(of: social.friends) {
            viewModel.friends = social.friends
        }
```

- [ ] **Step 3: Build to verify**

Run: `xcodebuild -project MyStuff.xcodeproj -scheme MyStuff -destination 'generic/platform=iOS Simulator' -configuration Debug build 2>&1 | tail -20`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add MyStuff/ViewModels/StuffViewModel.swift MyStuff/Views/ContentView.swift
git commit -m "feat: friends mirror + sharing helpers + orphan-aware root locations

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: Reusable `FriendShareSheet` + `SharedBadge`

**Files:**
- Create: `MyStuff/Views/FriendShareSheet.swift`
- Create: `MyStuff/Views/SharedBadge.swift`

**Interfaces:**
- Produces:
  - `struct FriendShareSheet: View` — `init(title: String, friends: [Friend], sharedWith: Set<String>, onToggle: @escaping (String, Bool) async -> Void)`.
  - `struct SharedBadge: View` — `init(iconOnly: Bool = false, ownerName: String? = nil)`: a small people-icon capsule; when `ownerName` is set, reads "Shared by <name>"; otherwise "Shared".

- [ ] **Step 1: Create `FriendShareSheet.swift`**

```swift
import SwiftUI

/// Toggle which friends an item or location is shared with. Owner-only (caller gates).
struct FriendShareSheet: View {
    let title: String
    let friends: [Friend]
    let sharedWith: Set<String>
    let onToggle: (String, Bool) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var shared: Set<String>

    init(title: String, friends: [Friend], sharedWith: Set<String>, onToggle: @escaping (String, Bool) async -> Void) {
        self.title = title
        self.friends = friends
        self.sharedWith = sharedWith
        self.onToggle = onToggle
        _shared = State(initialValue: sharedWith)
    }

    var body: some View {
        NavigationStack {
            List {
                if friends.isEmpty {
                    ContentUnavailableView {
                        Label("No Friends Yet", systemImage: "person.2")
                    } description: {
                        Text("Add friends from your account menu to share with them.")
                    }
                } else {
                    Section(title) {
                        ForEach(friends) { friend in
                            Button {
                                let willShare = !shared.contains(friend.uid)
                                if willShare { shared.insert(friend.uid) } else { shared.remove(friend.uid) }
                                Task { await onToggle(friend.uid, willShare) }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(friend.displayName).foregroundStyle(.primary)
                                        Text(friend.email).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if shared.contains(friend.uid) {
                                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                    } else {
                                        Image(systemName: "circle").foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Share")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
```

- [ ] **Step 2: Create `SharedBadge.swift`**

```swift
import SwiftUI

/// Small capsule marking an entity as shared, or (with ownerName) shared *with me* by someone.
struct SharedBadge: View {
    var iconOnly: Bool = false
    var ownerName: String? = nil

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "person.2.fill")
                .font(.caption2)
            if !iconOnly {
                Text(ownerName.map { "Shared by \($0)" } ?? "Shared")
                    .font(.caption2)
            }
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, iconOnly ? 6 : 8)
        .padding(.vertical, 3)
        .background(.ultraThinMaterial, in: Capsule())
    }
}
```

- [ ] **Step 3: Build to verify**

Run: `xcodebuild -project MyStuff.xcodeproj -scheme MyStuff -destination 'generic/platform=iOS Simulator' -configuration Debug build 2>&1 | tail -20`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add MyStuff/Views/FriendShareSheet.swift MyStuff/Views/SharedBadge.swift
git commit -m "feat: reusable FriendShareSheet + SharedBadge components

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: Share entry in ItemDetailSheet and LocationDetailView

**Files:**
- Modify: `MyStuff/Views/ItemDetailSheet.swift`
- Modify: `MyStuff/Views/LocationDetailView.swift`

**Interfaces:**
- Consumes: `FriendShareSheet` (Task 2), `viewModel.friends`/`canManageSharing`/`sharedMembers`/`shareItem`/`unshareItem`/`shareLocation`/`unshareLocation`/`addMembers`/`items(for:)`.

- [ ] **Step 1: Add a Share button + sheet to `ItemDetailSheet`**

In `MyStuff/Views/ItemDetailSheet.swift`, add state near the other `@State`:

```swift
    @State private var showShareSheet = false
```

Add a Share toolbar button (owner-only) — insert into the existing `.toolbar { … }`, alongside the Done button:

```swift
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    if viewModel.canManageSharing(of: item) {
                        Button {
                            showShareSheet = true
                        } label: {
                            Image(systemName: viewModel.isShared(item) ? "person.2.fill" : "person.2")
                        }
                    }
                }
            }
```

Add the share sheet presentation (alongside the other `.sheet` modifiers on the `NavigationStack`'s content — e.g. after the `.fullScreenCover(isPresented: $showCamera)`):

```swift
        .sheet(isPresented: $showShareSheet) {
            let live = viewModel.items.first(where: { $0.id == item.id }) ?? item
            FriendShareSheet(
                title: "Share \"\(live.name)\"",
                friends: viewModel.friends,
                sharedWith: Set(viewModel.sharedMembers(of: live)),
                onToggle: { uid, share in
                    if share { await viewModel.shareItem(live, withFriend: uid) }
                    else { await viewModel.unshareItem(live, fromFriend: uid) }
                }
            )
        }
```

- [ ] **Step 2: Add a Share action to `LocationDetailView`**

In `MyStuff/Views/LocationDetailView.swift`, add state:

```swift
    @State private var showShareSheet = false
    @State private var shareIncludeItems = false
```

Add a Share button to the existing `ToolbarItemGroup(placement: .primaryAction)` (owner-only), before the QR button:

```swift
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if viewModel.canManageSharing(of: live) {
                    Button { showShareSheet = true } label: {
                        Image(systemName: viewModel.isShared(live) ? "person.2.fill" : "person.2")
                    }
                }
                Button { showingQR = true } label: { Image(systemName: "qrcode") }
                Button("Edit") { showingEdit = true }
            }
        }
```

Add the share sheet presentation (after the existing `.sheet(item: $detailItem)`):

```swift
        .sheet(isPresented: $showShareSheet) {
            FriendShareSheet(
                title: "Share \"\(live.name)\"",
                friends: viewModel.friends,
                sharedWith: Set(viewModel.sharedMembers(of: live)),
                onToggle: { uid, share in
                    if share {
                        await viewModel.shareLocation(live, withFriend: uid)
                        // Convenience: also share the location's direct items with this friend.
                        for item in viewModel.items(for: live) where viewModel.canManageSharing(of: item) {
                            await viewModel.shareItem(item, withFriend: uid)
                        }
                    } else {
                        await viewModel.unshareLocation(live, fromFriend: uid)
                    }
                }
            )
        }
```

> Design note: sharing a location here also shares its **direct** items with that friend (the common intent — "share this whole shelf"). Unshare only unshares the location; per-item unshare stays available in each item's detail. This satisfies the spec's optional "also share its items" without a separate toggle.

- [ ] **Step 3: Build to verify**

Run: `xcodebuild -project MyStuff.xcodeproj -scheme MyStuff -destination 'generic/platform=iOS Simulator' -configuration Debug build 2>&1 | tail -20`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add MyStuff/Views/ItemDetailSheet.swift MyStuff/Views/LocationDetailView.swift
git commit -m "feat: Share actions in item + location detail (owner-only)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: Create-time sharing in ItemFormSheet

**Files:**
- Modify: `MyStuff/Views/ItemsView.swift`

**Interfaces:**
- Consumes: `viewModel.friends`, `viewModel.shareItem`.
- Produces: `ItemFormSheet.onSave` gains a trailing `Set<String>` (selected friend uids); the create path in `ItemsView` shares the new item with them.

- [ ] **Step 1: Add a "Share with" section + widen `onSave` in `ItemFormSheet`**

In `MyStuff/Views/ItemsView.swift`, change `ItemFormSheet`'s `onSave` type and init to carry selected friend uids. Change the stored property:

```swift
    let onSave: (String, String?, String?, String?, Data?, Data?, Set<String>) -> Void
```

Change the `init` signature + add state:

```swift
    @State private var shareWith: Set<String>

    init(
        item: Item? = nil,
        viewModel: StuffViewModel,
        onSave: @escaping (String, String?, String?, String?, Data?, Data?, Set<String>) -> Void
    ) {
        self.item = item
        self.viewModel = viewModel
        self.onSave = onSave
        _name = State(initialValue: item?.name ?? "")
        _notes = State(initialValue: item?.notes ?? "")
        _selectedLocationId = State(initialValue: item?.locationId ?? "__unassigned__")
        _selectedCategoryId = State(initialValue: item?.categoryId ?? "__uncategorized__")
        _useSameForLocation = State(initialValue: item == nil)
        _shareWith = State(initialValue: [])
    }
```

Add a "Share with" section (only when creating a new item and you have friends) — insert after the `Section("Category")` block:

```swift
                if item == nil && !viewModel.friends.isEmpty {
                    Section("Share with") {
                        ForEach(viewModel.friends) { friend in
                            Button {
                                if shareWith.contains(friend.uid) { shareWith.remove(friend.uid) }
                                else { shareWith.insert(friend.uid) }
                            } label: {
                                HStack {
                                    Text(friend.displayName).foregroundStyle(.primary)
                                    Spacer()
                                    if shareWith.contains(friend.uid) {
                                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
```

Update the Save button's `onSave` call to pass `shareWith`:

```swift
                        onSave(name, notes.isEmpty ? nil : notes, locationId, categoryId, photoData, resolvedLocationData, shareWith)
```

- [ ] **Step 2: Update the two `ItemFormSheet` call sites in `ItemsView`**

The **add** sheet's closure gains the `shareWith` param and shares after creating:

```swift
            .sheet(isPresented: $showingAddSheet) {
                ItemFormSheet(
                    viewModel: viewModel,
                    onSave: { name, notes, locationId, categoryId, itemPhotoData, locationPhotoData, shareWith in
                        Task {
                            await viewModel.addItem(name: name, notes: notes, locationId: locationId, categoryId: categoryId)
                            if let newItem = viewModel.items.last(where: { $0.name == name }) {
                                if let itemPhotoData {
                                    await viewModel.setItemPhoto(for: newItem, imageData: itemPhotoData)
                                }
                                if let locationPhotoData {
                                    let refreshed = viewModel.items.first(where: { $0.id == newItem.id }) ?? newItem
                                    await viewModel.setPhoto(for: refreshed, imageData: locationPhotoData)
                                }
                                for uid in shareWith {
                                    await viewModel.shareItem(newItem, withFriend: uid)
                                }
                            }
                        }
                    }
                )
            }
```

The **edit** sheet's closure just accepts and ignores the new param (editing doesn't create-share; sharing an existing item is done from its detail):

```swift
            .sheet(item: $editingItem) { item in
                ItemFormSheet(
                    item: item,
                    viewModel: viewModel,
                    onSave: { name, notes, locationId, categoryId, itemPhotoData, locationPhotoData, _ in
                        var updated = item
                        updated.name = name
                        updated.notes = notes
                        updated.locationId = locationId
                        updated.categoryId = categoryId
                        Task {
                            await viewModel.updateItem(updated)
                            if let itemPhotoData {
                                await viewModel.setItemPhoto(for: updated, imageData: itemPhotoData)
                            }
                            if let locationPhotoData {
                                let refreshed = viewModel.items.first(where: { $0.id == updated.id }) ?? updated
                                await viewModel.setPhoto(for: refreshed, imageData: locationPhotoData)
                            }
                        }
                    }
                )
            }
```

- [ ] **Step 3: Build to verify**

Run: `xcodebuild -project MyStuff.xcodeproj -scheme MyStuff -destination 'generic/platform=iOS Simulator' -configuration Debug build 2>&1 | tail -20`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add MyStuff/Views/ItemsView.swift
git commit -m "feat: create-time Share-with picker in ItemFormSheet

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 5: Move/share confirmation dialog in MoveItemSheet

**Files:**
- Modify: `MyStuff/Views/HomeView.swift` (the `MoveItemSheet` struct lives here)

**Interfaces:**
- Consumes: `viewModel.sharedMembers(of:)`, `viewModel.membersMissing(from:forItemMembers:)`, `viewModel.addMembers(_:toLocation:)`, `viewModel.makeItemPrivate(_:)`, `onMove`.
- Produces: `MoveItemSheet` intercepts a move that would put a **shared** item into a location **not** shared with its members, prompting "Share location too" / "Make item private" before completing the move.

- [ ] **Step 1: Add conflict interception to `MoveItemSheet`**

In `MyStuff/Views/HomeView.swift`, in the `MoveItemSheet` struct, add state:

```swift
    @State private var pendingMove: (locationId: String, location: Location, missing: [String])?
```

Add a private helper that decides whether to prompt or move directly, and replace the direct `onMove(...)` calls in the location `ForEach` and the "Unassigned" button with it:

```swift
    private func selectMove(toLocationId locationId: String?) {
        // Unassigned or non-shared item → move straight away.
        let liveItem = viewModel.items.first(where: { $0.id == item.id }) ?? item
        let itemMembers = viewModel.sharedMembers(of: liveItem)
        guard let locationId,
              !itemMembers.isEmpty,
              let location = viewModel.locations.first(where: { $0.id == locationId }) else {
            onMove(locationId)
            dismiss()
            return
        }
        let missing = viewModel.membersMissing(from: location, forItemMembers: itemMembers)
        if missing.isEmpty {
            onMove(locationId)
            dismiss()
        } else {
            pendingMove = (locationId, location, missing)
        }
    }
```

In the `content` body, change the "Unassigned" button action from `onMove(nil); dismiss()` to `selectMove(toLocationId: nil)`, and each location button action from `onMove(entry.location.id); dismiss()` to `selectMove(toLocationId: entry.location.id)`.

Add the confirmation dialog to the `List` (e.g. after the `.alert("Location not found", …)`):

```swift
            .confirmationDialog(
                pendingMove.map { "\"\(item.name)\" is shared, but \($0.location.name) isn't." } ?? "",
                isPresented: Binding(
                    get: { pendingMove != nil },
                    set: { if !$0 { pendingMove = nil } }
                ),
                titleVisibility: .visible
            ) {
                if let pending = pendingMove {
                    Button("Share \(pending.location.name) too") {
                        Task {
                            await viewModel.addMembers(pending.missing, toLocation: pending.location)
                            onMove(pending.locationId)
                            pendingMove = nil
                            dismiss()
                        }
                    }
                    Button("Make item private", role: .destructive) {
                        let liveItem = viewModel.items.first(where: { $0.id == item.id }) ?? item
                        Task {
                            await viewModel.makeItemPrivate(liveItem)
                            onMove(pending.locationId)
                            pendingMove = nil
                            dismiss()
                        }
                    }
                    Button("Cancel", role: .cancel) { pendingMove = nil }
                }
            }
```

- [ ] **Step 2: Build to verify**

Run: `xcodebuild -project MyStuff.xcodeproj -scheme MyStuff -destination 'generic/platform=iOS Simulator' -configuration Debug build 2>&1 | tail -20`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add MyStuff/Views/HomeView.swift
git commit -m "feat: move/share dialog when a shared item enters a not-shared location

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

> Follow-up (not in this task): the NFC move path (`applyNFCUpdate` via `NFCUpdateSheet`) does not route through `MoveItemSheet`, so it won't prompt. Log for a later pass.

---

### Task 6: Shared/owned-by-others badges across the lists

**Files:**
- Modify: `MyStuff/Views/ItemsView.swift`
- Modify: `MyStuff/Views/LocationsView.swift`
- Modify: `MyStuff/Views/LocationDetailView.swift`

**Interfaces:**
- Consumes: `SharedBadge` (Task 2), `viewModel.isShared`, `viewModel.isSharedWithMe`, `viewModel.friend(forUid:)`.

- [ ] **Step 1: Item row badge in `ItemsView`**

In `MyStuff/Views/ItemsView.swift`, add a helper near `locationBadge`/`categoryBadge`:

```swift
    @ViewBuilder
    private func sharedBadge(for item: Item) -> some View {
        if viewModel.isSharedWithMe(item) {
            SharedBadge(ownerName: viewModel.friend(forUid: item.ownerId ?? "")?.displayName)
        } else if viewModel.isShared(item) {
            SharedBadge()
        }
    }
```

In `itemsList`, add it to the trailing badges HStack (after `locationBadge(for: item)`):

```swift
                            categoryBadge(for: item)
                            locationBadge(for: item)
                            sharedBadge(for: item)
```

- [ ] **Step 2: Location row badge in `LocationsView`**

In `MyStuff/Views/LocationsView.swift`, in `locationsList`, add a badge inside the location label `HStack` before the item-count capsule. After the `Text(entry.location.name)` / `Spacer()` and before the count `Text`:

```swift
                            Text(entry.location.name)
                                .font(.body)
                                .foregroundStyle(.primary)
                            if viewModel.isSharedWithMe(entry.location) {
                                SharedBadge(iconOnly: true, ownerName: viewModel.friend(forUid: entry.location.ownerId ?? "")?.displayName)
                            } else if viewModel.isShared(entry.location) {
                                SharedBadge(iconOnly: true)
                            }
                            Spacer()
```

- [ ] **Step 3: Header badge in `LocationDetailView`**

In `MyStuff/Views/LocationDetailView.swift`, in the header `Section`'s `VStack`, add under the item-count text:

```swift
                        Text("\(viewModel.recursiveItemCount(for: live)) items")
                            .font(.caption).foregroundStyle(.secondary)
                        if viewModel.isSharedWithMe(live) {
                            SharedBadge(ownerName: viewModel.friend(forUid: live.ownerId ?? "")?.displayName)
                        } else if viewModel.isShared(live) {
                            SharedBadge()
                        }
```

- [ ] **Step 4: Build to verify**

Run: `xcodebuild -project MyStuff.xcodeproj -scheme MyStuff -destination 'generic/platform=iOS Simulator' -configuration Debug build 2>&1 | tail -20`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add MyStuff/Views/ItemsView.swift MyStuff/Views/LocationsView.swift MyStuff/Views/LocationDetailView.swift
git commit -m "feat: shared / shared-by badges on items and locations

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage (P2b slice):**
- Share existing item → Task 3 (ItemDetailSheet). ✅
- Share existing location (+ its items) → Task 3 (LocationDetailView). ✅
- Create already-shared item → Task 4. ✅
- Move/share dialog (shared item → not-shared location) → Task 5 (covers Home + Items via shared MoveItemSheet; NFC path logged as follow-up). ✅
- Shared content merged into normal tabs, badged → Task 6 + orphan roots (Task 1). ✅
- Owner-only sharing controls (P2a-review follow-up) → `canManageSharing` gating in Tasks 3–4. ✅
- Unshared items in a shared location stay hidden → already enforced by the P2a collectionGroup read; nothing to add. ✅

**Placeholder scan:** No TBD/TODO; every code step shows complete code. ✅

**Type consistency:** `viewModel.friends: [Friend]` set in ContentView, read in Tasks 2–6; `FriendShareSheet(title:friends:sharedWith:onToggle:)` used identically in Task 3; `ItemFormSheet.onSave` 7-arg form updated at the definition and both call sites (Task 4); `SharedBadge(iconOnly:ownerName:)` used consistently; `selectMove`/`pendingMove` internal to MoveItemSheet. ✅

## Known follow-ups (later)
- NFC move (`applyNFCUpdate`) doesn't route through `MoveItemSheet`, so it won't show the move/share dialog — add a parallel prompt in `NFCUpdateSheet` later.
- HomeView cards don't get badges in this plan (they group items under location cards); add if desired.
- Sharing a location shares its direct items but not sub-locations/their items — deep share is a future enhancement.
