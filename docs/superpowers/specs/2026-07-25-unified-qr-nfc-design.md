# Unified QR + NFC for Items and Locations

**Date:** 2026-07-25
**Status:** Approved

## Problem

QR codes and NFC tags are split by entity type:

| Capability | Locations | Items |
|---|---|---|
| QR generate / print / share | ✅ `QRCodeSheet` | ❌ |
| QR batch print | ✅ `BatchQRPrintSheet` | ❌ |
| QR scan | ✅ navigates to detail | ❌ rejected as "not a location code" |
| NFC pair | ❌ | ✅ one tag maximum |
| NFC scan | ❌ | ✅ opens quick-update sheet |
| NFC badge in lists | ❌ | ✅ |

Two goals:

1. Every entity supports both code kinds through the same UI.
2. An entity may carry many codes, not one.

## Key Constraint

A QR code's payload is derived from the entity id — `https://mystuff.coding-turtle.org/{item,location}/<uuid>`. Nothing is persisted. Every sticker printed for a given entity is byte-identical, so "many QR codes per entity" already works and needs no model change.

NFC is the asymmetric case: `Item.nfcTagUID: String?` stores exactly one serial, and `Location` has no field at all. **Multiplicity work therefore lands entirely on NFC.**

## Design

### 1. `AppLink.Target` is the currency

`Target` gains `Hashable` and `Identifiable` (`id` = `"item:<uuid>"` / `"location:<uuid>"`). Every QR/NFC API keys on `Target` rather than a bare id plus an implied type. QR and NFC encode the same URL, so one type covers both.

### 2. Model — NFC becomes a list of labelled tags on both entities

A tag is a serial plus a user-editable label, so a shelf carrying three stickers can distinguish them ("front", "inside lid", "back"):

```swift
struct NFCTag: Codable, Hashable, Sendable, Identifiable {
    var uid: String        // hex serial, stable identity
    var label: String?     // user-editable, nil until named
    var id: String { uid }
}
```

`Item` and `Location` each gain `var nfcTags: [NFCTag]?`, with a non-optional accessor following the existing `members` idiom:

```swift
var pairedTags: [NFCTag] {
    if let nfcTags, !nfcTags.isEmpty { return nfcTags }
    if let nfcTagUID { return [NFCTag(uid: nfcTagUID)] }   // Item only — legacy
    return []
}
```

`Item.nfcTagUID` is retained so existing documents decode. The first write that touches tags migrates the legacy serial into `nfcTags` and sets `nfcTagUID` to nil. Optionality matches `ownerId` / `memberIds`, so documents written before this change decode cleanly. Firestore stores the array as maps, which its `Codable` mapping handles without extra work.

`Location` has no legacy field, so its accessor omits the singleton branch.

Labels are display-only — nothing is written to the physical tag, whose NDEF payload remains just the universal link.

### 3. `NFCService` generalized

```swift
struct NFCScanResult: Sendable {
    let target: AppLink.Target?
    let previousTarget: AppLink.Target?
    let tagSerial: String
}

protocol NFCService: AnyObject, Sendable {
    var isAvailable: Bool { get }
    func scan() async throws -> NFCScanResult
    func write(target: AppLink.Target, allowOverwrite: Bool) async throws -> NFCScanResult
}
```

`NFCError.existingPairing` carries a `Target`. `NFCLink` folds into `AppLink` — the URL shape already lives there, and the item-only helpers no longer make sense. `CoreNFCService.extractItemId` becomes `extractTarget`, parsing via `AppLink.parse`. `MockNFCService` mirrors the shape.

### 4. `StuffViewModel` — one tag API over both types

```swift
func pairedTags(for target: AppLink.Target) -> [NFCTag]
func target(forTagUID uid: String) -> AppLink.Target?
func addNFCTag(uid: String, to target: AppLink.Target) async
func removeNFCTag(uid: String, from target: AppLink.Target) async
func renameNFCTag(uid: String, label: String?, on target: AppLink.Target) async
func displayName(for target: AppLink.Target) -> String?
```

`addNFCTag` **appends** and de-duplicates by `uid`; it never replaces. This is what makes many-tags-per-entity real. Reassigning a tag away from a previous owner calls `removeNFCTag` on that owner first, removing only the one serial and leaving its siblings intact. `renameNFCTag` with a blank string stores nil rather than an empty label.

The existing `item(forTagUID:)`, `clearNFCTag(itemId:)` and `setNFCTag(itemId:uid:)` are replaced by the above. Tag writes route through the existing `updateItem` / `updateLocation` so sharing, batching and haptics behave as they already do.

### 5. `CodesSheet` — the shared UI component

Swipe-to-delete requires a `List`. `LocationDetailView` is one, but `ItemDetailSheet` is a `ScrollView` of `ultraThinMaterial` cards, so an inline section cannot support swipe in both places. Instead both screens show a single **`CodesRow`** — `"Codes · 2 tags ›"` — that presents a shared `CodesSheet`. This also keeps detail screens from growing unbounded as tags accumulate.

`CodesSheet` is a `List` over one `AppLink.Target`:

- **QR section** — a tappable row opening `QRCodeSheet` for this target.
- **Tags section** — one row per paired tag showing its label, or the abbreviated serial when unnamed, with the full serial as secondary text. Swipe-to-delete unpairs. Tapping a row opens a rename alert with a `TextField`.
- **"Pair NFC Tag"** button, always additive, hidden when NFC is unavailable on the device.

This replaces the bespoke `nfcSection` in `ItemDetailSheet` and is new to `LocationDetailView`. It is the single place where "both kinds, many of each" is expressed, so the two detail screens cannot drift apart again.

Unpairing only clears the app-side record; it does not blank the physical tag, which still carries the old link until rewritten. The delete confirmation says so.

### 6. `QRCodeSheet` / `QRTileView` take a subject

```swift
struct QRSubject: Identifiable, Hashable {
    let target: AppLink.Target
    let name: String
    let icon: String
}
```

Locations supply `emoji ?? "📍"`. Items have no emoji field — nor does `Category` — so items use `📦`. Filename generation in `writeTemp` uses the subject name and target id.

### 7. `BatchQRPrintSheet` covers both

A Locations section (existing indented tree) and an Items section, each with its own Select All. Selection becomes `Set<AppLink.Target>`. Tiles from both kinds pack onto the same A4 sheets; existing size and caption controls are unchanged.

### 8. `QRScannerSheet` resolves targets

```swift
extension AppLink {
    enum TargetKind { case any, item, location }
}

QRScannerSheet(accepts: AppLink.TargetKind = .any, onTarget: (AppLink.Target) -> Void)
```

`accepts` filters what the scanner will resolve; a rejected kind keeps the existing inline-message-and-keep-scanning behavior. Call sites:

- `HomeView`, `ItemsView`, `LocationsView`, `NFCTabView` — `.any`
- `ItemDetailSheet` move flow — `.location` (moving an item to an item is meaningless)

### 9. Scan behavior depends on entity type, not code type

A scan resolves to a `Target`; what happens next is determined by the target:

- **Item target** → quick-update sheet (set location + photo)
- **Location target** → location detail view

This holds for QR and NFC alike, and matches what universal links and push notifications already do in `ContentView`. The 2-tap re-shelve flow that makes NFC tags worth applying is preserved.

Because the sheet is reachable from a QR scan too, `NFCUpdateSheet` is renamed `ItemQuickUpdateSheet` (file included). Its three call sites — `NFCTabView`, `ContentView` deep links, `ContentView` push — update with it. The NFC tab keeps its "NFC/QR" title.

### 10. `NFCPairSheet` pairs to either kind

Sections for Items and Locations under one search field. Rows show a tag-count indicator rather than a binary paired/unpaired glyph, since an entity may now hold several.

### 11. `NFCBadge` extends to locations

Shown on location rows in `LocationsView` when `pairedTags` is non-empty, alongside the existing item usages in `ItemsView`, `HomeView` and `ItemGalleryGrid`. Those three call sites switch from `item.nfcTagUID != nil` to `!item.pairedTags.isEmpty`. No QR badge exists — every entity implicitly has a QR code, so a badge would carry no information.

## Out of Scope

- Recording individual QR stickers as revocable records with labels. QR stays stateless and derived.
- Changing universal-link URL shape or the AASA file.
- Firestore security rules — `nfcTags` sits inside documents already covered by existing item/location rules.
- Writing labels onto the physical tag's NDEF payload, or blanking a tag when unpairing.

## Testing

No test target exists in this project. Verification is a clean `xcodebuild` plus manual passes:

1. An item with a legacy `nfcTagUID` shows that tag in `CodesSheet`; pairing a second leaves both listed and clears the legacy field.
2. A location accepts two tags; scanning either opens location detail.
3. Scanning an item QR opens the quick-update sheet; scanning a location QR opens location detail.
4. Item-move scanner rejects an item QR with an inline message and keeps scanning.
5. Batch print with a mixed item/location selection produces one PDF with all tiles.
6. Reassigning a tag from entity A to entity B removes only that serial from A, leaving A's other tags paired.
7. Renaming a tag persists the label; clearing the field falls back to the abbreviated serial.
8. Swipe-to-delete removes one tag row without disturbing its siblings.
