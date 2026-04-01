import Foundation

/// Protocol defining all CRUD operations for items and locations.
protocol DataService: Sendable {

    // MARK: - Items

    func fetchItems() async throws -> [Item]
    func addItem(_ item: Item) async throws
    func updateItem(_ item: Item) async throws
    func deleteItem(_ item: Item) async throws

    // MARK: - Locations

    func fetchLocations() async throws -> [Location]
    func addLocation(_ location: Location) async throws
    func updateLocation(_ location: Location) async throws
    func deleteLocation(_ location: Location) async throws

    // MARK: - Categories

    func fetchCategories() async throws -> [Category]
    func addCategory(_ category: Category) async throws
    func updateCategory(_ category: Category) async throws
    func deleteCategory(_ category: Category) async throws
}
