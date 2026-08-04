# Codes in Form Sheets Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users attach and remove NFC tags — and show/print the QR code — while creating or editing an item or a location, not only from its detail screen.

**Architecture:** The form sheets pre-allocate the entity's UUID so a draft can be paired and printed against before it is saved. `CodesSheet` becomes closure-driven so one component serves both the live detail screens and the staging form sheets. Staged tag edits are applied on Save through a new `applyStagedTags` viewmodel method.

**Tech Stack:** Swift 6.0, SwiftUI, iOS 26, CoreNFC, Firebase Firestore via `Codable`.

**Spec:** `docs/superpowers/specs/2026-08-04-codes-in-form-sheets-design.md`
**Parent feature spec:** `docs/superpowers/specs/2026-07-25-unified-qr-nfc-design.md`

## Global Constraints

- **This project has NO test target. Do not create one, and do not write XCTest files.** Every task's verification gate is a clean build plus the stated manual check.
- Build command, run from `/Users/lars/coding_projects/mystuff-ios`:
  ```
  xcodebuild -project MyStuff.xcodeproj -scheme MyStuff -destination 'generic/platform=iOS Simulator' -configuration Debug build
  ```
  Takes 30–90s. Tail the last 60 lines and confirm `** BUILD SUCCEEDED **`.
- The Xcode project uses `PBXFileSystemSynchronizedRootGroup`. **New `.swift` files under `MyStuff/` are picked up automatically — never hand-edit `MyStuff.xcodeproj/project.pbxproj`.**
- **Every task must end with a green build.** Where a signature change breaks call sites, that task fixes all of them.
- Follow existing conventions: `@Observable` (not `ObservableObject`), `@Bindable` in views, `ultraThinMaterial` / Liquid Glass styling, `HapticManager` on CRUD.
- Exact copy, used verbatim: the create-mode footers are **"Codes activate when you save this item."** and **"Codes activate when you save this location."**
- Items use the `📦` icon; locations use their emoji or `📍`.
- Commit after each task with a `feat:`/`refactor:` prefix and the trailer `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`.

---

### Task 1: `applyStagedTags` and caller-supplied ids

Pure viewmodel layer. Both changes are additive — the new `id` parameters are defaulted, so no existing call site changes behavior and nothing else breaks.

**Files:**
- Modify: `MyStuff/ViewModels/StuffViewModel.swift` (`addItem`, `addLocation`, and the NFC Tags section)

**Interfaces:**
- Consumes: `NFCTag`, `AppLink.Target`, `pairedTags(for:)`, `target(forTagUID:)`, `removeNFCTag(uid:from:)`, private `writeTags(_:to:)` — all already present.
- Produces: `applyStagedTags(_:to:) async`; `addItem(id:name:notes:locationId:categoryId:) async`; `addLocation(id:name:emoji:parentId:) async`.

- [ ] **Step 1: Add `applyStagedTags`**

In `MyStuff/ViewModels/StuffViewModel.swift`, add this immediately after `renameNFCTag(uid:label:on:)` in the `// MARK: - NFC Tags` section:

```swift
    /// Apply a buffered tag list to an entity, stripping each serial from any
    /// other entity that currently owns it. The form sheets stage tag edits
    /// until Save and then call this; `CodesSheet` in live mode writes through
    /// `addNFCTag` / `removeNFCTag` instead.
    ///
    /// No-ops when the staged list already matches, so an ordinary
    /// rename-the-item save writes no tags.
    func applyStagedTags(_ staged: [NFCTag], to entity: AppLink.Target) async {
        guard staged != pairedTags(for: entity) else { return }
        for tag in staged {
            if let previous = target(forTagUID: tag.uid), previous != entity {
                await removeNFCTag(uid: tag.uid, from: previous)
            }
        }
        await writeTags(staged, to: entity)
    }
```

The parameter is named `entity`, **not** `target` — a parameter named `target` would shadow the `target(forTagUID:)` method and the call inside the loop would fail to compile. The external label stays `to:` so call sites read naturally.

- [ ] **Step 2: Let callers supply the item id**

In the same file, change `addItem`'s signature and its `Item` construction. Replace:

```swift
    func addItem(name: String, notes: String?, locationId: String?, categoryId: String?) async {
        let owner = service.currentUserId
        let item = Item(name: name, notes: notes, locationId: locationId, categoryId: categoryId, locationChangedAt: locationId != nil ? .now : nil, ownerId: owner, memberIds: [owner])
```

with:

```swift
    /// `id` is defaulted so existing callers are unaffected. The form sheets
    /// pass a pre-allocated draft id so codes can be paired before the item exists.
    func addItem(id: String = UUID().uuidString, name: String, notes: String?, locationId: String?, categoryId: String?) async {
        let owner = service.currentUserId
        let item = Item(id: id, name: name, notes: notes, locationId: locationId, categoryId: categoryId, locationChangedAt: locationId != nil ? .now : nil, ownerId: owner, memberIds: [owner])
```

Leave the rest of the method body unchanged.

- [ ] **Step 3: Let callers supply the location id**

Replace:

```swift
    func addLocation(name: String, emoji: String?, parentId: String? = nil) async {
        let owner = service.currentUserId
        let location = Location(name: name, emoji: emoji, parentId: parentId, ownerId: owner, memberIds: [owner])
```

with:

```swift
    /// `id` is defaulted so existing callers are unaffected. The form sheets
    /// pass a pre-allocated draft id so codes can be paired before the location exists.
    func addLocation(id: String = UUID().uuidString, name: String, emoji: String?, parentId: String? = nil) async {
        let owner = service.currentUserId
        let location = Location(id: id, name: name, emoji: emoji, parentId: parentId, ownerId: owner, memberIds: [owner])
```

Leave the rest of the method body unchanged.

- [ ] **Step 4: Build**

Run: `xcodebuild -project MyStuff.xcodeproj -scheme MyStuff -destination 'generic/platform=iOS Simulator' -configuration Debug build 2>&1 | tail -60`

Expected: `** BUILD SUCCEEDED **`. Both `id` parameters are defaulted and `applyStagedTags` is new, so no existing call site should break.

- [ ] **Step 5: Commit**

```bash
git add MyStuff/ViewModels/StuffViewModel.swift
git commit -m "feat: applyStagedTags and caller-supplied entity ids

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 2: `CodesSheet` and `CodesRow` become closure-driven

`CodesSheet` currently reads `viewModel.pairedTags(for:)` and derives its `QRSubject` via `viewModel.qrSubject(for:)`, so it can only operate on an entity that already exists in `items` / `locations`. Both become inputs. Behavior on the detail screens is unchanged.

**Files:**
- Modify: `MyStuff/Views/CodesSheet.swift`
- Modify: `MyStuff/Views/ItemDetailSheet.swift:35, 79`
- Modify: `MyStuff/Views/LocationDetailView.swift:79, 155`

**Interfaces:**
- Consumes: `QRSubject` (`target`, `name`, `icon`, `urlString`), `NFCTag`, `NFCService.write(target:allowOverwrite:)`, `NFCError.existingPairing(target:tagSerial:)`, `viewModel.target(forTagUID:)`, `viewModel.displayName(for:)`, `viewModel.qrSubject(for:)`, `Item.pairedTags`, `Location.pairedTags`.
- Produces: `CodesRow(tags:)`; `CodesSheet(subject:tags:onPair:onRemove:onRename:viewModel:)`; the convenience `CodesSheet(live:tags:viewModel:)`.

- [ ] **Step 1: Make `CodesRow` take tags**

In `MyStuff/Views/CodesSheet.swift`, replace the whole `CodesRow` struct with:

```swift
/// Compact summary row that opens `CodesSheet`. Style-neutral so each screen
/// can wrap it in its own idiom (material card vs. List row). Takes the tag
/// list directly so a form sheet can show its staged count and a detail
/// screen its live one.
struct CodesRow: View {
    let tags: [NFCTag]

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "qrcode")
                .foregroundStyle(Color.appAccent)
            Text("Codes")
                .fontWeight(.medium)
            Spacer()
            Text(tags.isEmpty ? "QR only" : "QR · \(tags.count) tag\(tags.count == 1 ? "" : "s")")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
```

- [ ] **Step 2: Change `CodesSheet`'s inputs**

Replace the property block and the `tags` computed property — i.e. from `struct CodesSheet: View {` through the line `private var tags: [NFCTag] { viewModel.pairedTags(for: target) }` — with:

```swift
struct CodesSheet: View {
    let subject: QRSubject
    let tags: [NFCTag]
    /// Called with the scanned tag serial after a successful NDEF write.
    let onPair: @MainActor (String) async -> Void
    /// Called with the serial to unpair.
    let onRemove: @MainActor (String) async -> Void
    /// Called with the serial and its new label (nil clears it).
    let onRename: @MainActor (String, String?) async -> Void
    /// Needed only to name the *other* entity in the reassign alert.
    @Bindable var viewModel: StuffViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var nfcService: NFCService = CoreNFCService()
    @State private var isPairing = false
    @State private var errorMessage: String?
    @State private var showQR = false
    @State private var renamingTag: NFCTag?
    @State private var renameText = ""
    /// Set when the scanned tag already points elsewhere; drives the reassign alert.
    @State private var overwritePrevious: AppLink.Target?

    private var target: AppLink.Target { subject.target }
```

The closures are `@MainActor` because the staging callers mutate SwiftUI `@State` from inside them.

- [ ] **Step 3: Use the passed-in subject for the QR sheet**

Replace:

```swift
            .sheet(isPresented: $showQR) {
                if let subject = viewModel.qrSubject(for: target) {
                    QRCodeSheet(subject: subject, viewModel: viewModel)
                }
            }
```

with:

```swift
            .sheet(isPresented: $showQR) {
                QRCodeSheet(subject: subject, viewModel: viewModel)
            }
```

The optional is gone: the subject is now supplied by the caller, which is what makes the QR section work for an unsaved draft.

- [ ] **Step 4: Route the three mutations through the closures**

In `tagRow(_:)`, replace the swipe action's body:

```swift
                Task { await viewModel.removeNFCTag(uid: tag.uid, from: target) }
```

with:

```swift
                Task { await onRemove(tag.uid) }
```

In `renameAlertActions`, replace:

```swift
                Task { await viewModel.renameNFCTag(uid: tag.uid, label: text, on: target) }
```

with:

```swift
                Task { await onRename(tag.uid, text) }
```

In `pair(allowOverwrite:)`, replace the three lines that strip and add:

```swift
                // Strip the serial from whatever entity our records say owns it —
                // not from whatever the sticker's (possibly stale) NDEF pointed at.
                if let previous = viewModel.target(forTagUID: result.tagSerial), previous != target {
                    await viewModel.removeNFCTag(uid: result.tagSerial, from: previous)
                }
                await viewModel.addNFCTag(uid: result.tagSerial, to: target)
```

with:

```swift
                await onPair(result.tagSerial)
```

Leave the `catch` clauses exactly as they are — the reassign alert still resolves the previous owner via `viewModel.target(forTagUID: serial) ?? previous`, which is correct in both modes because it names a different, already-saved entity.

- [ ] **Step 5: Add the live-mode convenience initializer**

Add at the end of `MyStuff/Views/CodesSheet.swift`:

```swift
extension CodesSheet {
    /// Live mode: every edit writes straight through to the view model. Used by
    /// the detail screens, where the entity already exists. The staging form
    /// sheets use the memberwise initializer with buffer-mutating closures.
    init(live subject: QRSubject, tags: [NFCTag], viewModel: StuffViewModel) {
        let target = subject.target
        self.init(
            subject: subject,
            tags: tags,
            onPair: { serial in
                // Strip the serial from whatever entity our records say owns it —
                // not from whatever the sticker's (possibly stale) NDEF pointed at.
                if let previous = viewModel.target(forTagUID: serial), previous != target {
                    await viewModel.removeNFCTag(uid: serial, from: previous)
                }
                await viewModel.addNFCTag(uid: serial, to: target)
            },
            onRemove: { serial in
                await viewModel.removeNFCTag(uid: serial, from: target)
            },
            onRename: { serial, label in
                await viewModel.renameNFCTag(uid: serial, label: label, on: target)
            },
            viewModel: viewModel
        )
    }
}
```

- [ ] **Step 6: Update `ItemDetailSheet`**

In `MyStuff/Views/ItemDetailSheet.swift`, replace line 35:

```swift
                        CodesRow(target: .item(item.id), viewModel: viewModel)
```

with:

```swift
                        CodesRow(tags: liveItem.pairedTags)
```

and replace the `showCodes` sheet at line 78–80:

```swift
        .sheet(isPresented: $showCodes) {
            CodesSheet(target: .item(item.id), viewModel: viewModel)
        }
```

with:

```swift
        .sheet(isPresented: $showCodes) {
            if let subject = viewModel.qrSubject(for: .item(item.id)) {
                CodesSheet(live: subject, tags: liveItem.pairedTags, viewModel: viewModel)
            }
        }
```

- [ ] **Step 7: Update `LocationDetailView`**

In `MyStuff/Views/LocationDetailView.swift`, replace line 79:

```swift
                    CodesRow(target: .location(live.id), viewModel: viewModel)
```

with:

```swift
                    CodesRow(tags: live.pairedTags)
```

and replace the `showCodes` sheet at line 154–156:

```swift
        .sheet(isPresented: $showCodes) {
            CodesSheet(target: .location(live.id), viewModel: viewModel)
        }
```

with:

```swift
        .sheet(isPresented: $showCodes) {
            if let subject = viewModel.qrSubject(for: .location(live.id)) {
                CodesSheet(live: subject, tags: live.pairedTags, viewModel: viewModel)
            }
        }
```

- [ ] **Step 8: Build**

Run: `xcodebuild -project MyStuff.xcodeproj -scheme MyStuff -destination 'generic/platform=iOS Simulator' -configuration Debug build 2>&1 | tail -60`

Expected: `** BUILD SUCCEEDED **`. If the compiler reports actor-isolation errors on the closures, confirm the `@MainActor` attributes from Step 2 are present on all three closure types.

- [ ] **Step 9: Manual check**

This step is user-gated and cannot be run by an agent: the app opens on a Google sign-in screen. Record it as outstanding rather than attempting it. When a human runs it: open an item's detail, tap the Codes row, and confirm the sheet still lists the item's tags and opens its QR — behavior identical to before this task.

- [ ] **Step 10: Commit**

```bash
git add MyStuff/Views/CodesSheet.swift MyStuff/Views/ItemDetailSheet.swift MyStuff/Views/LocationDetailView.swift
git commit -m "refactor: CodesSheet takes a subject and mutation closures

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 3: Codes in `ItemFormSheet`

**Files:**
- Modify: `MyStuff/Views/ItemsView.swift` (`ItemFormSheet` + its two call sites at ~64 and ~86)
- Modify: `MyStuff/Views/LocationDetailView.swift:177` (the third `ItemFormSheet` call site)

**Interfaces:**
- Consumes: `applyStagedTags(_:to:)`, `addItem(id:…)` (Task 1); `CodesRow(tags:)`, `CodesSheet(subject:tags:onPair:onRemove:onRename:viewModel:)` (Task 2); `Item.pairedTags`; `QRSubject`.
- Produces: `ItemFormResult`; `ItemFormSheet(item:initialLocationId:viewModel:onSave:)` where `onSave: (ItemFormResult) -> Void`.

- [ ] **Step 1: Add the result payload**

The `onSave` closure already carries seven positional arguments; adding the draft id and the staged tags would make nine. Bundle them instead.

In `MyStuff/Views/ItemsView.swift`, add immediately above `struct ItemFormSheet: View {`:

```swift
/// Everything `ItemFormSheet` hands back on Save. Bundled rather than passed as
/// positional closure arguments — the list had already reached seven.
struct ItemFormResult {
    let id: String
    let name: String
    let notes: String?
    let locationId: String?
    let categoryId: String?
    let itemPhotoData: Data?
    let locationPhotoData: Data?
    let shareWith: Set<String>
    let nfcTags: [NFCTag]
}
```

- [ ] **Step 2: Add draft state to `ItemFormSheet`**

Change the `onSave` property declaration:

```swift
    let onSave: (String, String?, String?, String?, Data?, Data?, Set<String>) -> Void
```

to:

```swift
    let onSave: (ItemFormResult) -> Void
```

Add these alongside the other `@State` properties:

```swift
    /// Pre-allocated so codes can be paired and printed against a draft that
    /// has not been saved yet. MUST be `@State`: SwiftUI recreates the view
    /// struct on every render, so a plain `let` would mint a fresh UUID each
    /// pass and a paired tag would point at an id that never reaches Firestore.
    @State private var draftId: String
    /// Tag edits are buffered here and applied on Save, matching how the rest
    /// of this form treats Cancel.
    @State private var stagedTags: [NFCTag]
    @State private var showCodes = false
```

In `init`, change the `onSave` parameter type and add the two initializers. Replace:

```swift
        onSave: @escaping (String, String?, String?, String?, Data?, Data?, Set<String>) -> Void
```

with:

```swift
        onSave: @escaping (ItemFormResult) -> Void
```

and add after `_shareWith = State(initialValue: [])`:

```swift
        _draftId = State(initialValue: item?.id ?? UUID().uuidString)
        _stagedTags = State(initialValue: item?.pairedTags ?? [])
```

- [ ] **Step 3: Add the Codes section**

In the `Form`, add this section immediately after the `Section("Category")` block:

```swift
                Section {
                    Button {
                        showCodes = true
                    } label: {
                        CodesRow(tags: stagedTags)
                    }
                    .tint(.primary)
                } header: {
                    Text("Codes")
                } footer: {
                    if item == nil {
                        Text("Codes activate when you save this item.")
                    }
                }
```

- [ ] **Step 4: Present the staging `CodesSheet`**

Add alongside the sheet's other `.sheet` modifiers:

```swift
            .sheet(isPresented: $showCodes) {
                CodesSheet(
                    subject: QRSubject(target: .item(draftId), name: name, icon: "📦"),
                    tags: stagedTags,
                    onPair: { serial in
                        guard !stagedTags.contains(where: { $0.uid == serial }) else { return }
                        stagedTags.append(NFCTag(uid: serial))
                    },
                    onRemove: { serial in
                        stagedTags.removeAll { $0.uid == serial }
                    },
                    onRename: { serial, label in
                        guard let index = stagedTags.firstIndex(where: { $0.uid == serial }) else { return }
                        let trimmed = label?.trimmingCharacters(in: .whitespacesAndNewlines)
                        stagedTags[index].label = (trimmed?.isEmpty ?? true) ? nil : trimmed
                    },
                    viewModel: viewModel
                )
            }
```

The rename closure trims blank labels to nil, mirroring `StuffViewModel.renameNFCTag` so staged and live behave identically.

- [ ] **Step 5: Build the result on Save**

Replace the Save button's `onSave(...)` line:

```swift
                        onSave(name, notes.isEmpty ? nil : notes, locationId, categoryId, photoData, resolvedLocationData, shareWith)
```

with:

```swift
                        onSave(ItemFormResult(
                            id: draftId,
                            name: name,
                            notes: notes.isEmpty ? nil : notes,
                            locationId: locationId,
                            categoryId: categoryId,
                            itemPhotoData: photoData,
                            locationPhotoData: resolvedLocationData,
                            shareWith: shareWith,
                            nfcTags: stagedTags
                        ))
```

- [ ] **Step 6: Update the create call site in `ItemsView`**

Replace the `onSave` closure of the `ItemFormSheet` at ~line 64:

```swift
                    onSave: { result in
                        Task {
                            await viewModel.addItem(
                                id: result.id,
                                name: result.name,
                                notes: result.notes,
                                locationId: result.locationId,
                                categoryId: result.categoryId
                            )
                            guard let newItem = viewModel.items.first(where: { $0.id == result.id }) else { return }
                            if let data = result.itemPhotoData {
                                await viewModel.setItemPhoto(for: newItem, imageData: data)
                            }
                            if let data = result.locationPhotoData {
                                let refreshed = viewModel.items.first(where: { $0.id == result.id }) ?? newItem
                                await viewModel.setPhoto(for: refreshed, imageData: data)
                            }
                            for uid in result.shareWith {
                                await viewModel.shareItem(newItem, withFriend: uid)
                            }
                            await viewModel.applyStagedTags(result.nfcTags, to: .item(result.id))
                        }
                    }
```

Note the lookup is now by id rather than `items.last(where: { $0.name == name })`, so creating two items with the same name can no longer attach a photo to the wrong one.

- [ ] **Step 7: Update the edit call site in `ItemsView`**

Replace the `onSave` closure of the `ItemFormSheet` at ~line 86:

```swift
                    onSave: { result in
                        var updated = item
                        updated.name = result.name
                        updated.notes = result.notes
                        updated.locationId = result.locationId
                        updated.categoryId = result.categoryId
                        Task {
                            await viewModel.updateItem(updated)
                            if let data = result.itemPhotoData {
                                await viewModel.setItemPhoto(for: updated, imageData: data)
                            }
                            if let data = result.locationPhotoData {
                                let refreshed = viewModel.items.first(where: { $0.id == updated.id }) ?? updated
                                await viewModel.setPhoto(for: refreshed, imageData: data)
                            }
                            await viewModel.applyStagedTags(result.nfcTags, to: .item(item.id))
                        }
                    }
```

`applyStagedTags` runs after `updateItem` because `updated` is a snapshot taken before the form opened and carries the pre-edit tag list; the staged write lands last and wins.

- [ ] **Step 8: Update the create call site in `LocationDetailView`**

In `MyStuff/Views/LocationDetailView.swift`, replace the `onSave` closure of the `ItemFormSheet` at ~line 177:

```swift
                onSave: { result in
                    Task {
                        await viewModel.addItem(
                            id: result.id,
                            name: result.name,
                            notes: result.notes,
                            locationId: result.locationId,
                            categoryId: result.categoryId
                        )
                        guard let newItem = viewModel.items.first(where: { $0.id == result.id }) else { return }
                        if let data = result.itemPhotoData {
                            await viewModel.setItemPhoto(for: newItem, imageData: data)
                        }
                        if let data = result.locationPhotoData {
                            let refreshed = viewModel.items.first(where: { $0.id == result.id }) ?? newItem
                            await viewModel.setPhoto(for: refreshed, imageData: data)
                        }
                        for uid in result.shareWith {
                            await viewModel.shareItem(newItem, withFriend: uid)
                        }
                        await viewModel.applyStagedTags(result.nfcTags, to: .item(result.id))
                    }
                }
```

- [ ] **Step 9: Build**

Run: `xcodebuild -project MyStuff.xcodeproj -scheme MyStuff -destination 'generic/platform=iOS Simulator' -configuration Debug build 2>&1 | tail -60`

Expected: `** BUILD SUCCEEDED **`. Then confirm no call site was missed: `grep -rn "ItemFormSheet(" MyStuff` must return exactly three, and `grep -n "items.last(where" MyStuff/Views/*.swift` must return nothing.

If the `Form`'s `body` trips `error: the compiler is unable to type-check this expression in reasonable time`, extract the new section into a private computed property (`private var codesSection: some View`) and reference it — this codebase has hit that limit twice before. Keep all copy and behavior identical.

- [ ] **Step 10: Manual check**

User-gated; record as outstanding rather than attempting it (the app requires Google sign-in, and NFC needs physical hardware). When a human runs it:

- Create an item, open Codes, pair a tag, Save, then confirm the tag shows on the item's detail screen.
- Repeat but hit Cancel, and confirm no item was created.
- **Confirm the staged list updates inside the open sheet.** `CodesSheet` receives `tags` by value, so a newly paired tag only appears if SwiftUI re-evaluates the `.sheet` content when `stagedTags` mutates. It should — the content closure reads the parent's `@State`, so mutating it re-runs the parent body — but this is the one interaction in this task that static analysis cannot settle. If a paired tag does not appear until the sheet is reopened, the fix is to pass a `Binding` instead of a value and read `tags` through it.

- [ ] **Step 11: Commit**

```bash
git add MyStuff/Views/ItemsView.swift MyStuff/Views/LocationDetailView.swift
git commit -m "feat: manage codes while creating or editing an item

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 4: Codes in `LocationFormSheet`

Same treatment, so the two form sheets stay symmetric.

**Files:**
- Modify: `MyStuff/Views/LocationsView.swift` (`LocationFormSheet` + its two call sites at ~49 and ~78)
- Modify: `MyStuff/Views/LocationDetailView.swift:158` (edit call site)
- Modify: `MyStuff/Views/ItemQuickUpdateSheet.swift:79` (new-location call site)

**Interfaces:**
- Consumes: `applyStagedTags(_:to:)`, `addLocation(id:…)` (Task 1); `CodesRow(tags:)`, `CodesSheet(subject:tags:onPair:onRemove:onRename:viewModel:)` (Task 2); `Location.pairedTags`; `QRSubject`.
- Produces: `LocationFormResult`; `LocationFormSheet(location:initialParentId:viewModel:onSave:)` where `onSave: (LocationFormResult) -> Void`.

- [ ] **Step 1: Add the result payload**

In `MyStuff/Views/LocationsView.swift`, add immediately above `struct LocationFormSheet: View {`:

```swift
/// Everything `LocationFormSheet` hands back on Save. Mirrors `ItemFormResult`.
struct LocationFormResult {
    let id: String
    let name: String
    let emoji: String?
    let parentId: String?
    let nfcTags: [NFCTag]
}
```

- [ ] **Step 2: Add draft state to `LocationFormSheet`**

Change:

```swift
    let onSave: (String, String?, String?) -> Void
```

to:

```swift
    let onSave: (LocationFormResult) -> Void
```

Add alongside the other `@State` properties:

```swift
    /// Pre-allocated so codes can be paired and printed against a draft that
    /// has not been saved yet. MUST be `@State`: SwiftUI recreates the view
    /// struct on every render, so a plain `let` would mint a fresh UUID each
    /// pass and a paired tag would point at an id that never reaches Firestore.
    @State private var draftId: String
    /// Tag edits are buffered here and applied on Save.
    @State private var stagedTags: [NFCTag]
    @State private var showCodes = false
```

In `init`, change the `onSave` parameter type from `@escaping (String, String?, String?) -> Void` to `@escaping (LocationFormResult) -> Void`, and add after the `_selectedParentId` initializer:

```swift
        _draftId = State(initialValue: location?.id ?? UUID().uuidString)
        _stagedTags = State(initialValue: location?.pairedTags ?? [])
```

- [ ] **Step 3: Add the Codes section**

Add this as the last `Section` in the `Form`:

```swift
                Section {
                    Button {
                        showCodes = true
                    } label: {
                        CodesRow(tags: stagedTags)
                    }
                    .tint(.primary)
                } header: {
                    Text("Codes")
                } footer: {
                    if location == nil {
                        Text("Codes activate when you save this location.")
                    }
                }
```

- [ ] **Step 4: Present the staging `CodesSheet`**

Add to the `NavigationStack`'s modifiers:

```swift
            .sheet(isPresented: $showCodes) {
                CodesSheet(
                    subject: QRSubject(
                        target: .location(draftId),
                        name: name,
                        icon: emoji.isEmpty ? "📍" : emoji
                    ),
                    tags: stagedTags,
                    onPair: { serial in
                        guard !stagedTags.contains(where: { $0.uid == serial }) else { return }
                        stagedTags.append(NFCTag(uid: serial))
                    },
                    onRemove: { serial in
                        stagedTags.removeAll { $0.uid == serial }
                    },
                    onRename: { serial, label in
                        guard let index = stagedTags.firstIndex(where: { $0.uid == serial }) else { return }
                        let trimmed = label?.trimmingCharacters(in: .whitespacesAndNewlines)
                        stagedTags[index].label = (trimmed?.isEmpty ?? true) ? nil : trimmed
                    },
                    viewModel: viewModel
                )
            }
```

`viewModel` here is a plain `let` on `LocationFormSheet`, not `@Bindable`; passing it to `CodesSheet`'s `@Bindable` parameter is fine.

- [ ] **Step 5: Build the result on Save**

Replace the Save button's `onSave(...)` line:

```swift
                        onSave(name, emoji.isEmpty ? nil : emoji, parentId)
```

with:

```swift
                        onSave(LocationFormResult(
                            id: draftId,
                            name: name,
                            emoji: emoji.isEmpty ? nil : emoji,
                            parentId: parentId,
                            nfcTags: stagedTags
                        ))
```

- [ ] **Step 6: Update the two `LocationsView` call sites**

Replace the add-sheet closure at ~line 49:

```swift
                    onSave: { result in
                        Task {
                            await viewModel.addLocation(id: result.id, name: result.name, emoji: result.emoji, parentId: result.parentId)
                            await viewModel.applyStagedTags(result.nfcTags, to: .location(result.id))
                        }
                    }
```

Replace the add-sublocation closure at ~line 78:

```swift
                    onSave: { result in
                        Task {
                            await viewModel.addLocation(id: result.id, name: result.name, emoji: result.emoji, parentId: result.parentId)
                            await viewModel.applyStagedTags(result.nfcTags, to: .location(result.id))
                        }
                        if let parentId = result.parentId { expandedIds.insert(parentId) }
                    }
```

- [ ] **Step 7: Update the `LocationDetailView` edit call site**

In `MyStuff/Views/LocationDetailView.swift`, replace the `LocationFormSheet` `onSave` at ~line 158:

```swift
                onSave: { result in
                    var updated = live
                    updated.name = result.name
                    updated.emoji = result.emoji
                    updated.parentId = result.parentId
                    Task {
                        await viewModel.updateLocation(updated)
                        await viewModel.applyStagedTags(result.nfcTags, to: .location(live.id))
                    }
                }
```

- [ ] **Step 8: Update the `ItemQuickUpdateSheet` call site**

In `MyStuff/Views/ItemQuickUpdateSheet.swift`, replace the `LocationFormSheet` `onSave` at ~line 79:

```swift
                onSave: { result in
                    Task {
                        await viewModel.addLocation(id: result.id, name: result.name, emoji: result.emoji, parentId: result.parentId)
                        await viewModel.applyStagedTags(result.nfcTags, to: .location(result.id))
                        selectedLocationId = result.id
                    }
                }
```

The `locations.last(where: { $0.name == name && $0.parentId == parentId })` lookup is gone — the id is known up front.

- [ ] **Step 9: Build**

Run: `xcodebuild -project MyStuff.xcodeproj -scheme MyStuff -destination 'generic/platform=iOS Simulator' -configuration Debug build 2>&1 | tail -60`

Expected: `** BUILD SUCCEEDED **`. Then confirm nothing was missed: `grep -rn "LocationFormSheet(" MyStuff` must return exactly four, and `grep -rn "locations.last(where" MyStuff` must return nothing.

- [ ] **Step 10: Manual check**

User-gated; record as outstanding. When a human runs it: create a location, pair a tag in the form, Save, then scan the tag and confirm it opens that location.

- [ ] **Step 11: Commit**

```bash
git add MyStuff/Views/LocationsView.swift MyStuff/Views/LocationDetailView.swift MyStuff/Views/ItemQuickUpdateSheet.swift
git commit -m "feat: manage codes while creating or editing a location

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Final Verification

All of these are user-gated — the app opens on Google sign-in and NFC needs physical hardware. From the spec's testing section:

1. Create an item, pair a tag in the form, Save. The tag appears on the item's detail screen and scanning it opens that item.
2. Create an item, pair a tag, then **Cancel**. No item is created; scanning the tag offers to pair it elsewhere.
3. Edit an item, unpair one of two tags, Save. Only that tag is removed.
4. Edit an item, unpair a tag, then **Cancel**. The tag is still paired.
5. Pair a serial already held by another entity, Save. It moves; the previous owner keeps its other tags.
6. Create an item with no tag interaction at all. No tag write occurs and the item saves as before.
7. Create two items with the same name in a row, attaching a photo to each. Each photo lands on the correct item.
8. The same passes for `LocationFormSheet`.
