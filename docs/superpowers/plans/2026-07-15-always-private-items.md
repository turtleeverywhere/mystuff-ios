# Always-Private Items Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a user flag an individual item as always-private so automatic member-propagation flows skip it, while manual sharing still works.

**Architecture:** Add an optional `isPrivate` flag to `Item`. Guard the one existing auto-share-item path (`moveLocation` subtree loop) with `isPrivate != true`. A new view-model method toggles the flag and, on enable, resets membership to owner-only. A privacy card in `ItemDetailSheet` drives it.

**Tech Stack:** Swift 6, SwiftUI, iOS 26, Firebase Firestore (Codable mapping). MVVM with a single shared `@Observable StuffViewModel`.

## Global Constraints

- Swift 6.0, iOS 26.0 target, bundle ID `com.flyingturtle.mystuff`.
- `@Observable` macro + `@Bindable` in views (not ObservableObject).
- Firestore uses Codable (`data(as:)` / `setData(from:)`); new model fields must be Optional so legacy docs missing the field decode without throwing.
- Haptics via `HapticManager` on CRUD ops.
- **No test target exists.** Verification is `xcodebuild` compile + manual driving. Build command, run from `/Users/lars/coding_projects/mystuff-ios`:
  ```
  xcodebuild -project MyStuff.xcodeproj -scheme MyStuff -destination 'generic/platform=iOS Simulator' -configuration Debug build
  ```
  Success marker: `** BUILD SUCCEEDED **` in the last ~60 lines.

---

### Task 1: Add `isPrivate` flag to Item model

**Files:**
- Modify: `MyStuff/Models/Item.swift`

**Interfaces:**
- Produces: `Item.isPrivate: Bool?` stored property; `init` gains `isPrivate: Bool? = nil` parameter. Callers test `item.isPrivate == true`.

- [ ] **Step 1: Add the stored property**

In `MyStuff/Models/Item.swift`, add after the `var nfcTagUID: String?` line:

```swift
    /// When true, automatic member-propagation flows (e.g. moveLocation subtree share)
    /// skip this item. Manual sharing is unaffected. Optional so legacy docs missing the
    /// field decode cleanly — same idiom as ownerId/memberIds.
    var isPrivate: Bool?
```

- [ ] **Step 2: Add the init parameter**

In the `init(...)` signature, add after `nfcTagUID: String? = nil,`:

```swift
        isPrivate: Bool? = nil,
```

And in the init body, add after `self.nfcTagUID = nfcTagUID`:

```swift
        self.isPrivate = isPrivate
```

- [ ] **Step 3: Build to verify it compiles**

Run:
```
xcodebuild -project MyStuff.xcodeproj -scheme MyStuff -destination 'generic/platform=iOS Simulator' -configuration Debug build 2>&1 | tail -60
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add MyStuff/Models/Item.swift
git commit -m "feat: add isPrivate flag to Item model"
```

---

### Task 2: Guard auto-share + add toggle method in StuffViewModel

**Files:**
- Modify: `MyStuff/ViewModels/StuffViewModel.swift`

**Interfaces:**
- Consumes: `Item.isPrivate` (Task 1); existing `persistItemMembers(_:)`, `currentUserId`, `items`.
- Produces: `func setItemPrivate(_ item: Item, _ isPrivate: Bool) async`.

- [ ] **Step 1: Guard the moveLocation subtree item loop**

In `MyStuff/ViewModels/StuffViewModel.swift`, in `moveLocation`, find the item loop guard (around line 665):

```swift
                for itemId in subtreeItemIds {
                    guard let it = items.first(where: { $0.id == itemId }),
                          canManageSharing(of: it) else { continue }
```

Replace the `guard` with (add the `isPrivate` condition + comment):

```swift
                for itemId in subtreeItemIds {
                    // Always-private items opt out of automatic member propagation.
                    // Any future auto-share-item flow must apply the same guard.
                    guard let it = items.first(where: { $0.id == itemId }),
                          canManageSharing(of: it),
                          it.isPrivate != true else { continue }
```

- [ ] **Step 2: Add the toggle method**

In the `// MARK: - Sharing` section, immediately after the `makeItemPrivate(_:)` method (ends around line 774), add:

```swift
    /// Set or clear the always-private flag. Enabling also resets the item to private
    /// (members = [owner]) in a single write; disabling only clears the flag.
    func setItemPrivate(_ item: Item, _ isPrivate: Bool) async {
        guard var updated = items.first(where: { $0.id == item.id }) else { return }
        updated.isPrivate = isPrivate
        if isPrivate {
            updated.memberIds = [updated.ownerId ?? currentUserId]
        }
        await persistItemMembers(updated)
    }
```

- [ ] **Step 3: Build to verify it compiles**

Run:
```
xcodebuild -project MyStuff.xcodeproj -scheme MyStuff -destination 'generic/platform=iOS Simulator' -configuration Debug build 2>&1 | tail -60
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add MyStuff/ViewModels/StuffViewModel.swift
git commit -m "feat: skip always-private items in moveLocation auto-share; add setItemPrivate"
```

---

### Task 3: Add privacy toggle card to ItemDetailSheet

**Files:**
- Modify: `MyStuff/Views/ItemDetailSheet.swift`

**Interfaces:**
- Consumes: `Item.isPrivate` (Task 1); `viewModel.setItemPrivate(_:_:)` (Task 2); existing `liveItem` computed property.

- [ ] **Step 1: Add the privacy card to the layout**

In `MyStuff/Views/ItemDetailSheet.swift`, in `body`, add `privacySection` after `nfcSection` in the main `VStack` (around line 35):

```swift
                    photoSection
                    infoSection
                    moveSection
                    nfcSection
                    privacySection
```

- [ ] **Step 2: Add the privacySection view**

Add this computed property near `nfcSection` (e.g. after the `nfcSection` block, before `// MARK: - Info Section`):

```swift
    // MARK: - Privacy Section

    private var privacySection: some View {
        let isPrivate = Binding(
            get: { liveItem.isPrivate == true },
            set: { newValue in
                Task { await viewModel.setItemPrivate(liveItem, newValue) }
            }
        )
        return VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: isPrivate) {
                HStack(spacing: 8) {
                    Image(systemName: "lock")
                        .foregroundStyle(.tint)
                    Text("Always private")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
            }
            Text("Excluded from automatic sharing.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
```

- [ ] **Step 3: Build to verify it compiles**

Run:
```
xcodebuild -project MyStuff.xcodeproj -scheme MyStuff -destination 'generic/platform=iOS Simulator' -configuration Debug build 2>&1 | tail -60
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add MyStuff/Views/ItemDetailSheet.swift
git commit -m "feat: always-private toggle card in item detail"
```

---

## Manual Verification (after all tasks)

Drive the app in the simulator:

1. **Persistence:** Open an item → toggle "Always private" on → close and reopen the sheet → toggle stays on.
2. **Reset-on-enable:** Share an item with a friend (share button) → toggle "Always private" on → item's shared badge clears (members reset to owner).
3. **Auto-share opt-out:** Put a flagged item and a non-flagged item in the same location → move that location under a shared parent → non-flagged item gains the parent's members; flagged item does not.
4. **Manual still works:** With the flag on, use the share button to share with a friend → sharing succeeds (auto-flows-only, manual override allowed).
