import Foundation

/// Source for fetch operations.
enum FetchSource {
    /// Disk cache only — instant, returns empty if nothing cached.
    case cache
    /// Network only — bypasses cache.
    case server
    /// Default behavior (network with cache fallback).
    case `default`
}

/// Protocol defining all CRUD operations for items and locations.
protocol DataService: Sendable {

    /// Current authenticated user's uid. Empty string if unauthenticated (Firebase) or a stable
    /// constant (Mock). Used to stamp `ownerId`/`memberIds` on new entities.
    var currentUserId: String { get }

    /// Read the current user's OWN items subcollection directly (pre-sharing path).
    /// Used once to backfill `memberIds`/`ownerId` before the collectionGroup read.
    func fetchOwnItems() async throws -> [Item]
    /// Read the current user's OWN locations subcollection directly.
    func fetchOwnLocations() async throws -> [Location]

    // MARK: - Items

    func fetchItems(source: FetchSource) async throws -> [Item]
    func addItem(_ item: Item) async throws
    func updateItem(_ item: Item) async throws
    func deleteItem(_ item: Item) async throws

    // MARK: - Locations

    func fetchLocations(source: FetchSource) async throws -> [Location]
    func addLocation(_ location: Location) async throws
    func updateLocation(_ location: Location) async throws
    func deleteLocation(_ location: Location) async throws

    // MARK: - Categories

    func fetchCategories(source: FetchSource) async throws -> [Category]
    func addCategory(_ category: Category) async throws
    func updateCategory(_ category: Category) async throws
    func deleteCategory(_ category: Category) async throws
}

extension DataService {
    func fetchItems() async throws -> [Item] { try await fetchItems(source: .default) }
    func fetchLocations() async throws -> [Location] { try await fetchLocations(source: .default) }
    func fetchCategories() async throws -> [Category] { try await fetchCategories(source: .default) }
}
