# iPad Support: Hide NFC UI on Devices Without NFC Reader

**Date:** 2026-07-07
**Status:** Approved

## Goal

App is already universal (`TARGETED_DEVICE_FAMILY = 1,2`) and uses `.sidebarAdaptable` tabs, so it runs on iPad today. Only gap: NFC UI shows on iPads, which have no NFC reader. Hide all NFC UI on devices without NFC hardware.

## Non-Goals

- No iPad-specific layout pass (grids, split view) — explicitly out of scope.
- No separate iPad target.
- No removal of NFC deep-link handling (see Decisions).

## Detection

Capability-based, not idiom-based: `NFCTagReaderSession.readingAvailable` (already wrapped by `CoreNFCService.isAvailable`). False on iPad; also covers any NFC-less device and future Catalyst.

## Changes

### 1. `MyStuff/Views/ContentView.swift` (only code change)

Wrap the NFC tab in an availability check:

```swift
if nfcAvailable {
    Tab("NFC", systemImage: "wave.3.right.circle.fill", value: 3) {
        NFCTabView(viewModel: viewModel)
    }
}
```

`nfcAvailable` comes from a static availability check (`NFCTagReaderSession.readingAvailable` via a small helper on the NFC service layer, matching the existing `isAvailable` pattern). Result: iPad sidebar shows Home/Items/Locations only.

## Already Handled (no change)

- `ItemDetailSheet.nfcSection` — already gated on `nfcService.isAvailable`, hidden on iPad.
- `NFCPairSheet` — only reachable from gated UI.
- `MockNFCService.isAvailable = true` keeps previews working.

## Decisions

- **Keep deep-link handling on iPad** (`onOpenURL` / `NFCUpdateSheet`): the sheet needs no NFC hardware. If a tag's universal link is opened in Safari on iPad, the item still resolves. Shows nothing unless a link arrives.

## Testing

- Build for iPad simulator: no NFC tab, no NFC section in item detail.
- Build for iPhone simulator: unchanged (NFC tab present).
- No test target exists; verification is build + manual.
