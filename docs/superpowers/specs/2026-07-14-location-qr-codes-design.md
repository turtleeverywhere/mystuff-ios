# Location QR Codes — Design

Date: 2026-07-14
Status: Approved

## Goal

Generate printable QR codes for locations. A QR encodes a universal link to
the location. Scanning it — from the system Camera app **or** from inside
MyStuff — opens the app and shows the items stored at that location. When moving
an item, the target location can be chosen by scanning its QR. Export as PNG and
PDF; print directly (AirPrint).

Reuses the existing universal-link infrastructure already built for NFC item
tags (host `mystuff.coding-turtle.org`, AASA at `.well-known/`).

## Non-goals

- No JPG or SVG export (PDF is vector-capable, printable, and shareable; PNG
  covers raster sharing).
- No item QR codes (items use NFC).
- No web fallback page for un-installed app (future, worker-side only).
- No model/schema changes.

## Existing infrastructure (reused)

- **Universal links**: AASA at `mystuff.coding-turtle.org/.well-known/apple-app-site-association`,
  associated domain in `MyStuff.entitlements`. Currently routes `/item/*`.
- **`NFCLink`** (`NFCService.swift`): builds/parses `https://<host>/item/<uuid>`.
- **Deep-link handling** (`ContentView.swift`): `onOpenURL` + `onContinueUserActivity`
  → `handleDeepLink` → `pendingNFCItemId` → resolves against loaded items →
  presents `NFCUpdateSheet`. The "resolve when data loads" pattern is reused.
- **`viewModel.items(for: location)`**, `childLocations(for:)`, `recursiveItemCount(for:)`
  already exist.
- **`NSCameraUsageDescription`** already in `Info.plist` (no new permission key).

## Components

### 1. `AppLink` (new — `MyStuff/Services/AppLink.swift`)

Unified URL router for both targets. Owns the shared host.

```swift
enum AppLink {
    static let host = "mystuff.coding-turtle.org"
    enum Target: Equatable { case item(String), location(String) }
    static func url(for target: Target) -> URL      // https://host/{item|location}/<id>
    static func parse(_ url: URL) -> Target?         // nil if not one of ours
}
```

`NFCLink.host` becomes `AppLink.host`; `NFCLink.url(forItemId:)` /
`itemId(from:)` delegate to `AppLink` (item path unchanged, so NFC writing/reading
behaves identically). `AppLink.parse` recognizes both `/item/<id>` and
`/location/<id>`.

### 2. AASA change (`.well-known/apple-app-site-association`)

Add a component so location links route to the app:

```json
"components": [ { "/": "/item/*" }, { "/": "/location/*" } ]
```

User redeploys the Cloudflare worker/host serving this file. No worker logic
change.

### 3. `LocationDetailView` (new — `MyStuff/Views/LocationDetailView.swift`)

The home for a location. Two presentations from **one** view:

- **Pushed**: tapping a location row in `LocationsView` pushes it (replacing the
  current tap-to-edit behavior).
- **Sheet**: opening a location via QR/scan presents it inside a
  `NavigationStack` sheet.

Content:
- Header: emoji + name + item count.
- Direct items: `viewModel.items(for: location)`; tap an item → `ItemDetailSheet`.
- Sub-locations: `viewModel.childLocations(for:)` as `NavigationLink`s to their
  own detail (only meaningful in the pushed presentation; in sheet presentation
  they still push within the sheet's stack).
- Empty state when no items.
- Toolbar: **Edit** (existing `LocationFormSheet`) + **QR Code** (presents
  `QRCodeSheet`).

### 4. `QRCodeGenerator` (new — `MyStuff/Utilities/QRCodeGenerator.swift`)

```swift
enum QRCodeGenerator {
    static func image(for string: String, scale: CGFloat = 12) -> UIImage?
}
```

CoreImage `CIFilter.qrCodeGenerator` with high error correction; scaled with
nearest-neighbor (no blur); rendered to `UIImage`. Returns nil on failure.

### 5. `QRStickerView` (new — `MyStuff/Views/QRStickerView.swift`)

SwiftUI view = single source of truth for the sticker: QR image + emoji + name
caption, on a white card (print-friendly, high contrast regardless of app
theme). Used both for on-screen preview and for export rendering.

### 6. `QRCodeSheet` (new — `MyStuff/Views/QRCodeSheet.swift`)

Presents `QRStickerView` preview + actions:
- **Share**: `ShareLink` exposing PNG and PDF items (user picks
  destination/Files/Print via the system share sheet).
- **Print**: `UIPrintInteractionController` with the PDF (AirPrint).

Export rendering via `ImageRenderer(content: QRStickerView(...))`:
- PNG: `renderer.uiImage` → `pngData()`.
- PDF: `renderer.render { size, ctx in UIGraphicsPDFRenderer... }` → `Data`.

Both include emoji + name. Files named `<location-name>-qr.png` / `.pdf`.

### 7. `QRScannerView` (new — `MyStuff/Views/QRScannerView.swift`)

`UIViewControllerRepresentable` wrapping `DataScannerViewController` (VisionKit),
`recognizedDataTypes: [.barcode(symbologies: [.qr])]`. Delegate returns the
decoded string; caller parses via `AppLink.parse`. A host sheet wraps it with a
title bar + cancel, and shows an inline error for unrecognized codes.

Availability: only offered when `DataScannerViewController.isSupported &&
.isAvailable`. On unsupported devices / simulator, the scan buttons are hidden.
Camera-permission-denied → alert linking to Settings.

### 8. Entry points

- **Global scan** — a **Scan** toolbar button in `LocationsView` (next to `+`).
  Scans a location QR → presents that location's `LocationDetailView` sheet
  (same code path as deep-link). Works on iPhone and iPad.
- **Move-item scan** — `MoveItemSheet` (shared struct used by `HomeView` and
  `ItemsView`) gets a **Scan QR** button. A scanned location QR sets the move
  target to that location. A non-location / unknown QR shows an inline error and
  keeps the manual picker.

### 9. `ContentView` changes

- Add `@State deepLinkedLocation: Location?` + `pendingLocationId` mirroring the
  existing item plumbing.
- `handleDeepLink(url)` switches on `AppLink.parse`: `.item` → existing path;
  `.location` → `pendingLocationId`, resolved against `viewModel.locations` when
  loaded, then present `LocationDetailView` in a sheet.
- Unknown/deleted location id → pending cleared, no-op (no crash, no sheet).

## Data flow

```
Print QR:  LocationDetailView → QRCodeSheet → ImageRenderer(QRStickerView) → PNG/PDF → Share/Print
Camera app scan: system Camera → universal link https://host/location/<id>
                 → app foreground → ContentView.handleDeepLink → AppLink.parse(.location)
                 → resolve Location → present LocationDetailView (sheet) → items list
In-app global scan: LocationsView Scan → QRScannerView → AppLink.parse → same sheet
Move by scan: MoveItemSheet Scan → QRScannerView → AppLink.parse(.location)
              → set target location → confirm move
```

## Error handling

| Case | Behavior |
|------|----------|
| QR generation fails | Sheet shows fallback message, disables export |
| Camera permission denied | Alert → "Open Settings" |
| DataScanner unsupported | Scan buttons hidden |
| Scanned code not a MyStuff URL | Inline "Not a MyStuff code" in scanner sheet |
| Scanned location deleted/unknown | Inline "Location not found" |
| Deep-link to unknown location | Pending cleared, no sheet |

## Files

**New**
- `MyStuff/Services/AppLink.swift`
- `MyStuff/Utilities/QRCodeGenerator.swift`
- `MyStuff/Views/QRStickerView.swift`
- `MyStuff/Views/QRCodeSheet.swift`
- `MyStuff/Views/LocationDetailView.swift`
- `MyStuff/Views/QRScannerView.swift`

**Modified**
- `.well-known/apple-app-site-association` — add `/location/*` component
- `MyStuff/Services/NFCService.swift` — `NFCLink` delegates to `AppLink`
- `MyStuff/Views/ContentView.swift` — location deep-link routing + sheet
- `MyStuff/Views/LocationsView.swift` — row tap → detail; Scan toolbar button
- `MyStuff/Views/HomeView.swift` — `MoveItemSheet` Scan QR button

No model changes. No new Info.plist key (camera description already present;
optionally broaden its wording to mention QR scanning).

## Verification (no test target)

Manual, per `xcodebuild` build succeeding first:
1. Generate a QR for a location; Share PNG + PDF; Print preview renders sticker
   with emoji + name.
2. Scan the printed/preview QR with the system Camera app → MyStuff opens →
   location items sheet with correct items.
3. In-app global Scan → same sheet.
4. Move an item via MoveItemSheet Scan → item lands in scanned location.
5. Scan a random non-app QR in-app → "Not a MyStuff code".
6. NFC item flow still works (regression: `AppLink` refactor).
