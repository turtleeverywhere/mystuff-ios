# Item Recognition Scan

Date: 2026-10-10
Status: Approved

## Problem

The database goes stale because updating an item's location is slower than moving the
item. Existing bulk move (`MoveItemsHereSheet`) still needs one search or one code scan
per item, and most items carry no QR/NFC tag.

## Solution overview

A camera-driven **scan session**: pick a destination location (NFC, QR, or manual),
point the camera at items one at a time and tap the shutter, let the app recognize each
against known items, then confirm one review list that batch-moves everything.

Recognition uses on-device image embeddings (Apple Vision feature print) and a
nearest-neighbour lookup — no trained classifier, no network. Locations are never
recognized by ML; they come from tags or the manual picker.

Success: moving ten untagged items to a shelf takes ten shutter taps plus one confirm,
with no typing, fully offline.

## Decisions

| Topic | Decision |
|---|---|
| Capture | Tap per item (one shutter tap = one item) |
| Reference images | Existing item photo + learned from confirmed scans + optional manual "add angles" |
| Model | Apple Vision feature print, behind a protocol |
| No match | Pick an existing item or create a new one |
| Reference storage | On-device only, per signed-in uid. No Firestore schema or rules change |
| Tests | New unit test target for the pure logic |
| Entry points | Location detail, NFC/QR tab, Home toolbar |

## Out of scope

Live auto-detect panning, whole-shelf photo segmentation, MobileCLIP / text search,
vision-LLM prefill of new items, syncing references across devices, ML location
recognition, reporting items that were expected at the location but not scanned.

## Definitions

- **Reference** — one embedding vector plus a small thumbnail, attached to an item.
- **Source** — where a reference came from:
  - `itemPhoto` — derived from the item's item photo (`itemPhotoURL` /
    `remoteItemPhotoURL`). At most one per item. Never the location photo (`photoURL`).
  - `enrolled` — captured by the user through "Add angles".
  - `learned` — a scan capture the user confirmed for that item.
- **Capture** — one shutter tap in a scan session: thumbnail, vector, ranked candidates,
  and a resolution.
- **Tray** — the session's set of resolved items, unique by item id.

## Recognition

### Embedding

`MyStuff/Services/ImageEmbedder.swift`

```swift
protocol ImageEmbedder: Sendable {
    /// Identifies model + revision. Vectors are only comparable within one modelID.
    var modelID: String { get }
    /// `imageData` is an encoded image; EXIF orientation is honoured.
    func embed(imageData: Data) async throws -> Embedding
}

struct Embedding: Sendable {
    let vector: [Float]
    /// JPEG of the crop actually embedded, at most 320 px.
    let thumbnail: Data
}
```

`VisionFeaturePrintEmbedder` (Swift Vision API):

1. `GenerateForegroundInstanceMaskRequest` on the image. Choose the instance under the
   image centre (`instanceAtPoint`), else all instances. If any, produce
   `generateMaskedImage(for:imageFrom:croppedToInstancesExtent: true)` — background
   removed, cropped to the subject.
2. No subject found: fall back to the centre square (70 % of the short side).
3. `GenerateImageFeaturePrintRequest` on the result; read `FeaturePrintObservation.data`
   as `[Float]`.

The same pipeline runs for references and for scan captures, so shelf backgrounds do
not dominate the vector. `modelID` is `"vision-featureprint-r<revision>"`.

### Storage

`MyStuff/Services/RecognitionStore.swift` — `@MainActor @Observable final class`.

```swift
struct ItemReference: Codable, Identifiable, Sendable {
    enum Source: String, Codable, Sendable { case itemPhoto, enrolled, learned }
    var id: String
    var itemId: String
    var source: Source
    var modelID: String
    /// Raw Float32 bytes on disk.
    var vector: [Float]
    /// itemPhoto only: `remoteItemPhotoURL ?? itemPhotoURL` at embed time, to detect a changed photo.
    var sourceKey: String?
    var createdAt: Date
}
```

On disk under `Application Support/Recognition/<uid>/`: one binary plist per reference
(`<refId>.plist`) and one 320 px JPEG thumbnail (`<refId>.jpg`). Loaded when the store
is first used. Scoped by uid so switching accounts neither mixes nor deletes references. The
directory stays in device backups — enrolled and learned references are not
rebuildable.

API:

```swift
func references(for itemId: String) -> [ItemReference]
func thumbnailURL(for reference: ItemReference) -> URL
func add(_ embedding: Embedding, to itemId: String, source: ItemReference.Source, sourceKey: String? = nil)
func remove(_ reference: ItemReference)
func removeAll(itemId: String)
/// Ensures every item with an item photo has a current `itemPhoto` reference. Reports progress.
func syncItemPhotos(for items: [Item]) async
var syncProgress: (done: Int, total: Int)?
```

Rules:

- **Cap** 8 references per item. `itemPhoto` is always kept. `enrolled` is kept until
  the user deletes it (max 5; "Add angles" disables at 5). `learned` fills the rest,
  oldest evicted first.
- **Dedupe** a `learned` reference is dropped if it lies within 0.15 of an existing
  reference of the same item.
- **Model change** references whose `modelID` differs from the active embedder are
  ignored by matching and re-embedded from their thumbnail during `syncItemPhotos`.
- **Item photo sync** for each item with an item photo, (re)create the `itemPhoto`
  reference when missing or when `sourceKey` no longer matches. The image is resolved
  the way `PhotoView` resolves it: local file first, else remote via `ImageCache`.
  Photos that are remote-only while offline are skipped and retried next sync. Items
  whose item photo was removed lose their `itemPhoto` reference.

`StuffViewModel` hooks: `setItemPhoto` and `deleteItemPhoto` refresh that item's
`itemPhoto` reference (the local path is unchanged when a photo is replaced, so
`sourceKey` alone cannot detect it); `deleteItem` calls `removeAll(itemId:)`.

### Matching

`MyStuff/Services/ItemMatcher.swift` — pure, no I/O.

```swift
struct ItemMatch: Sendable, Equatable { let itemId: String; let distance: Float }

enum MatchOutcome: Sendable, Equatable {
    case confident(ItemMatch, alternatives: [ItemMatch])
    case ambiguous([ItemMatch])   // best first, max 3
    case noMatch([ItemMatch])     // nearest guesses still offered, max 3
}

enum ItemMatcher {
    static let acceptDistance: Float = 0.55
    static let acceptMargin: Float = 0.08
    static let rejectDistance: Float = 0.90

    static func rank(_ query: [Float], references: [ItemReference], knownItemIds: Set<String>, modelID: String) -> [ItemMatch]
    static func classify(_ ranked: [ItemMatch]) -> MatchOutcome
}
```

- Distance is Euclidean over the Float vectors (what `FeaturePrintObservation.distance`
  computes), via Accelerate.
- An item's distance is the minimum over its references. References for unknown items
  or another `modelID` are skipped.
- `confident`: best ≤ `acceptDistance` **and** runner-up item is at least `acceptMargin`
  farther (or there is no runner-up).
- `noMatch`: best > `rejectDistance`, or no references at all.
- Otherwise `ambiguous`.

The three constants are starting estimates, not measured values. They live in one
place and a DEBUG-only readout shows distances on the match card for tuning on a real
device. Wrong thresholds cost one extra tap; they cannot cause a silent wrong move,
because nothing is written before the review sheet.

## Scan session

### State

`MyStuff/ViewModels/ScanSessionModel.swift` — `@MainActor @Observable final class`,
constructed with an `ImageEmbedder`, the `RecognitionStore`, and an
`items: @MainActor () -> [Item]` provider. It does not hold `StuffViewModel` (which
hardcodes the Firebase service), so it is unit-testable; the views perform Firestore
writes through `StuffViewModel` and report the result back to the session.

```swift
struct Capture: Identifiable {
    enum Resolution { case pending, item(String) }
    enum Origin { case camera, code, created }
    let id: UUID
    var thumbnail: UIImage?
    var embedding: Embedding?      // nil for code scans
    var candidates: [ItemMatch]
    var resolution: Resolution
    var origin: Origin
    var wasAutoAccepted: Bool
}
```

- `destination: Location?`
- `captures: [Capture]`
- `tray: [Item]` — derived: resolved item ids, unique, in first-seen order.
- `pendingCapture: Capture?` — the capture currently needing a decision.
- `isProcessing: Bool` — shutter disabled while embedding.

Operations: `capture(_ image: UIImage)`, `resolve(_ captureId:to:origin:)`,
`discard(_ captureId:)`, `removeFromTray(_ itemId:)`, `handle(_ target: AppLink.Target)`,
`saveLearnedReferences(selected: Set<String>)`.

### Screen

`MyStuff/Views/Scan/ItemScanView.swift`, presented as `fullScreenCover`.

- **Destination bar** (top, glass). Shows the destination's emoji + name, or "Choose
  location". Tapping opens a sheet with `LocationTreeSections` and an `NFCScanButton`.
  A location QR seen by the viewfinder sets the destination directly.
- **Viewfinder** — `ScanCaptureStage`: the existing `QRScannerView`
  (`DataScannerViewController`) extended with a `ScanCameraController` that exposes
  `capturePhoto()`, plus reticle and shutter.
- **Shutter** → `capture`. Outcome:
  - `confident` → capture resolved to the match, added to the tray, success haptic.
  - `ambiguous` / `noMatch` → `ScanMatchCard` slides up.
- **`ScanMatchCard`** — captured thumbnail; up to three candidate rows (thumbnail,
  name, current location); "Other…" (searchable list of all items); "New item";
  "Discard". DEBUG builds also show each candidate's distance.
- **Tray** — horizontal strip of resolved items above the shutter. Tapping a chip
  reopens the card for its latest capture (reassign) or removes the item.
- **Review (n)** button → `ScanReviewSheet`. Disabled while the tray is empty.
- **Cancel** — asks to confirm when the tray is non-empty.

Codes inside the session (viewfinder QR, or the NFC button):

- item code → added to the tray with `origin: .code`, no embedding. This is the path
  for near-identical items.
- location code → sets `destination`.
- unknown / foreign code → inline message, same as `QRScannerSheet`.

**New item** — a name prompt, then the view calls `viewModel.addItem` (location =
current destination, or none) and `viewModel.setItemPhoto` with the captured image,
then resolves the capture to the new id with `origin: .created`. Creation is immediate and is not undone by cancelling the
session.

**Unsupported camera** (simulator, old hardware): the viewfinder is replaced by a
`PhotosPicker` button feeding the same `capture` path. Camera permission denied: the
same "Open Settings" state `QRScannerSheet` uses.

### Review and commit

`MyStuff/Views/Scan/ScanReviewSheet.swift`

- Requires a destination; if none, the sheet leads with the destination picker.
- One row per tray item: name, `current location → destination`, a checkmark toggle
  (default on).
- Items already directly in the destination show "Already here" and are not moved.
- **Confirm**:
  1. Move the selected items with the same destination auto-sharing that
     `MoveItemsHereSheet.confirmMove` performs today. That logic is extracted into
     `StuffViewModel.moveItemsSharingDestination(_:to:)` and both screens call it.
  2. `session.saveLearnedReferences(selected:)`: for every capture that has an
     embedding and resolves to a selected item (moved or "already here"), add a
     `learned` reference. Captures the user deselected or
     discarded teach nothing.
  3. Dismiss.

Nothing is written to Firestore before Confirm, except new items the user explicitly
created.

## Enrollment

`MyStuff/Views/Scan/RecognitionPhotosSection.swift`, added to `ItemDetailSheet`.

- Horizontal strip of the item's reference thumbnails. `enrolled` and `learned`
  references can be deleted from a context menu; the `itemPhoto` reference follows the
  item photo and has no delete.
- "Add angles" opens `ScanCaptureStage` in multi-shot mode: each shutter tap embeds and
  stores an `enrolled` reference, with an `n/5` counter and Done.
- Empty state explains that scanning learns the item automatically.

## Entry points

- `LocationDetailView` — "Scan items here", next to "Move items here". Destination
  preset.
- `NFCTabView` — "Scan Items" button under the existing two.
- `HomeView` — toolbar button (`camera.viewfinder`).

Opening a session kicks off `syncItemPhotos`; the screen is usable immediately and
shows "Preparing recognition n/m" while the backfill runs.

## Files

New:

- `MyStuff/Services/ImageEmbedder.swift`
- `MyStuff/Services/RecognitionStore.swift`
- `MyStuff/Services/ItemMatcher.swift`
- `MyStuff/ViewModels/ScanSessionModel.swift`
- `MyStuff/Views/Scan/ItemScanView.swift`
- `MyStuff/Views/Scan/ScanCaptureStage.swift`
- `MyStuff/Services/ItemPhotoLoader.swift`
- `MyStuff/Models/ItemReference.swift`
- `MyStuff/Views/Scan/ScanMatchCard.swift`
- `MyStuff/Views/Scan/ScanReviewSheet.swift`
- `MyStuff/Views/Scan/RecognitionPhotosSection.swift`
- `MyStuffTests/` — new unit test target (Swift Testing, `@testable import MyStuff`)

Changed:

- `StuffViewModel.swift` — `moveItemsSharingDestination`, `moveItems` returns `Bool`,
  reference hooks.
- `QRScannerView.swift` — optional `ScanCameraController`.
- `MoveItemsHereSheet.swift` — call the extracted helper.
- `LocationDetailView.swift`, `NFCTabView.swift`, `HomeView.swift` — entry points.
- `ItemDetailSheet.swift` — recognition photos section.
- `Info.plist` — camera usage string mentions recognizing items.
- `MyStuff.xcodeproj/project.pbxproj` — test target.

## Error handling

- Embedding failure → inline "Couldn't read that photo", capture dropped, session
  continues.
- Reference file write failure → reference skipped; matching keeps working from memory.
- Move failure → existing `viewModel.errorMessage` path; the session stays open so
  nothing captured is lost.
- Item deleted elsewhere mid-session (live sync) → dropped from the tray on review.

## Testing

Unit tests (new target):

- `ItemMatcher` — min-over-references, ordering, each `classify` branch at and around
  the thresholds, margin with and without a runner-up, unknown item ids and foreign
  `modelID` skipped, empty input.
- `RecognitionStore` (temp directory, fake embedder) — persist/reload round trip, cap
  and eviction order, learned dedupe, `removeAll`, `sourceKey` refresh, uid scoping.
- `ScanSessionModel` (fake embedder) — tray uniqueness, auto-accept vs pending,
  reassign, discard, code handling for item vs location targets.

Build check with the standard `xcodebuild` command. Simulator walk-through using the
photo-library fallback.

Manual on device (cannot be automated): camera capture, QR inside the session, NFC
destination, threshold tuning with the DEBUG distance readout.

## Risks

- Threshold values are unverified until tried on real items.
- Feature print is a general-purpose embedding; visually similar items will land in
  `ambiguous`. Item QR/NFC inside the session is the designed fallback.
- Subject masking can pick the wrong object on a cluttered shelf. The reticle and the
  centre-instance preference mitigate it; holding the item apart is the user-side fix.
- References are device-local: a second device starts from item photos only.
