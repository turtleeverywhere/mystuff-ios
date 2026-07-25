# Unified QR + NFC Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give items and locations the same QR and NFC capabilities, with many labelled NFC tags allowed per entity.

**Architecture:** `AppLink.Target` becomes the currency for every QR/NFC operation, replacing bare ids with an implied type. NFC storage moves from `Item.nfcTagUID: String?` to `nfcTags: [NFCTag]?` on both `Item` and `Location`. A shared `CodesSheet` renders the QR row and the tag list for either entity kind, so the two detail screens cannot drift apart again.

**Tech Stack:** Swift 6.0, SwiftUI, iOS 26, CoreNFC, VisionKit (`DataScannerViewController`), CoreImage QR generation, Firebase Firestore via `Codable`.

**Spec:** `docs/superpowers/specs/2026-07-25-unified-qr-nfc-design.md`

## Global Constraints

- **No test target exists in this project.** Do not create one, and do not write XCTest files. Every task's verification gate is a clean build plus the stated manual check.
- Build command, run from `/Users/lars/coding_projects/mystuff-ios`:
  ```
  xcodebuild -project MyStuff.xcodeproj -scheme MyStuff -destination 'generic/platform=iOS Simulator' -configuration Debug build
  ```
  Takes 30–90s. Tail the last 60 lines and confirm `** BUILD SUCCEEDED **`.
- The Xcode project uses `PBXFileSystemSynchronizedRootGroup`. **New `.swift` files under `MyStuff/` are picked up automatically — never hand-edit `MyStuff.xcodeproj/project.pbxproj`.**
- **Every task must end with a green build.** Where a signature change breaks call sites, that task fixes all of them.
- Follow existing conventions: `@Observable` (not `ObservableObject`), `@Bindable` in views, `ultraThinMaterial` / Liquid Glass styling, `HapticManager` on CRUD, optional model fields for backward-compatible decode (the `ownerId` / `memberIds` idiom).
- `Item.nfcTagUID` is **retained** for legacy decode through the whole plan. It is never re-read after Task 2 except inside `pairedTags`, and is nil'd on any tag write.
- Commit after each task with a `feat:`/`refactor:` prefix and the `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>` trailer.

---

### Task 1: `NFCTag` model, `AppLink.Target` upgrade, entity fields

Pure additive model layer. No existing call site changes, so the build stays green with zero churn.

**Files:**
- Create: `MyStuff/Models/NFCTag.swift`
- Modify: `MyStuff/Services/AppLink.swift`
- Modify: `MyStuff/Models/Item.swift`
- Modify: `MyStuff/Models/Location.swift`

**Interfaces:**
- Produces: `NFCTag {uid: String, label: String?, id: String, displayName: String, shortSerial: String}`; `AppLink.Target: Hashable, Identifiable` with `id`, `entityId`, `kind`; `AppLink.TargetKind {any, item, location}` with `accepts(_:)`; `Item.pairedTags` / `Location.pairedTags: [NFCTag]`; `Item.nfcTags` / `Location.nfcTags: [NFCTag]?`.

- [ ] **Step 1: Create the tag model**

Create `MyStuff/Models/NFCTag.swift`:

```swift
import Foundation

/// One physical NFC sticker paired to an item or location.
/// `uid` is the tag's hex serial and is the stable identity; `label` is a
/// display-only name the user can edit ("front", "inside lid"). Nothing is
/// written to the tag itself beyond the universal link.
struct NFCTag: Codable, Hashable, Sendable, Identifiable {
    var uid: String
    var label: String?

    var id: String { uid }

    init(uid: String, label: String? = nil) {
        self.uid = uid
        self.label = label
    }

    /// Trailing bytes of the serial, for when the tag has no user label.
    var shortSerial: String {
        uid.count <= 8 ? uid : "…" + uid.suffix(8)
    }

    /// What list rows show: the label when set, otherwise the short serial.
    var displayName: String {
        if let label, !label.isEmpty { return label }
        return shortSerial
    }
}
```

- [ ] **Step 2: Upgrade `AppLink.Target`**

In `MyStuff/Services/AppLink.swift`, replace the `Target` enum declaration:

```swift
    enum Target: Equatable {
        case item(String)
        case location(String)
    }
```

with:

```swift
    enum Target: Equatable, Hashable, Identifiable {
        case item(String)
        case location(String)

        /// Stable, kind-qualified identity. Two entities of different kinds
        /// could in principle share a UUID, so the kind is part of the id.
        var id: String {
            switch self {
            case .item(let id): return "item:\(id)"
            case .location(let id): return "location:\(id)"
            }
        }

        /// The bare entity UUID, without the kind prefix.
        var entityId: String {
            switch self {
            case .item(let id), .location(let id): return id
            }
        }

        var kind: TargetKind {
            switch self {
            case .item: return .item
            case .location: return .location
            }
        }
    }

    /// Filter for scanners that only accept one kind of code.
    /// `Target.kind` never returns `.any`; it exists for the filter side only.
    enum TargetKind {
        case any, item, location

        func accepts(_ target: Target) -> Bool {
            switch self {
            case .any: return true
            case .item: return target.kind == .item
            case .location: return target.kind == .location
            }
        }

        /// Inline message shown when a scanned code is the wrong kind.
        var rejectionMessage: String {
            switch self {
            case .any: return "Not a MyStuff code"
            case .item: return "That's not an item code"
            case .location: return "That's not a location code"
            }
        }
    }
```

- [ ] **Step 3: Add the tag array to `Item`**

In `MyStuff/Models/Item.swift`, immediately after the existing `var nfcTagUID: String?` line (line 18), add:

```swift
    /// Legacy single-tag field above is kept for decode only. All paired tags
    /// live here; reads go through `pairedTags`, which merges the two.
    var nfcTags: [NFCTag]?
```

Add the parameter to `init`, immediately after `nfcTagUID: String? = nil,`:

```swift
        nfcTags: [NFCTag]? = nil,
```

and the assignment, immediately after `self.nfcTagUID = nfcTagUID`:

```swift
        self.nfcTags = nfcTags
```

Then add this computed property next to the existing `members` accessor:

> **Amended after review.** The original version of this step guarded the legacy
> fallback on `!nfcTags.isEmpty`, which shipped a critical bug: writes use
> `setData(from:merge: true)` and Swift's synthesized `Codable` emits
> `encodeIfPresent`, so nil-ing `nfcTagUID` omits the key entirely and Firestore
> keeps the old serial. Unpairing the last tag then emptied the array, fell
> through to the surviving legacy field, and the live listener resurrected the
> tag — leaving legacy items permanently unpairable. A non-nil `nfcTags` must
> win **even when empty**; that is sound because `writeTags` is its only writer
> and always writes the complete list.

```swift
    /// Non-optional tag list. A non-nil `nfcTags` means this item has been
    /// migrated, so it wins even when empty — otherwise unpairing the last
    /// tag would fall back to the legacy field and resurrect it. (The legacy
    /// field survives in Firestore because `merge: true` writes omit nil.)
    var pairedTags: [NFCTag] {
        if let nfcTags { return nfcTags }
        if let nfcTagUID { return [NFCTag(uid: nfcTagUID)] }
        return []
    }
```

- [ ] **Step 4: Add the tag array to `Location`**

In `MyStuff/Models/Location.swift`, add after `var shareBatchId: String?`:

```swift
    /// Paired NFC stickers. Locations have no legacy single-tag field.
    var nfcTags: [NFCTag]?
```

Add to `init`, after `shareBatchId: String? = nil,`:

```swift
        nfcTags: [NFCTag]? = nil,
```

and after `self.shareBatchId = shareBatchId`:

```swift
        self.nfcTags = nfcTags
```

Then next to `members`:

```swift
    /// Non-optional tag list. No legacy branch — locations never had a single-tag field.
    var pairedTags: [NFCTag] { nfcTags ?? [] }
```

- [ ] **Step 5: Build**

Run: `xcodebuild -project MyStuff.xcodeproj -scheme MyStuff -destination 'generic/platform=iOS Simulator' -configuration Debug build 2>&1 | tail -60`

Expected: `** BUILD SUCCEEDED **`. Nothing else changed, so no call site should break.

- [ ] **Step 6: Commit**

```bash
git add MyStuff/Models/NFCTag.swift MyStuff/Models/Item.swift MyStuff/Models/Location.swift MyStuff/Services/AppLink.swift
git commit -m "feat: NFCTag model, multi-tag fields on Item/Location, Target upgrade

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 2: `StuffViewModel` tag API

Adds the target-keyed tag operations. The three old item-only helpers are rewritten to delegate, so existing callers keep compiling; they are deleted in Task 5 when their last caller goes.

**Files:**
- Modify: `MyStuff/ViewModels/StuffViewModel.swift:564-583`

**Interfaces:**
- Consumes: `NFCTag`, `AppLink.Target`, `Item.pairedTags`, `Location.pairedTags` (Task 1).
- Produces: `pairedTags(for:)`, `target(forTagUID:)`, `displayName(for:)`, `qrSubject(for:)`, `addNFCTag(uid:to:)`, `removeNFCTag(uid:from:)`, `renameNFCTag(uid:label:on:)`.

- [ ] **Step 1: Replace the item-only NFC helpers**

In `MyStuff/ViewModels/StuffViewModel.swift`, replace lines 564–583 — the block from `/// Find the item currently paired to a given NFC tag serial.` through the closing brace of `setNFCTag(itemId:uid:)` — with:

```swift
    // MARK: - NFC Tags

    /// Paired tags for either entity kind. Returns `[]` for an unknown target.
    func pairedTags(for target: AppLink.Target) -> [NFCTag] {
        switch target {
        case .item(let id): return items.first { $0.id == id }?.pairedTags ?? []
        case .location(let id): return locations.first { $0.id == id }?.pairedTags ?? []
        }
    }

    /// Which entity, if any, currently owns this tag serial. Items are searched first.
    func target(forTagUID uid: String) -> AppLink.Target? {
        if let item = items.first(where: { $0.pairedTags.contains { $0.uid == uid } }) {
            return .item(item.id)
        }
        if let location = locations.first(where: { $0.pairedTags.contains { $0.uid == uid } }) {
            return .location(location.id)
        }
        return nil
    }

    /// Entity name for alerts and sheet titles.
    func displayName(for target: AppLink.Target) -> String? {
        switch target {
        case .item(let id): return items.first { $0.id == id }?.name
        case .location(let id): return locations.first { $0.id == id }?.name
        }
    }

    /// Everything the QR renderer needs. Items have no emoji field (nor does
    /// Category), so they fall back to a box glyph.
    func qrSubject(for target: AppLink.Target) -> QRSubject? {
        switch target {
        case .item(let id):
            guard let item = items.first(where: { $0.id == id }) else { return nil }
            return QRSubject(target: target, name: item.name, icon: "📦")
        case .location(let id):
            guard let location = locations.first(where: { $0.id == id }) else { return nil }
            return QRSubject(target: target, name: location.name, icon: location.emoji ?? "📍")
        }
    }

    /// Single write path for tags. `pairedTags` already folded any legacy
    /// `nfcTagUID` into `tags` before we got here, so nil-ing it locally just
    /// drops the duplicate. The *server* copy survives — `merge: true` writes
    /// omit nil optionals — but it is inert, because a non-nil `nfcTags` wins
    /// in `pairedTags` from here on.
    private func writeTags(_ tags: [NFCTag], to target: AppLink.Target) async {
        switch target {
        case .item(let id):
            guard var item = items.first(where: { $0.id == id }) else { return }
            item.nfcTags = tags
            item.nfcTagUID = nil
            await updateItem(item)
        case .location(let id):
            guard var location = locations.first(where: { $0.id == id }) else { return }
            location.nfcTags = tags
            await updateLocation(location)
        }
    }

    /// Append a tag. De-duplicates by uid, so re-pairing the same sticker is a no-op.
    func addNFCTag(uid: String, to target: AppLink.Target) async {
        var tags = pairedTags(for: target)
        guard !tags.contains(where: { $0.uid == uid }) else { return }
        tags.append(NFCTag(uid: uid))
        await writeTags(tags, to: target)
    }

    /// Unpair one serial, leaving the entity's other tags intact.
    func removeNFCTag(uid: String, from target: AppLink.Target) async {
        var tags = pairedTags(for: target)
        tags.removeAll { $0.uid == uid }
        await writeTags(tags, to: target)
    }

    /// Set or clear a tag's display label. Blank input stores nil, not "".
    func renameNFCTag(uid: String, label: String?, on target: AppLink.Target) async {
        var tags = pairedTags(for: target)
        guard let index = tags.firstIndex(where: { $0.uid == uid }) else { return }
        let trimmed = label?.trimmingCharacters(in: .whitespacesAndNewlines)
        tags[index].label = (trimmed?.isEmpty ?? true) ? nil : trimmed
        await writeTags(tags, to: target)
    }

    // MARK: - Legacy item-only shims (removed in Task 5)

    func item(forTagUID uid: String) -> Item? {
        guard case .item(let id)? = target(forTagUID: uid) else { return nil }
        return items.first { $0.id == id }
    }

    func clearNFCTag(itemId: String) async {
        for tag in pairedTags(for: .item(itemId)) {
            await removeNFCTag(uid: tag.uid, from: .item(itemId))
        }
    }

    func setNFCTag(itemId: String, uid: String) async {
        await addNFCTag(uid: uid, to: .item(itemId))
    }
}
```

Note the trailing `}` closes the type — verify you have not doubled or dropped a brace, since the replaced region ended mid-type.

- [ ] **Step 2: Add the `QRSubject` type**

`qrSubject(for:)` references a type that does not exist yet. Create `MyStuff/Models/QRSubject.swift`:

```swift
import Foundation

/// What the QR renderer needs to draw a sticker, independent of entity kind.
struct QRSubject: Identifiable, Hashable {
    let target: AppLink.Target
    let name: String
    /// Emoji drawn in the tile caption.
    let icon: String

    var id: String { target.id }

    /// The universal link encoded into the QR image.
    var urlString: String { AppLink.url(for: target).absoluteString }
}
```

- [ ] **Step 3: Build**

Run: `xcodebuild -project MyStuff.xcodeproj -scheme MyStuff -destination 'generic/platform=iOS Simulator' -configuration Debug build 2>&1 | tail -60`

Expected: `** BUILD SUCCEEDED **`. The shims keep `ItemDetailSheet` and `NFCPairSheet` compiling unchanged.

- [ ] **Step 4: Commit**

```bash
git add MyStuff/ViewModels/StuffViewModel.swift MyStuff/Models/QRSubject.swift
git commit -m "feat: target-keyed NFC tag API on StuffViewModel

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 3: Generalize `NFCService` to targets

**Files:**
- Modify: `MyStuff/Services/NFCService.swift`
- Modify: `MyStuff/Views/ItemDetailSheet.swift:310`
- Modify: `MyStuff/Views/NFCPairSheet.swift:108`

**Interfaces:**
- Consumes: `AppLink.Target`, `AppLink.parse` (Task 1).
- Produces: `NFCScanResult {target: AppLink.Target?, previousTarget: AppLink.Target?, tagSerial: String}`; `NFCService.write(target:allowOverwrite:)`; `NFCError.existingPairing(target:tagSerial:)`.

- [ ] **Step 1: Delete `NFCLink`, generalize the result and protocol**

In `MyStuff/Services/NFCService.swift`, replace everything from the top of the file through the end of the `NFCService` protocol (the `NFCLink` enum, `NFCScanResult`, `NFCError`, `protocol NFCService`) with:

```swift
import Foundation
@preconcurrency import CoreNFC

struct NFCScanResult: Sendable {
    /// Parsed target if the tag's NDEF holds a universal link we recognize.
    /// After a successful write, this is the newly written target.
    let target: AppLink.Target?
    /// For writes: what the tag pointed at before being overwritten, if different.
    /// nil for pure reads and fresh writes onto a blank tag.
    let previousTarget: AppLink.Target?
    /// Hex-encoded tag serial (UID).
    let tagSerial: String
}

enum NFCError: LocalizedError {
    case unavailable
    case userCancelled
    case sessionInvalidated(String)
    case readOnlyTag
    case writeFailed(String)
    case unsupportedTag
    /// Tag carries a different target; surface to UI so the user can confirm overwrite.
    case existingPairing(target: AppLink.Target, tagSerial: String)

    var errorDescription: String? {
        switch self {
        case .unavailable: return "NFC is not available on this device."
        case .userCancelled: return "Scan cancelled."
        case .sessionInvalidated(let msg): return msg
        case .readOnlyTag: return "This tag is read-only and cannot be written."
        case .writeFailed(let msg): return "Write failed: \(msg)"
        case .unsupportedTag: return "Tag type is not supported."
        case .existingPairing: return "Tag is paired to something else."
        }
    }
}

protocol NFCService: AnyObject, Sendable {
    var isAvailable: Bool { get }
    func scan() async throws -> NFCScanResult
    func write(target: AppLink.Target, allowOverwrite: Bool) async throws -> NFCScanResult
}
```

`NFCLink` is gone — `AppLink` already owns the URL shape, and its item-only helpers no longer make sense.

- [ ] **Step 2: Update `CoreNFCService`**

Change the `Mode` enum:

```swift
    private enum Mode {
        case read
        case write(target: AppLink.Target, allowOverwrite: Bool)
    }
```

Replace `writeItem(id:allowOverwrite:)` with:

```swift
    func write(target: AppLink.Target, allowOverwrite: Bool) async throws -> NFCScanResult {
        try await begin(
            mode: .write(target: target, allowOverwrite: allowOverwrite),
            alert: "Hold your iPhone near the tag to pair"
        )
    }
```

In `handleConnected`, rename the local binding: `let existingId = Self.extractItemId(from: unsafeMessage)` becomes:

```swift
                        let existingTarget = Self.extractTarget(from: unsafeMessage)
```

and the `afterRead` call's argument `existingId: existingId` becomes `existingTarget: existingTarget`.

Replace the whole `afterRead` method with:

```swift
    private func afterRead(
        serial: String,
        existingTarget: AppLink.Target?,
        status: NFCNDEFStatus,
        ndefTag: NFCNDEFTag,
        session: NFCTagReaderSession
    ) {
        switch mode {
        case .read:
            session.alertMessage = "Tag scanned"
            session.invalidate()
            finish(.success(NFCScanResult(target: existingTarget, previousTarget: nil, tagSerial: serial)))

        case .write(let target, let allowOverwrite):
            if let existing = existingTarget, existing != target, !allowOverwrite {
                session.invalidate(errorMessage: "Tag paired to something else")
                finish(.failure(NFCError.existingPairing(target: existing, tagSerial: serial)))
                return
            }
            guard status == .readWrite else {
                session.invalidate(errorMessage: "Tag is read-only")
                finish(.failure(NFCError.readOnlyTag))
                return
            }
            let uri = AppLink.url(for: target).absoluteString
            guard let urlPayload = NFCNDEFPayload.wellKnownTypeURIPayload(string: uri) else {
                session.invalidate(errorMessage: "Failed to encode payload")
                finish(.failure(NFCError.writeFailed("payload encoding")))
                return
            }
            let message = NFCNDEFMessage(records: [urlPayload])
            let previousTarget = (existingTarget != target) ? existingTarget : nil
            nonisolated(unsafe) let unsafeSession = session
            ndefTag.writeNDEF(message) { [weak self] error in
                guard let self else { return }
                self.queue.async {
                    if let error {
                        unsafeSession.invalidate(errorMessage: error.localizedDescription)
                        self.finish(.failure(NFCError.writeFailed(error.localizedDescription)))
                    } else {
                        unsafeSession.alertMessage = "Tag paired"
                        unsafeSession.invalidate()
                        self.finish(.success(NFCScanResult(target: target, previousTarget: previousTarget, tagSerial: serial)))
                    }
                }
            }
        }
    }
```

Replace `extractItemId` with:

```swift
    private static func extractTarget(from message: NFCNDEFMessage?) -> AppLink.Target? {
        guard let records = message?.records else { return nil }
        for record in records {
            if let url = record.wellKnownTypeURIPayload(),
               let target = AppLink.parse(url) {
                return target
            }
        }
        return nil
    }
```

- [ ] **Step 3: Update `MockNFCService`**

Replace the mock at the bottom of the file with:

```swift
final class MockNFCService: NFCService, @unchecked Sendable {
    var isAvailable: Bool { true }

    /// Configure for previews: nil = blank tag, set = paired tag.
    var stubTarget: AppLink.Target?
    var stubSerial: String = "MOCK01020304"

    func scan() async throws -> NFCScanResult {
        try? await Task.sleep(nanoseconds: 300_000_000)
        return NFCScanResult(target: stubTarget, previousTarget: nil, tagSerial: stubSerial)
    }

    func write(target: AppLink.Target, allowOverwrite: Bool) async throws -> NFCScanResult {
        try? await Task.sleep(nanoseconds: 300_000_000)
        if let existing = stubTarget, existing != target, !allowOverwrite {
            throw NFCError.existingPairing(target: existing, tagSerial: stubSerial)
        }
        let previous = (stubTarget != target) ? stubTarget : nil
        stubTarget = target
        return NFCScanResult(target: target, previousTarget: previous, tagSerial: stubSerial)
    }
}
```

- [ ] **Step 4: Fix the two call sites**

In `MyStuff/Views/ItemDetailSheet.swift`, inside `pairTag(allowOverwrite:)`, replace the body of the `do` block's first three lines:

```swift
                let result = try await nfcService.writeItem(id: item.id, allowOverwrite: allowOverwrite)
                if let prevId = result.previousItemId {
                    await viewModel.clearNFCTag(itemId: prevId)
                }
```

with:

```swift
                let result = try await nfcService.write(target: .item(item.id), allowOverwrite: allowOverwrite)
                if let previous = result.previousTarget {
                    await viewModel.removeNFCTag(uid: result.tagSerial, from: previous)
                }
```

and change the catch clause `catch NFCError.existingPairing(let previousId, _) { ... pairOverwritePrevious = previousId }` to:

```swift
            } catch NFCError.existingPairing(let previous, _) {
                isPairing = false
                pairOverwritePrevious = previous.entityId
```

In `MyStuff/Views/NFCPairSheet.swift`, inside `pair(item:allowOverwrite:)`, apply the same substitution:

```swift
                let result = try await nfcService.write(target: .item(item.id), allowOverwrite: allowOverwrite)
                if let previous = result.previousTarget {
                    await viewModel.removeNFCTag(uid: result.tagSerial, from: previous)
                }
                await viewModel.addNFCTag(uid: result.tagSerial, to: .item(item.id))
```

and change its catch clause to:

```swift
            } catch NFCError.existingPairing(let previous, _) {
                isPairing = false
                overwriteCandidate = (item, previous.entityId)
```

- [ ] **Step 5: Build**

Run: `xcodebuild -project MyStuff.xcodeproj -scheme MyStuff -destination 'generic/platform=iOS Simulator' -configuration Debug build 2>&1 | tail -60`

Expected: `** BUILD SUCCEEDED **`. If the compiler reports `previousItemId` or `itemId` on `NFCScanResult`, a call site was missed — grep for `writeItem(` and `previousItemId` and fix.

- [ ] **Step 6: Commit**

```bash
git add MyStuff/Services/NFCService.swift MyStuff/Views/ItemDetailSheet.swift MyStuff/Views/NFCPairSheet.swift
git commit -m "refactor: NFCService operates on AppLink.Target, not item ids

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 4: `QRCodeSheet` / `QRTileView` take a `QRSubject`

**Files:**
- Modify: `MyStuff/Views/BatchQRPrintSheet.swift:31-70` (`QRTileView`)
- Modify: `MyStuff/Views/QRCodeSheet.swift`
- Modify: `MyStuff/Views/LocationDetailView.swift:140`

**Interfaces:**
- Consumes: `QRSubject` (Task 2), `AppLink.url(for:)`.
- Produces: `QRTileView(subject:qrImage:size:showIcon:showName:)`, `QRCodeSheet(subject:viewModel:)`.

- [ ] **Step 1: Generalize `QRTileView`**

In `MyStuff/Views/BatchQRPrintSheet.swift`, replace the `location` property and the two usages in the caption:

```swift
struct QRTileView: View {
    let subject: QRSubject
    let qrImage: UIImage
    let size: QRTileSize
    var showIcon: Bool = true
    var showName: Bool = true
```

In the caption `HStack`, `Text(location.emoji ?? "📍")` becomes `Text(subject.icon)` and `Text(location.name)` becomes `Text(subject.name)`. Everything else in the view is unchanged.

- [ ] **Step 2: Generalize `QRCodeSheet`**

In `MyStuff/Views/QRCodeSheet.swift`, replace `let location: Location` with `let subject: QRSubject`, then substitute throughout:

- `QRTileView(location: location, ...)` → `QRTileView(subject: subject, ...)` (two occurrences: `content(qrImage:)` and `render()`)
- `SharePreview("\(location.name) QR", ...)` → `SharePreview("\(subject.name) QR", ...)` (two occurrences)
- `PDFPrinter.print(data, jobName: "\(location.name) QR")` → `jobName: "\(subject.name) QR"`
- `BatchQRPrintSheet(viewModel: viewModel, initialSelection: [location.id])` → `initialSelection: [subject.target]`

In `render()`, replace the first line:

```swift
        let urlString = AppLink.url(for: .location(location.id)).absoluteString
```

with:

```swift
        let urlString = subject.urlString
```

In `writeTemp(_:ext:)`, replace the `safe` / `name` / `url` lines with:

```swift
        let safe = subject.name
            .components(separatedBy: CharacterSet(charactersIn: "/\\:")).joined(separator: "-")
        let name = safe.isEmpty ? "code" : safe
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(subject.target.entityId.prefix(8))-qr.\(ext)")
```

- [ ] **Step 3: Update the one existing caller**

In `MyStuff/Views/LocationDetailView.swift`, replace:

```swift
            QRCodeSheet(location: live, viewModel: viewModel)
```

with:

```swift
            QRCodeSheet(
                subject: QRSubject(target: .location(live.id), name: live.name, icon: live.emoji ?? "📍"),
                viewModel: viewModel
            )
```

- [ ] **Step 4: Build**

Run: `xcodebuild -project MyStuff.xcodeproj -scheme MyStuff -destination 'generic/platform=iOS Simulator' -configuration Debug build 2>&1 | tail -60`

Expected: `** BUILD SUCCEEDED **`. `BatchQRPrintSheet.makeBatchPDF` still constructs `QRTileView(location:)` and will fail here — fix it provisionally by mapping each location to a subject inside `makeBatchPDF`:

```swift
            let subject = QRSubject(target: .location(loc.id), name: loc.name, icon: loc.emoji ?? "📍")
            guard let qr = QRCodeGenerator.image(for: subject.urlString) else { return nil }
            let renderer = ImageRenderer(content: QRTileView(subject: subject, qrImage: qr, size: size, showIcon: showIcon, showName: showName))
```

and change `initialSelection` in `BatchQRPrintSheet.init` to `Set<AppLink.Target>` with `_selectedIds = State(initialValue: initialSelection)`, plus `@State private var selectedIds: Set<AppLink.Target>`. Task 7 rebuilds this sheet properly; this keeps the build green. Inside the body, `selectedIds.contains(entry.location.id)` becomes `selectedIds.contains(.location(entry.location.id))`, `toggle(entry.location.id)` becomes `toggle(.location(entry.location.id))`, `toggle`/`toggleAll` take `AppLink.Target` / map to `.location(...)`, and `makeBatchPDF`'s filter becomes `selectedIds.contains(.location($0.id))`.

- [ ] **Step 5: Commit**

```bash
git add MyStuff/Views/QRCodeSheet.swift MyStuff/Views/BatchQRPrintSheet.swift MyStuff/Views/LocationDetailView.swift
git commit -m "refactor: QR sheet and tile render a QRSubject, not a Location

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 5: `CodesSheet` — the shared codes UI

The heart of the feature. Replaces `ItemDetailSheet.nfcSection` and adds the same surface to `LocationDetailView`.

**Files:**
- Create: `MyStuff/Views/CodesSheet.swift`
- Modify: `MyStuff/Views/ItemDetailSheet.swift` (remove `nfcSection`, `pairTag`, related state; add `CodesRow`)
- Modify: `MyStuff/Views/LocationDetailView.swift` (add `CodesRow`)
- Modify: `MyStuff/ViewModels/StuffViewModel.swift` (delete the Task 2 legacy shims)

**Interfaces:**
- Consumes: `pairedTags(for:)`, `addNFCTag`, `removeNFCTag`, `renameNFCTag`, `qrSubject(for:)` (Task 2); `NFCService.write(target:allowOverwrite:)` (Task 3); `QRCodeSheet(subject:viewModel:)` (Task 4).
- Produces: `CodesRow(target:viewModel:)`, `CodesSheet(target:viewModel:)`.

- [ ] **Step 1: Create the sheet**

Create `MyStuff/Views/CodesSheet.swift`:

```swift
import SwiftUI

/// Compact summary row that opens `CodesSheet`. Style-neutral so each detail
/// screen can wrap it in its own idiom (material card vs. List row).
struct CodesRow: View {
    let target: AppLink.Target
    let viewModel: StuffViewModel

    var body: some View {
        let count = viewModel.pairedTags(for: target).count
        HStack(spacing: 8) {
            Image(systemName: "qrcode")
                .foregroundStyle(.tint)
            Text("Codes")
                .fontWeight(.medium)
            Spacer()
            Text(count == 0 ? "QR only" : "QR · \(count) tag\(count == 1 ? "" : "s")")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Every code attached to one entity: its QR sticker plus any number of
/// labelled NFC tags. Identical for items and locations — this is the single
/// place the "both kinds, many of each" rule is expressed.
struct CodesSheet: View {
    let target: AppLink.Target
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

    private var tags: [NFCTag] { viewModel.pairedTags(for: target) }

    var body: some View {
        NavigationStack {
            List {
                Section("QR Code") {
                    Button {
                        showQR = true
                    } label: {
                        Label("Show, Share & Print", systemImage: "qrcode")
                    }
                    .tint(.primary)
                } footer: {
                    Text("Every sticker for this \(kindNoun) carries the same code — print as many as you like.")
                }

                Section {
                    if tags.isEmpty {
                        Text("No NFC tags paired.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(tags) { tag in
                            Button {
                                renamingTag = tag
                                renameText = tag.label ?? ""
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(tag.displayName)
                                        .foregroundStyle(.primary)
                                    if tag.label != nil {
                                        Text(tag.uid)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    Task { await viewModel.removeNFCTag(uid: tag.uid, from: target) }
                                } label: {
                                    Label("Unpair", systemImage: "trash")
                                }
                            }
                        }
                    }

                    if nfcService.isAvailable {
                        Button {
                            pair(allowOverwrite: false)
                        } label: {
                            Label(isPairing ? "Hold near tag…" : "Pair NFC Tag", systemImage: "wave.3.right")
                        }
                        .disabled(isPairing)
                    }
                } header: {
                    Text("NFC Tags")
                } footer: {
                    Text(nfcService.isAvailable
                         ? "Tap a tag to rename it, swipe to unpair. Unpairing only removes the link in MyStuff — the sticker keeps its old code until you write to it again."
                         : "NFC is not available on this device.")
                }
            }
            .navigationTitle("Codes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showQR) {
                if let subject = viewModel.qrSubject(for: target) {
                    QRCodeSheet(subject: subject, viewModel: viewModel)
                }
            }
            .alert("Rename Tag", isPresented: Binding(
                get: { renamingTag != nil },
                set: { if !$0 { renamingTag = nil } }
            )) {
                TextField("Label", text: $renameText)
                Button("Save") {
                    if let tag = renamingTag {
                        let text = renameText
                        Task { await viewModel.renameNFCTag(uid: tag.uid, label: text, on: target) }
                    }
                    renamingTag = nil
                }
                Button("Cancel", role: .cancel) { renamingTag = nil }
            } message: {
                Text("Name this sticker so you can tell it from the others, e.g. \"front\" or \"inside lid\".")
            }
            .alert("Pair Failed", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .alert("Tag Already Paired", isPresented: Binding(
                get: { overwritePrevious != nil },
                set: { if !$0 { overwritePrevious = nil } }
            )) {
                Button("Reassign", role: .destructive) {
                    overwritePrevious = nil
                    pair(allowOverwrite: true)
                }
                Button("Cancel", role: .cancel) { overwritePrevious = nil }
            } message: {
                if let previous = overwritePrevious,
                   let name = viewModel.displayName(for: previous) {
                    Text("This tag currently points to \"\(name)\". Reassign it?")
                } else {
                    Text("This tag points to something else. Reassign it?")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var kindNoun: String {
        switch target {
        case .item: return "item"
        case .location: return "location"
        }
    }

    /// Writes the link to a physical tag, then records the serial. Reassigning
    /// strips the serial from its previous owner only — that entity's other
    /// tags stay paired.
    private func pair(allowOverwrite: Bool) {
        isPairing = true
        Task {
            do {
                let result = try await nfcService.write(target: target, allowOverwrite: allowOverwrite)
                if let previous = result.previousTarget {
                    await viewModel.removeNFCTag(uid: result.tagSerial, from: previous)
                }
                await viewModel.addNFCTag(uid: result.tagSerial, to: target)
                isPairing = false
            } catch NFCError.userCancelled {
                isPairing = false
            } catch NFCError.existingPairing(let previous, _) {
                isPairing = false
                overwritePrevious = previous
            } catch {
                isPairing = false
                errorMessage = error.localizedDescription
            }
        }
    }
}
```

- [ ] **Step 2: Swap `ItemDetailSheet` over**

In `MyStuff/Views/ItemDetailSheet.swift`:

Delete the entire `// MARK: - NFC Section` block — the `nfcSection` computed property and the `pairTag(allowOverwrite:)` method (lines ~257–326).

Delete these now-unused `@State` declarations: `nfcService`, `isPairing`, `nfcErrorMessage`, `pairOverwritePrevious`, `showUnpairConfirmation`. Also delete the `.alert("NFC Error", ...)` modifier and the `.confirmationDialog("Unpair NFC tag from ...")` modifier.

Add one new state property alongside the others:

```swift
    @State private var showCodes = false
```

Replace the `nfcSection` reference in the body's `VStack` with:

```swift
                    Button {
                        showCodes = true
                    } label: {
                        CodesRow(target: .item(item.id), viewModel: viewModel)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .tint(.primary)
```

Add the sheet presentation next to the other `.sheet` modifiers:

```swift
        .sheet(isPresented: $showCodes) {
            CodesSheet(target: .item(item.id), viewModel: viewModel)
        }
```

- [ ] **Step 3: Add the row to `LocationDetailView`**

In `MyStuff/Views/LocationDetailView.swift`, add state:

```swift
    @State private var showCodes = false
```

Add a section to the `List`, directly after the sub-locations section and before the add-actions section:

```swift
            Section {
                Button {
                    showCodes = true
                } label: {
                    CodesRow(target: .location(live.id), viewModel: viewModel)
                }
                .tint(.primary)
            }
```

Add the sheet:

```swift
        .sheet(isPresented: $showCodes) {
            CodesSheet(target: .location(live.id), viewModel: viewModel)
        }
```

Leave the existing `qrcode` toolbar button and its `showingQR` sheet in place — it is the fast path to the QR sticker, and `CodesSheet` is the manage-everything path.

- [ ] **Step 4: Delete the legacy shims**

In `MyStuff/ViewModels/StuffViewModel.swift`, delete the `// MARK: - Legacy item-only shims (removed in Task 5)` block added in Task 2 — the `item(forTagUID:)`, `clearNFCTag(itemId:)` and `setNFCTag(itemId:uid:)` methods.

- [ ] **Step 5: Build**

Run: `xcodebuild -project MyStuff.xcodeproj -scheme MyStuff -destination 'generic/platform=iOS Simulator' -configuration Debug build 2>&1 | tail -60`

Expected: `** BUILD SUCCEEDED **`. If `clearNFCTag` or `setNFCTag` is reported missing, `NFCPairSheet` still calls it — Task 8 rewrites that sheet, so for now change its `pair` method to use `addNFCTag(uid:to:)` / `removeNFCTag(uid:from:)` as shown in Task 3 Step 4.

- [ ] **Step 6: Manual check**

Run the app in the simulator. Open any item's detail — the old "NFC Tag" card is replaced by a `Codes` row reading `QR only` (or `QR · 1 tag` for an item with a legacy pairing). Tapping it opens `CodesSheet`; the QR row renders the item's sticker. Open a location's detail — the same row appears. NFC pairing itself cannot be exercised in the simulator (no NFC hardware); the button is correctly hidden there.

- [ ] **Step 7: Commit**

```bash
git add MyStuff/Views/CodesSheet.swift MyStuff/Views/ItemDetailSheet.swift MyStuff/Views/LocationDetailView.swift MyStuff/ViewModels/StuffViewModel.swift MyStuff/Views/NFCPairSheet.swift
git commit -m "feat: shared CodesSheet with multi-tag pairing for items and locations

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 6: `QRScannerSheet` resolves targets

**Files:**
- Modify: `MyStuff/Views/QRScannerView.swift:64-145`
- Modify: `MyStuff/Views/LocationsView.swift:53`
- Modify: `MyStuff/Views/NFCTabView.swift:86`
- Modify: `MyStuff/Views/ItemDetailSheet.swift:128`
- Modify: `MyStuff/Views/HomeView.swift:744`
- Modify: `MyStuff/Views/ItemsView.swift:653`

**Interfaces:**
- Consumes: `AppLink.TargetKind`, `AppLink.Target` (Task 1).
- Produces: `QRScannerSheet(accepts:onTarget:)`.

- [ ] **Step 1: Generalize the sheet**

In `MyStuff/Views/QRScannerView.swift`, replace the `QRScannerSheet` declaration line and its `onLocation` property:

```swift
struct QRScannerSheet: View {
    /// Which code kinds this scanner will resolve. Contexts like "move this
    /// item somewhere" only make sense for locations.
    var accepts: AppLink.TargetKind = .any
    let onTarget: (AppLink.Target) -> Void
```

Replace the `handle(_:)` method with:

```swift
    private func handle(_ payload: String) {
        guard let url = URL(string: payload), let target = AppLink.parse(url) else {
            errorText = "Not a MyStuff code"
            return
        }
        guard accepts.accepts(target) else {
            errorText = accepts.rejectionMessage
            return
        }
        HapticManager.success()
        onTarget(target)
        dismiss()
    }
```

Update the doc comment above the struct to say it parses via `AppLink` and calls `onTarget` for any code the `accepts` filter admits.

- [ ] **Step 2: Update the three location-only call sites**

These three are "pick a location" contexts and keep filtering. In each, add `accepts: .location` and switch the closure parameter to a target.

`MyStuff/Views/ItemDetailSheet.swift:128` — replace:

```swift
        .sheet(isPresented: $showMoveScanner) {
            QRScannerSheet { locationId in
                if viewModel.locations.contains(where: { $0.id == locationId }) {
                    performMove(toLocationId: locationId)
                } else {
                    unknownScan = true
                }
            }
        }
```

with:

```swift
        .sheet(isPresented: $showMoveScanner) {
            QRScannerSheet(accepts: .location) { target in
                let locationId = target.entityId
                if viewModel.locations.contains(where: { $0.id == locationId }) {
                    performMove(toLocationId: locationId)
                } else {
                    unknownScan = true
                }
            }
        }
```

`MyStuff/Views/HomeView.swift:744`:

```swift
                QRScannerSheet(accepts: .location) { target in
                    let locationId = target.entityId
                    if viewModel.locations.contains(where: { $0.id == locationId }) {
                        selectMove(toLocationId: locationId)
                    } else {
                        unknownScan = true
                    }
                }
```

`MyStuff/Views/ItemsView.swift:653`:

```swift
            .sheet(isPresented: $showLocationScanner) {
                QRScannerSheet(accepts: .location) { target in
                    let locationId = target.entityId
                    if viewModel.locations.contains(where: { $0.id == locationId }) {
                        selectedLocationId = locationId
                    } else {
                        unknownLocationScan = true
                    }
                }
            }
```

- [ ] **Step 3: Update `LocationsView` to accept both kinds**

`MyStuff/Views/LocationsView.swift` browses, so it accepts anything. It needs somewhere to put a scanned item, so add state next to the existing properties:

```swift
    @State private var scannedItem: Item?
```

Replace the scanner sheet:

```swift
            .sheet(isPresented: $showingScanner) {
                QRScannerSheet { target in
                    switch target {
                    case .location(let id):
                        if let loc = viewModel.locations.first(where: { $0.id == id }) {
                            path.append(loc)
                        }
                    case .item(let id):
                        scannedItem = viewModel.items.first(where: { $0.id == id })
                    }
                }
            }
            .sheet(item: $scannedItem) { item in
                NFCUpdateSheet(item: item, viewModel: viewModel)
            }
```

Use the current name `NFCUpdateSheet` here — the type is not renamed until Task 7, whose `sed` sweep rewrites this line automatically.

- [ ] **Step 4: Update `NFCTabView`'s scanner**

In `MyStuff/Views/NFCTabView.swift`, replace the scanner sheet:

```swift
            .sheet(isPresented: $showQRScanner) {
                QRScannerSheet { target in
                    handle(target: target)
                }
            }
```

`handle(target:)` arrives in Task 7. For this task, inline the existing behavior instead so the build stays green:

```swift
            .sheet(isPresented: $showQRScanner) {
                QRScannerSheet { target in
                    switch target {
                    case .location(let id):
                        if let loc = viewModel.locations.first(where: { $0.id == id }) {
                            path.append(loc)
                        }
                    case .item(let id):
                        updateItem = viewModel.items.first(where: { $0.id == id })
                    }
                }
            }
```

- [ ] **Step 5: Build**

Run: `xcodebuild -project MyStuff.xcodeproj -scheme MyStuff -destination 'generic/platform=iOS Simulator' -configuration Debug build 2>&1 | tail -60`

Expected: `** BUILD SUCCEEDED **`. Grep for `QRScannerSheet {` to confirm exactly two unfiltered call sites remain (`LocationsView`, `NFCTabView`).

- [ ] **Step 6: Commit**

```bash
git add MyStuff/Views/QRScannerView.swift MyStuff/Views/LocationsView.swift MyStuff/Views/NFCTabView.swift MyStuff/Views/ItemDetailSheet.swift MyStuff/Views/HomeView.swift MyStuff/Views/ItemsView.swift
git commit -m "feat: QR scanner resolves targets with a kind filter

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 7: Scan dispatch by entity kind + rename `NFCUpdateSheet`

**Files:**
- Rename: `MyStuff/Views/NFCUpdateSheet.swift` → `MyStuff/Views/ItemQuickUpdateSheet.swift`
- Modify: `MyStuff/Views/NFCTabView.swift`
- Modify: `MyStuff/Views/ContentView.swift:61`
- Modify: `MyStuff/Views/LocationsView.swift` (rename sweep)

**Interfaces:**
- Consumes: `NFCScanResult.target` (Task 3), `AppLink.Target` (Task 1).
- Produces: `ItemQuickUpdateSheet(item:viewModel:)`; `NFCTabView.handle(target:)`.

- [ ] **Step 1: Rename the sheet**

```bash
git mv MyStuff/Views/NFCUpdateSheet.swift MyStuff/Views/ItemQuickUpdateSheet.swift
```

In the renamed file, change `struct NFCUpdateSheet: View {` to `struct ItemQuickUpdateSheet: View {` and update the doc comment:

```swift
/// Fast re-shelving sheet, reached by scanning an item's NFC tag or QR code,
/// or by opening its universal link. Lets the user update the item's location
/// photo and current location without the full detail screen.
```

Sweep the three call sites:

```bash
grep -rln "NFCUpdateSheet" MyStuff | xargs sed -i '' 's/NFCUpdateSheet/ItemQuickUpdateSheet/g'
```

- [ ] **Step 2: Give `NFCTabView` one dispatch point**

In `MyStuff/Views/NFCTabView.swift`, replace the `handle(result:)` method with:

```swift
    private func handle(result: NFCScanResult) {
        lastScannedSerial = result.tagSerial
        guard let target = result.target else {
            // Blank/unknown tag → open pair flow
            HapticManager.impact()
            showPairSheet = true
            return
        }
        handle(target: target)
    }

    /// One dispatch point for both code kinds. What happens depends on the
    /// entity, not on whether it was scanned by NFC or camera: items open the
    /// quick re-shelve sheet, locations open their detail screen.
    private func handle(target: AppLink.Target) {
        switch target {
        case .item(let id):
            if let item = viewModel.items.first(where: { $0.id == id }) {
                HapticManager.success()
                updateItem = item
            } else {
                lastUnknownTarget = target
                errorMessage = "This tag is paired to an item that no longer exists. Would you like to pair it to something else?"
            }
        case .location(let id):
            if let location = viewModel.locations.first(where: { $0.id == id }) {
                HapticManager.success()
                path.append(location)
            } else {
                lastUnknownTarget = target
                errorMessage = "This tag is paired to a location that no longer exists. Would you like to pair it to something else?"
            }
        }
    }
```

Replace the `lastUnknownItemId` state declaration with:

```swift
    @State private var lastUnknownTarget: AppLink.Target?
```

and update the two references inside the `.alert("Scan Issue", ...)` modifier — `lastUnknownItemId != nil` becomes `lastUnknownTarget != nil`, and both `lastUnknownItemId = nil` assignments become `lastUnknownTarget = nil`.

Replace the QR scanner sheet body from Task 6 Step 4 with the now-available dispatch:

```swift
            .sheet(isPresented: $showQRScanner) {
                QRScannerSheet { target in
                    handle(target: target)
                }
            }
```

- [ ] **Step 3: Update the subhead copy**

The tab now handles both kinds. In `NFCTabView`, replace the `subhead` return:

```swift
        return "Press Scan Tag, then tap your phone onto a paired NFC sticker to update its location and photo."
```

with:

```swift
        return "Scan a tag or QR code. Item codes open a quick update; location codes open that location."
```

- [ ] **Step 4: Build**

Run: `xcodebuild -project MyStuff.xcodeproj -scheme MyStuff -destination 'generic/platform=iOS Simulator' -configuration Debug build 2>&1 | tail -60`

Expected: `** BUILD SUCCEEDED **`. Confirm the rename took: `grep -rn "NFCUpdateSheet" MyStuff` returns nothing.

- [ ] **Step 5: Manual check**

In the simulator, open the Locations tab, tap the scanner button, and point the camera at a printed or on-screen location QR — it should push that location's detail. Scan an item QR — the quick update sheet should present. (Generate a test QR by opening any entity's `Codes` sheet on a second device or by rendering the URL through an online generator.)

- [ ] **Step 6: Commit**

```bash
git add -A MyStuff/Views
git commit -m "feat: scan dispatch keyed on entity kind; rename NFCUpdateSheet

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 8: `NFCPairSheet` pairs to items or locations

**Files:**
- Modify: `MyStuff/Views/NFCPairSheet.swift`

**Interfaces:**
- Consumes: `NFCService.write(target:allowOverwrite:)` (Task 3); `addNFCTag`, `removeNFCTag`, `displayName(for:)`, `pairedTags(for:)` (Task 2).

- [ ] **Step 1: Rewrite the sheet**

Replace the whole of `MyStuff/Views/NFCPairSheet.swift` with:

```swift
import SwiftUI

/// Target picker shown when a blank or unrecognized NFC tag is scanned on the
/// NFC tab. Lets the user pair the tag to any item or location.
struct NFCPairSheet: View {
    @Bindable var viewModel: StuffViewModel
    let nfcService: NFCService
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var isPairing = false
    @State private var errorMessage: String?
    @State private var overwriteCandidate: (target: AppLink.Target, previous: AppLink.Target)?

    var body: some View {
        NavigationStack {
            Group {
                if filteredItems.isEmpty && filteredLocations.isEmpty {
                    ContentUnavailableView("Nothing to pair", systemImage: "shippingbox")
                } else {
                    List {
                        if !filteredItems.isEmpty {
                            Section("Items") {
                                ForEach(filteredItems) { item in
                                    row(
                                        target: .item(item.id),
                                        title: item.name,
                                        subtitle: viewModel.location(for: item).map { viewModel.displayPath(for: $0) }
                                    )
                                }
                            }
                        }
                        if !filteredLocations.isEmpty {
                            Section("Locations") {
                                ForEach(filteredLocations, id: \.id) { location in
                                    row(
                                        target: .location(location.id),
                                        title: (location.emoji ?? "📍") + " " + location.name,
                                        subtitle: viewModel.displayPath(for: location)
                                    )
                                }
                            }
                        }
                    }
                    .searchable(text: $searchText, prompt: "Search items and locations...")
                }
            }
            .navigationTitle("Pair Tag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isPairing)
                }
            }
            .overlay {
                if isPairing {
                    Color.black.opacity(0.1)
                        .ignoresSafeArea()
                        .overlay { ProgressView("Hold near tag...") }
                }
            }
            .alert("Pair Failed", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .alert("Tag Already Paired", isPresented: Binding(
                get: { overwriteCandidate != nil },
                set: { if !$0 { overwriteCandidate = nil } }
            )) {
                Button("Reassign", role: .destructive) {
                    if let candidate = overwriteCandidate {
                        overwriteCandidate = nil
                        pair(to: candidate.target, allowOverwrite: true)
                    }
                }
                Button("Cancel", role: .cancel) { overwriteCandidate = nil }
            } message: {
                if let candidate = overwriteCandidate,
                   let previousName = viewModel.displayName(for: candidate.previous),
                   let newName = viewModel.displayName(for: candidate.target) {
                    Text("This tag is already paired to \"\(previousName)\". Reassign to \"\(newName)\"?")
                } else {
                    Text("This tag is already paired to something else. Reassign?")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// One selectable row. The trailing count replaces the old binary
    /// paired/unpaired glyph, since an entity may now hold several tags.
    @ViewBuilder
    private func row(target: AppLink.Target, title: String, subtitle: String?) -> some View {
        let count = viewModel.pairedTags(for: target).count
        Button {
            pair(to: target)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.body)
                        .foregroundStyle(.primary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if count > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "wave.3.right")
                        Text("\(count)")
                    }
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isPairing)
    }

    private var filteredItems: [Item] {
        let sorted = viewModel.items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        guard !searchText.isEmpty else { return sorted }
        return sorted.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var filteredLocations: [Location] {
        let sorted = viewModel.locations.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        guard !searchText.isEmpty else { return sorted }
        return sorted.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private func pair(to target: AppLink.Target, allowOverwrite: Bool = false) {
        isPairing = true
        Task {
            do {
                let result = try await nfcService.write(target: target, allowOverwrite: allowOverwrite)
                if let previous = result.previousTarget {
                    await viewModel.removeNFCTag(uid: result.tagSerial, from: previous)
                }
                await viewModel.addNFCTag(uid: result.tagSerial, to: target)
                isPairing = false
                dismiss()
            } catch NFCError.userCancelled {
                isPairing = false
            } catch NFCError.existingPairing(let previous, _) {
                isPairing = false
                overwriteCandidate = (target, previous)
            } catch {
                isPairing = false
                errorMessage = error.localizedDescription
            }
        }
    }
}
```

- [ ] **Step 2: Build**

Run: `xcodebuild -project MyStuff.xcodeproj -scheme MyStuff -destination 'generic/platform=iOS Simulator' -configuration Debug build 2>&1 | tail -60`

Expected: `** BUILD SUCCEEDED **`. If `displayPath(for:)` is reported missing for a `Location`, check its actual signature in `StuffViewModel` and match it.

- [ ] **Step 3: Commit**

```bash
git add MyStuff/Views/NFCPairSheet.swift
git commit -m "feat: pair a blank tag to an item or a location

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 9: `NFCBadge` on locations, badge predicate switch

**Files:**
- Modify: `MyStuff/Views/HomeView.swift:570`
- Modify: `MyStuff/Views/ItemsView.swift:179`
- Modify: `MyStuff/Views/ItemGalleryGrid.swift:118`
- Modify: `MyStuff/Views/LocationsView.swift`

**Interfaces:**
- Consumes: `Item.pairedTags`, `Location.pairedTags` (Task 1).

- [ ] **Step 1: Switch the three item predicates**

The legacy check misses entities whose tags live in the new array. In `HomeView.swift:570`, `ItemsView.swift:179` and `ItemGalleryGrid.swift:118`, replace:

```swift
                if item.nfcTagUID != nil {
```

with:

```swift
                if !item.pairedTags.isEmpty {
```

Match each file's existing indentation.

- [ ] **Step 2: Badge location rows**

In `MyStuff/Views/LocationsView.swift`, inside `locationsList`, the row label `HStack` currently reads:

```swift
                            if viewModel.isSharedWithMe(entry.location) {
                                SharedBadge(iconOnly: true, ownerName: viewModel.friend(forUid: entry.location.ownerId ?? "")?.displayName)
                            } else if viewModel.isShared(entry.location) {
                                SharedBadge(iconOnly: true)
                            }
                            Spacer()
```

Insert the NFC badge between the shared badges and the `Spacer()`:

```swift
                            if viewModel.isSharedWithMe(entry.location) {
                                SharedBadge(iconOnly: true, ownerName: viewModel.friend(forUid: entry.location.ownerId ?? "")?.displayName)
                            } else if viewModel.isShared(entry.location) {
                                SharedBadge(iconOnly: true)
                            }
                            if !entry.location.pairedTags.isEmpty {
                                NFCBadge(iconOnly: true)
                            }
                            Spacer()
```

- [ ] **Step 3: Build**

Run: `xcodebuild -project MyStuff.xcodeproj -scheme MyStuff -destination 'generic/platform=iOS Simulator' -configuration Debug build 2>&1 | tail -60`

Expected: `** BUILD SUCCEEDED **`. Then confirm no legacy reads remain outside the model: `grep -rn "nfcTagUID" MyStuff` should only hit `MyStuff/Models/Item.swift` (the field, the init parameter, the assignment, the `pairedTags` fallback) and `StuffViewModel.writeTags`.

- [ ] **Step 4: Commit**

```bash
git add MyStuff/Views/HomeView.swift MyStuff/Views/ItemsView.swift MyStuff/Views/ItemGalleryGrid.swift MyStuff/Views/LocationsView.swift
git commit -m "feat: NFC badge on location rows; read tags via pairedTags

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 10: Batch print covers items and locations

**Files:**
- Modify: `MyStuff/Views/BatchQRPrintSheet.swift:109-250`

**Interfaces:**
- Consumes: `QRSubject`, `qrSubject(for:)` (Task 2); `QRTileView(subject:...)` (Task 4).

> **Amended after review:** the code blocks below put a single global Select All in the Locations header, which would render the whole item inventory from a control labelled "Locations". Spec §7 requires each section to carry its own Select All, scoped to its own targets. As shipped: `locationTargets` / `itemTargets` feed a shared `sectionHeader(_:group:)`, `allSelected(in:)` uses set containment rather than a global count comparison (a stale selected id plus a deleted entity makes counts lie), and `selectedIds` is named `selectedTargets` since it holds `AppLink.Target`s. `allTargets` survives only as the PDF ordering source.

- [ ] **Step 1: Rebuild the selection over subjects**

In `MyStuff/Views/BatchQRPrintSheet.swift`, replace the `entries` / `allSelected` / selection plumbing. Add these computed properties, replacing `entries`:

```swift
    /// Locations in tree order, paired with their indent depth.
    private var locationEntries: [(location: Location, depth: Int)] {
        viewModel.flattenedLocationTree()
    }

    private var itemEntries: [Item] {
        viewModel.items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var allTargets: [AppLink.Target] {
        locationEntries.map { .location($0.location.id) } + itemEntries.map { .item($0.id) }
    }

    private var allSelected: Bool {
        !allTargets.isEmpty && selectedIds.count == allTargets.count
    }
```

Replace `pageCount`'s and `summary`'s references to `selectedIds.count` — they already read the count, so no change is needed there.

- [ ] **Step 2: Render both sections**

Replace the single `Section { ForEach(entries) ... } header: { ... }` block with:

```swift
                Section {
                    ForEach(locationEntries, id: \.location.id) { entry in
                        selectRow(
                            target: .location(entry.location.id),
                            icon: entry.location.emoji ?? "📍",
                            name: entry.location.name,
                            indent: CGFloat(entry.depth) * 16
                        )
                    }
                } header: {
                    HStack {
                        Text("Locations")
                        Spacer()
                        Button(allSelected ? "Clear" : "Select All") { toggleAll() }
                            .font(.caption)
                            .textCase(nil)
                    }
                }

                Section("Items") {
                    ForEach(itemEntries) { item in
                        selectRow(target: .item(item.id), icon: "📦", name: item.name, indent: 0)
                    }
                }
```

Add the shared row builder next to the other private methods:

```swift
    @ViewBuilder
    private func selectRow(target: AppLink.Target, icon: String, name: String, indent: CGFloat) -> some View {
        Button {
            toggle(target)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: selectedIds.contains(target) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selectedIds.contains(target) ? Color.appAccent : .secondary)
                Text(icon)
                Text(name)
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.leading, indent)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
```

- [ ] **Step 3: Update toggles and PDF generation**

```swift
    private func toggle(_ target: AppLink.Target) {
        if selectedIds.contains(target) { selectedIds.remove(target) } else { selectedIds.insert(target) }
    }

    private func toggleAll() {
        selectedIds = allSelected ? [] : Set(allTargets)
    }

    /// Renders every selected target's tile and packs them into an A4 PDF.
    /// Order follows `allTargets` so locations lead and items follow.
    @MainActor
    private func makeBatchPDF() -> Data? {
        let subjects = allTargets
            .filter { selectedIds.contains($0) }
            .compactMap { viewModel.qrSubject(for: $0) }
        let tiles: [UIImage] = subjects.compactMap { subject in
            guard let qr = QRCodeGenerator.image(for: subject.urlString) else { return nil }
            let renderer = ImageRenderer(
                content: QRTileView(subject: subject, qrImage: qr, size: size, showIcon: showIcon, showName: showName)
            )
            renderer.scale = 3
            return renderer.uiImage
        }
        guard !tiles.isEmpty else { return nil }
        return QRSheetPDF.makePDF(tiles: tiles, cell: size.cell(hasCaption: hasCaption))
    }
```

Update the two job/file names, which no longer describe locations only:

```swift
        PDFPrinter.print(data, jobName: "MyStuff QR codes")
```

```swift
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mystuff-qr-codes.pdf")
```

Update `summary`'s empty case to `"Select items or locations to print."`.

- [ ] **Step 4: Build**

Run: `xcodebuild -project MyStuff.xcodeproj -scheme MyStuff -destination 'generic/platform=iOS Simulator' -configuration Debug build 2>&1 | tail -60`

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Manual check**

In the simulator, open a location's `Codes` sheet → QR → "Print Multiple…". The sheet should show a Locations section (indented tree, pre-selected with the location you came from) and an Items section. Select one of each, tap the share button, and confirm the generated PDF contains both tiles with correct captions (📍 for the location, 📦 for the item).

- [ ] **Step 6: Commit**

```bash
git add MyStuff/Views/BatchQRPrintSheet.swift
git commit -m "feat: batch QR print covers items and locations together

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Final Verification

After Task 10, run the full manual pass from the spec on a physical device (NFC needs real hardware — the simulator can only exercise QR):

1. An item with a legacy `nfcTagUID` shows that tag in `CodesSheet`; pairing a second leaves both listed. Inspect the Firestore document and confirm `nfcTags` holds both entries. `nfcTagUID` will still hold its old value — merge writes omit nil optionals — which is expected and inert, since `pairedTags` ignores it once `nfcTags` is non-nil. Also unpair every tag from such an item and confirm the legacy serial does not reappear after the listener refreshes.
2. A location accepts two tags; scanning either opens location detail.
3. Scanning an item QR opens the quick-update sheet; scanning a location QR opens location detail.
4. The item-move scanner rejects an item QR with "That's not a location code" and keeps scanning.
5. Batch print with a mixed selection produces one PDF with all tiles.
6. Reassigning a tag from entity A to entity B removes only that serial from A; A's other tags stay paired.
7. Renaming a tag persists the label; clearing the field falls back to the abbreviated serial.
8. Swipe-to-delete removes one tag row without disturbing its siblings.
