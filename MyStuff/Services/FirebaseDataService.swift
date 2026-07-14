import Foundation
import FirebaseAuth
import FirebaseFirestore

/// Firestore-backed implementation of DataService.
///
/// Data is scoped per authenticated user:
///   `users/{uid}/items` and `users/{uid}/locations`
final class FirebaseDataService: DataService, @unchecked Sendable {

    private let db = Firestore.firestore()

    private var uid: String {
        guard let uid = Auth.auth().currentUser?.uid else {
            fatalError("FirebaseDataService used without an authenticated user.")
        }
        return uid
    }

    var currentUserId: String { Auth.auth().currentUser?.uid ?? "" }

    private func userDoc(_ owner: String) -> DocumentReference {
        db.collection("users").document(owner)
    }
    private func itemsCollection(owner: String) -> CollectionReference {
        userDoc(owner).collection("items")
    }
    private func locationsCollection(owner: String) -> CollectionReference {
        userDoc(owner).collection("locations")
    }
    private var categoriesCollection: CollectionReference {
        userDoc(uid).collection("categories")
    }

    /// Owner path for a write. Falls back to the current user for brand-new local entities.
    private func owner(of ownerId: String?) -> String { ownerId ?? uid }

    // MARK: - Items

    func fetchItems(source: FetchSource) async throws -> [Item] {
        let snapshot = try await db.collectionGroup("items")
            .whereField("memberIds", arrayContains: uid)
            .order(by: "createdAt", descending: true)
            .getDocuments(source: source.firestoreSource)
        return try snapshot.documents.map { try $0.data(as: Item.self) }
    }

    func addItem(_ item: Item) async throws {
        var item = item
        let owner = owner(of: item.ownerId)
        item.ownerId = owner
        if item.memberIds == nil || item.memberIds?.isEmpty == true { item.memberIds = [owner] }
        try itemsCollection(owner: owner).document(item.id).setData(from: item)
    }

    func updateItem(_ item: Item) async throws {
        try itemsCollection(owner: owner(of: item.ownerId)).document(item.id).setData(from: item, merge: true)
    }

    func deleteItem(_ item: Item) async throws {
        try await itemsCollection(owner: owner(of: item.ownerId)).document(item.id).delete()
    }

    // MARK: - Locations

    func fetchLocations(source: FetchSource) async throws -> [Location] {
        let snapshot = try await db.collectionGroup("locations")
            .whereField("memberIds", arrayContains: uid)
            .order(by: "createdAt", descending: true)
            .getDocuments(source: source.firestoreSource)
        return try snapshot.documents.map { try $0.data(as: Location.self) }
    }

    func addLocation(_ location: Location) async throws {
        var location = location
        let owner = owner(of: location.ownerId)
        location.ownerId = owner
        if location.memberIds == nil || location.memberIds?.isEmpty == true { location.memberIds = [owner] }
        try locationsCollection(owner: owner).document(location.id).setData(from: location)
    }

    func updateLocation(_ location: Location) async throws {
        try locationsCollection(owner: owner(of: location.ownerId)).document(location.id).setData(from: location, merge: true)
    }

    func deleteLocation(_ location: Location) async throws {
        try await locationsCollection(owner: owner(of: location.ownerId)).document(location.id).delete()
    }

    // MARK: - Categories

    func fetchCategories(source: FetchSource) async throws -> [Category] {
        let snapshot = try await categoriesCollection
            .order(by: "createdAt", descending: true)
            .getDocuments(source: source.firestoreSource)
        return try snapshot.documents.map { try $0.data(as: Category.self) }
    }

    func addCategory(_ category: Category) async throws {
        try categoriesCollection.document(category.id).setData(from: category)
    }

    func updateCategory(_ category: Category) async throws {
        try categoriesCollection.document(category.id).setData(from: category, merge: true)
    }

    func deleteCategory(_ category: Category) async throws {
        try await categoriesCollection.document(category.id).delete()
    }
}

private extension FetchSource {
    var firestoreSource: FirestoreSource {
        switch self {
        case .cache: return .cache
        case .server: return .server
        case .default: return .default
        }
    }
}
