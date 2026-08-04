# Codes in the Item and Location Form Sheets

**Date:** 2026-08-04
**Status:** Approved
**Builds on:** `2026-07-25-unified-qr-nfc-design.md`

## Problem

NFC tags and QR codes can only be managed from an entity's *detail* screen (`ItemDetailSheet`, `LocationDetailView`), each of which shows a `CodesRow` that presents the shared `CodesSheet`.

The Items tab is where items are created and edited, so that is where a user expects to attach a tag. Today `ItemFormSheet` offers no codes affordance at all, in either create or edit mode. `LocationFormSheet` has the identical gap.

## Key Constraint

**In create mode the entity has no id yet.** `addItem` and `addLocation` mint the `id` internally (`StuffViewModel.swift:401`, `:803`), and the form only hands back field values through its `onSave` closure.

Both code kinds need that id:

- A QR payload *is* the id — `https://mystuff.coding-turtle.org/item/<uuid>`.
- An NFC pair burns that same URL onto the physical tag.

So supporting codes during creation requires the id to exist before the entity does.

**QR codes are not "added" or "removed."** They are derived and stateless — every sticker for an entity is byte-identical and nothing is persisted. In the form, as in `CodesSheet`, the QR affordance is Show / Share / Print. Only NFC tags are genuinely add/remove.

## Design

### 1. Pre-allocated draft id

Both form sheets gain:

```swift
@State private var draftId: String
// init: _draftId = State(initialValue: entity?.id ?? UUID().uuidString)
```

**This must be `@State`, not a plain `let`.** SwiftUI recreates the view struct on every render pass; a `let` initialized in `init` would mint a fresh UUID each time, and a tag paired a moment earlier would point at an id that never reaches Firestore.

`addItem` and `addLocation` gain a defaulted `id` parameter so no existing caller changes behavior:

```swift
func addItem(id: String = UUID().uuidString, name: String, notes: String?, locationId: String?, categoryId: String?) async
func addLocation(id: String = UUID().uuidString, name: String, emoji: String?, parentId: String? = nil) async
```

Callers that create from a form pass `draftId`.

This also retires a latent bug. Three call sites currently locate the just-created entity by name:

- `ItemsView.swift:69` — `items.last(where: { $0.name == name })`
- `LocationDetailView.swift` — same shape for the add-item-here flow
- `ItemQuickUpdateSheet.swift:83` — `locations.last(where: { $0.name == name && $0.parentId == parentId })`

Each becomes an id lookup, so creating two entities with the same name can no longer attach a photo or share to the wrong one.

### 2. `CodesSheet` becomes closure-driven

`CodesSheet` currently reads `viewModel.pairedTags(for:)` and calls `addNFCTag` / `removeNFCTag` / `renameNFCTag` directly, so it can only operate on an entity that already exists. Parameterize the data in and the effects out:

```swift
struct CodesSheet: View {
    let subject: QRSubject
    let tags: [NFCTag]
    let onPair: (String) async -> Void            // tag serial
    let onRemove: (String) async -> Void          // tag serial
    let onRename: (String, String?) async -> Void // serial, new label
    @Bindable var viewModel: StuffViewModel       // displayName in the reassign alert only
}
```

- **Detail screens** pass closures that forward to the viewmodel. Behavior is unchanged from today.
- **Form sheets** pass closures that mutate a local `@State private var stagedTags: [NFCTag]`.

One component, one pair flow, one set of alerts — the property the parent spec introduced `CodesSheet` to protect. The NFC session, the reassign confirmation, and the rename alert are all written once.

**The subject is passed in, not derived.** `CodesSheet` previously called `viewModel.qrSubject(for: target)`, which looks the entity up in `items` / `locations` and so returns `nil` for a draft that has not been saved — the QR section would silently render nothing in create mode. Callers supply it instead:

- Detail screens keep using `viewModel.qrSubject(for: target)` at their existing call site, which already guards the optional.
- Form sheets build one directly from the draft: `QRSubject(target: .item(draftId), name: name, icon: "📦")` — or `emoji` for a location — so the printed tile's caption tracks the name field as the user types.

`subject.target` replaces the separate `target` parameter, since `QRSubject` already carries it. The remaining `viewModel` dependency is only `displayName(for:)` in the reassign alert, which names a *different*, already-saved entity and so resolves correctly in both modes.

When the name field is still empty, the tile renders with a blank caption; that is acceptable and matches what `QRTileView` already does for an unnamed entity.

`CodesRow` takes `tags: [NFCTag]` instead of a `StuffViewModel`, so it can render the staged count in a form and the live count on a detail screen. It keeps no viewmodel dependency.

### 3. Applying the buffer on Save

```swift
/// Apply a buffered tag list, stripping each serial from any other entity that
/// currently owns it. Used by the form sheets, which stage tag edits until Save.
func applyStagedTags(_ staged: [NFCTag], to target: AppLink.Target) async
```

For each staged serial, resolve the current owner with `target(forTagUID:)`; if it is a different entity, `removeNFCTag` there first. Then write the list via the existing private `writeTags`.

- **Create:** `addItem(id: draftId, …)`, then `applyStagedTags(staged, to: .item(draftId))`. The entity must exist first, because `writeTags` looks it up in `items` / `locations`.
- **Edit:** `applyStagedTags(staged, to: .item(item.id))` alongside the existing update call.

Skip the call entirely when `staged == entity.pairedTags` (`NFCTag` is `Equatable`, and array equality is order-sensitive — there is no reorder affordance, so order only changes when a tag is added or removed). An ordinary rename-the-item save therefore writes no tags.

### 4. Form UI

Both form sheets gain a `Codes` section holding a `CodesRow` button that presents `CodesSheet`, matching how the detail screens present it.

In create mode the section carries a footer: **"Codes activate when you save this item."** (`…this location.` in `LocationFormSheet`.) The draft is real enough to pair and print against, and the copy says so plainly rather than implying the entity already exists.

## Semantics

- **The NDEF write is immediate; only the record is staged.** Writing a tag is a hardware operation and cannot be deferred. Cancelling the form after pairing leaves a physical tag pointing at an id that was never saved. Scanning such a tag already lands in the "points to an item that no longer exists — pair it to something else?" flow, so it self-heals through existing UX.
- **Unpairing inside the form** removes the entry from the staging buffer only. The physical tag keeps its payload, identical to unpair semantics everywhere else in the app.
- **Reassignment** of a serial away from another entity happens at Save, not at pair time.
- **Last-write-wins on tags.** If another device changes this entity's tags while the form is open, Save overwrites with the staged list. This is inherent to buffering and already true of name, notes and photos.

## Out of Scope

- Changing the QR payload or URL shape.
- Persisting QR codes as records — they stay derived and stateless.
- Blanking a physical tag when it is unpaired.
- Cleaning up orphaned tags written against a cancelled draft; the existing re-pair flow covers it.
- Firestore security rules — no new fields.
- Batch printing ("Print Multiple…") for an unsaved draft. `BatchQRPrintSheet` enumerates entities from the view model, so a draft cannot appear there; the button is hidden until the entity is saved. Single-sticker Print, Share PDF and Share PNG do work for a draft.

## Testing

No test target exists in this project. Verification is a clean `xcodebuild` plus a manual pass:

1. Create an item, pair a tag in the form, Save. The tag appears on the item's detail screen and scanning it opens that item.
2. Create an item, pair a tag, then **Cancel**. No item is created; scanning the tag offers to pair it elsewhere.
3. Edit an item, unpair one of two tags, Save. Only that tag is removed.
4. Edit an item, unpair a tag, then **Cancel**. The tag is still paired.
5. Pair a serial already held by another entity, Save. It moves; the previous owner keeps its other tags.
6. Create an item with no tag interaction at all. No tag write occurs, and the item saves as before.
7. Create two items with the same name in a row, attaching a photo to each. Each photo lands on the correct item (the id-lookup fix).
8. The same passes for `LocationFormSheet`.
9. In a create form, open Codes → "Show, Share & Print" *before* saving. Print and both Share actions produce the draft's sticker; "Print Multiple…" is not offered.
10. Force a create to fail mid-save (e.g. offline with rules denying the write). No staged serial is unpaired from its current owner, and a location created from `ItemQuickUpdateSheet` leaves the picker unchanged rather than binding to a dangling `locationId`.
