# Gallery View for Home + Items — Design

Date: 2026-07-06
Status: approved pending user review

## Goal

Add a gallery (photo grid) display mode to HomeView and ItemsView as alternative to existing list rows. Grid shows attached photos, 2 columns, item name overlaid at bottom of each tile, placeholder tile when no photo.

## Scope

- No model, ViewModel, or service changes.
- Search + filters + grouping logic untouched — gallery is a pure presentation swap.

## Components

### New: `MyStuff/Views/ItemGalleryGrid.swift`

- `ItemGalleryGrid` view: `LazyVGrid` with 2 flexible columns, 12pt spacing. Parameters: `items: [Item]`, `photoKind` (`.item` or `.location`), callbacks for tap / add-photo / context actions.
- `GalleryTile` view:
  - Square: `aspectRatio(1, contentMode: .fill)`, clipped, `RoundedRectangle(cornerRadius: 12)`.
  - Photo via existing `PhotoView(item:, kind:, size: .thumbnail(480))`, `scaledToFill`.
  - Name overlay: bottom-aligned, dark gradient scrim (clear → black ~55%), white text, `.subheadline`, `lineLimit(2)`.
  - Placeholder (no photo): `.ultraThinMaterial`/secondary fill, centered `photo` SF symbol in `.tertiary`, name overlay still shown at bottom.

### HomeView changes

- `@AppStorage("homeViewMode")` — `"list"` / `"gallery"`, persisted.
- Toolbar button toggling mode, icon `square.grid.2x2` / `list.bullet`.
- Gallery mode preserves ALL existing structure: group-by segmented picker, filter bar, location cards, sublocation headers, category cards, unassigned/uncategorized cards, empty states, counts. Only the per-card item rows are replaced by the 2-col grid.
- Photo kind: `.location` (location photo).
- Interactions:
  - Tile with photo: tap → `detailItem` (ItemDetailSheet), same as list row tap. Long press → photo source sheet (change photo), mirroring list thumbnail long-press.
  - Placeholder tile: tap → photo source sheet (add photo), mirroring list placeholder tap.

### ItemsView changes

- `@AppStorage("itemsViewMode")` — same toggle, same toolbar button.
- Gallery mode: replace `List` with `ScrollView` + `ItemGalleryGrid` over `viewModel.filteredItems`.
- Photo kind: `.item` (item photo).
- Interactions:
  - Tile with photo: tap → `editingItem` (ItemFormSheet), same as list.
  - Placeholder tile: tap → photo source sheet (add photo).
  - Context menu on every tile: **Edit**, **Change Photo**, **Delete** (destructive) — replaces swipe-to-delete which grids can't do.

## Error handling

- `PhotoView` already handles load failure → its placeholder branch renders; tile falls back to placeholder look with name overlay.
- Empty groups behave exactly as in list mode ("No items here" text in cards).

## Testing

- Project builds; existing unit tests pass.
- Manual sim check: toggle both views, both groupings on Home, filters + search active in gallery, placeholder tiles, tap/long-press/context-menu actions, persistence across relaunch.
