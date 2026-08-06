# Item Home Location ("Misplaced" tracking)

Date: 2026-08-06
Status: Approved

## Problem

An item's `locationId` records where it *is*. Nothing records where it *belongs*, so
there is no way to see which items have drifted from their proper place.

## Solution overview

Add an optional "supposed location" (home location) to `Item`. An item with a home
location set that is not currently in it is **misplaced**. Misplaced items are
surfaced through a Home-tab filter, an Items-tab filter, a per-location "missing
from here" section, badges on item rows, and single/bulk "put back" actions.

## Definitions

- **Home location** — `Item.homeLocationId`, optional. `nil` means the item has no
  expected place and can never be misplaced.
- **Misplaced** — `homeLocationId != nil && locationId != homeLocationId`.
  Matching is **exact**: an item whose home is `Living Room` but which sits in the
  child location `Living Room > Shelf A` counts as misplaced. An item with a home
  location and no current location (`locationId == nil`) also counts as misplaced.
- **Missing from a location** — item whose `homeLocationId` equals that location's id
  but whose `locationId` does not. The location-scoped view of the same predicate.

## Data model

`MyStuff/Models/Item.swift`:

```swift
/// Location this item is supposed to live in. nil = no expected place.
/// Optional so legacy docs missing the field decode cleanly — same idiom as ownerId/memberIds.
var homeLocationId: String?
```

Added to the memberwise `init` with a `nil` default, positioned next to `locationId`.

No Firestore security-rule change and no new index: the field rides existing item
documents under `users/{ownerId}/items` and syncs through the current write paths.
`MockDataService` needs no change (it stores whole `Item` values).

## Logic

`Item` extension (in `Item.swift`):

```swift
var isMisplaced: Bool {
    guard let homeLocationId else { return false }
    return locationId != homeLocationId
}
```

`StuffViewModel`:

```swift
/// Every item that is away from its home location.
var misplacedItems: [Item]

/// Items whose home is `location` but which are not currently there.
func missingItems(for location: Location) -> [Item]

/// Send each item back to its own home location. Groups by destination so a
/// mixed selection resolves in one pass; fires a single success haptic.
/// Items whose home location no longer exists are skipped.
func putBackItems(_ items: [Item]) async
```

`putBackItems` mirrors `moveItems`: it writes through `service.updateItem`, updates
`locationChangedAt` and `updatedAt`, patches the in-memory `items` array, and reports
failures via `errorMessage`.

## UI

### Item form (`ItemFormSheet`)

The existing "Location" section gains a second picker, **Supposed location**, listing
`viewModel.flattenedLocationTree()` plus a `None` sentinel. Default for new items is
`None`. Below it, a button **"Same as current location"** copies the value of the
Location picker into the supposed-location picker.

The value is carried on `ItemFormResult` as `homeLocationId: String?` and applied by
the `onSave` closures in `ItemsView`, `LocationDetailView`, and any other call site
that constructs an item from a form result, alongside the existing
`locationId`/`categoryId` assignment. `StuffViewModel.addItem` gains a
`homeLocationId: String?` parameter.

### Shared filter bar (`ItemFilterBar`)

`HomeView.filterBar` is extracted into a new file `MyStuff/Views/ItemFilterBar.swift`
so the Home and Items tabs share one implementation. Two types live there:

```swift
/// The filter selection. Value type so each host view owns its own state.
struct ItemFilter: Equatable {
    var categoryIds: Set<String> = []
    var locationIds: Set<String> = []
    var misplacedOnly = false

    var isActive: Bool                 // any facet set
    var activeCount: Int               // for the header badge

    /// Applies every facet plus `searchText`. Location matching includes
    /// descendants of each selected location, as the Home filter does today.
    func apply(to items: [Item], searchText: String, viewModel: StuffViewModel) -> [Item]
}

/// Collapsible chip bar: Categories, Locations, Status, and the action row.
struct ItemFilterBar: View {
    @Binding var filter: ItemFilter
    @Binding var isExpanded: Bool
    let viewModel: StuffViewModel
    let onPutAllBack: () -> Void
    let putBackCount: Int
}
```

The bar renders the existing Categories and Locations chip rows unchanged, adds a
**Status** row holding one chip — "⚠️ Misplaced" — and keeps the "Clear All" button
(which now also resets `misplacedOnly`). `filterChip` moves here as a private helper.

When `misplacedOnly` is on and `putBackCount > 0`, the bar shows a **"Put All Back (n)"**
button that calls `onPutAllBack`. Each host passes its own currently-visible misplaced
items, so the action always matches what the user can see.

Search text stays owned by each host (`HomeView` has a local `homeSearchText`,
`ItemsView` binds `viewModel.searchText`) and is passed into `apply(to:searchText:viewModel:)`.

### Home tab (`HomeView`)

`filterCategoryIds`, `filterLocationIds`, and the inline `filterBar`/`filterChip`
bodies are replaced by `@State private var filter = ItemFilter()` plus the shared
`ItemFilterBar`. `homeFilteredItems`, `isFiltering`, and `filtered(_:)` delegate to
`filter`, preserving current behaviour (including the empty-section rules that key off
`isFiltering`). This removes roughly 100 lines from `HomeView`.

### Items tab (`ItemsView`)

`ItemsView` gains the same `ItemFilterBar`, placed above the item list and above the
gallery grid, with its own `@State private var filter` and `@State private var showFilters`.
Both the list and gallery paths read one filtered collection derived from
`filter.apply(to: viewModel.filteredItems, searchText: "", viewModel:)` — search is
already applied by `viewModel.filteredItems`, so it is not passed twice.

In the `List` path (`itemsList`) the bar is a section row with `listRowInsets(EdgeInsets())`
and a clear row background, matching how `MoveItemsHereSheet` hosts its grouping picker.
In the gallery path (`itemsGallery`) it sits above `ItemGalleryGrid` inside the existing
`ScrollView`. No new toolbar button is added.

`ItemsView`'s empty state currently triggers on `viewModel.items.isEmpty`. When filters
narrow the result to nothing but items do exist, show a "No items match these filters"
`ContentUnavailableView` instead, keeping the filter bar visible so the user can clear it.

### Location detail (`LocationDetailView`)

New section **"Missing from here"**, rendered only when `missingItems(for: live)` is
non-empty, placed directly above the existing "Items" section. Each row shows the item
name and its current location (or "Unassigned"); tapping a row puts that single item
back. The section header carries a **"Put all back here"** button.

Bulk put-back here reuses the auto-share step from `MoveItemsHereSheet.confirmMove`:
when the current user can manage sharing of the destination, members missing from the
destination but present on the moved items are added first, then
`moveItems(missing, toLocationId: live.id)` runs. This keeps collaborators from losing
visibility of items moved into a location they are not a member of.

### Badge and single put-back

New `MisplacedBadge` view in `MyStuff/Views/`, styled after the existing `SharedBadge`
and `NFCBadge` (small warning glyph, subdued capsule). Displayed on misplaced items in:

- `HomeView` item rows and gallery tiles
- `ItemsView` item rows and gallery tiles
- `LocationDetailView` item rows and gallery tiles
- `ItemDetailSheet`'s `infoSection`, which shows the item's current location — the badge
  sits there with the home location's name, so the sheet states both where the item is
  and where it belongs

Item context menus (`itemMenuItems` in `HomeView`, `ItemsView`, `LocationDetailView`)
gain a **"Put Back"** action, shown only when the item is misplaced and its home
location still exists, calling `moveItem(item, toLocationId: item.homeLocationId)`.

## Cleanup and edge cases

- **Deleted home location** — `StuffViewModel.deleteLocation` already unassigns
  `locationId` for items at the deleted location. It additionally clears
  `homeLocationId` on every item pointing at that location, so no dangling home
  references survive. Note the two loops cover different item sets and both are needed.
- **Deleted location that was a home only** — covered by the clause above; those items
  keep their current location and simply lose their home.
- **Shared items** — misplaced state is derived from fields every member already reads,
  so collaborators see the same badges. No ownership check gates the badge; the "Put
  Back" action follows the same permissions as the existing move actions.
- **Item with no home location** — never misplaced, never shown by any of the new
  filters or sections, no badge.

## Out of scope

- Home locations for locations themselves (nested-location "belongs under" rules)
- History or audit trail of misplacements
- Notifications or reminders about misplaced items
- Descendant-tolerant matching (explicitly rejected: matching is exact)
