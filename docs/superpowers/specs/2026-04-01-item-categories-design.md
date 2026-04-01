# Item Categories Design

## Summary

Add managed categories to items with Home tab grouping toggle (location vs category).

## Model

`Category`: `id: String`, `name: String`, `createdAt: Date`. Codable/Sendable/Identifiable/Hashable, same pattern as `Location`.

Firestore path: `users/{uid}/categories/{categoryId}`

## Item Change

Add `categoryId: String?` to `Item`. nil = uncategorized (displayed as "Uncategorized" in UI, same pattern as nil locationId = "Unassigned").

## DataService Protocol

Add to `DataService`:
- `fetchCategories() async throws -> [Category]`
- `addCategory(_ category: Category) async throws`
- `updateCategory(_ category: Category) async throws`
- `deleteCategory(_ category: Category) async throws`

Implement in `FirebaseDataService` (Firestore collection) and `MockDataService` (in-memory with sample data).

## StuffViewModel

- Add `categories: [Category]` array
- Add `selectedGrouping: GroupingMode` enum (`.location`, `.category`)
- Add computed: `items(for category:)`, `itemCount(for category:)`, `category(for item:)`, `uncategorizedItems`
- Add CRUD: `addCategory(name:)`, `updateCategory(_:)`, `deleteCategory(_:)` — deletion sets affected items' categoryId to nil
- Load categories in `loadData()` alongside items and locations

## Home Tab

- Segmented control at top: "Location" / "Category"
- When grouped by location (existing behavior): each item row shows a category tag
- When grouped by category: cards per category with item rows, each showing a location tag. "Uncategorized" card for items with nil categoryId.
- Item tap behavior unchanged (move sheet)

## Items Tab

- `ItemFormSheet`: add category picker below location picker, same pattern. Include "Unassigned" option + all categories + "New Category..." row that inline-creates a category (text field alert or inline row).
- Toolbar button opens `CategoryManagementView`: list of categories with tap-to-edit and swipe-to-delete, same pattern as `LocationsView`.

## Tags

Small capsule badge (same style as existing location badge in ItemsView) showing category name or location name depending on current grouping mode.

## Deletion Behavior

Deleting a category sets all affected items' `categoryId` to nil, matching location deletion behavior.
