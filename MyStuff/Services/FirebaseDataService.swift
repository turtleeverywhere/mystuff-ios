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

    private var userDoc: DocumentReference { db.collection("users").document(uid) }
    private var itemsCollection: CollectionReference { userDoc.collection("items") }
    private var locationsCollection: CollectionReference { userDoc.collection("locations") }

    // MARK: - Items

    func fetchItems() async throws -> [Item] {
        let snapshot = try await itemsCollection.order(by: "createdAt", descending: true).getDocuments()
        return try snapshot.documents.map { try $0.data(as: Item.self) }
    }

    func addItem(_ item: Item) async throws {
        try itemsCollection.document(item.id).setData(from: item)
    }

    func updateItem(_ item: Item) async throws {
        try itemsCollection.document(item.id).setData(from: item, merge: true)
    }

    func deleteItem(_ item: Item) async throws {
        try await itemsCollection.document(item.id).delete()
    }

    // MARK: - Locations

    func fetchLocations() async throws -> [Location] {
        let snapshot = try await locationsCollection.order(by: "createdAt", descending: true).getDocuments()
        return try snapshot.documents.map { try $0.data(as: Location.self) }
    }

    func addLocation(_ location: Location) async throws {
        try locationsCollection.document(location.id).setData(from: location)
    }

    func updateLocation(_ location: Location) async throws {
        try locationsCollection.document(location.id).setData(from: location, merge: true)
    }

    func deleteLocation(_ location: Location) async throws {
        try await locationsCollection.document(location.id).delete()
    }
}
