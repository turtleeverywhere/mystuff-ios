import Foundation
import SwiftUI

/// Central view model for all item and location operations.
@MainActor
@Observable
final class StuffViewModel {

    // MARK: - Published State

    var items: [Item] = []
    var locations: [Location] = []
    var searchText: String = ""
    var isLoading: Bool = false
    var errorMessage: String?

    // MARK: - Private

    /// Swap this single line to switch between Mock and Firebase:
    // private let service: DataService = MockDataService()
    private let service: DataService = FirebaseDataService()

    // MARK: - Computed

    var filteredItems: [Item] {
        guard !searchText.isEmpty else { return items }
        return items.filter { item in
            item.name.localizedCaseInsensitiveContains(searchText)
            || (item.notes?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    var unassignedItems: [Item] {
        items.filter { $0.locationId == nil }
    }

    func items(for location: Location) -> [Item] {
        items.filter { $0.locationId == location.id }
    }

    func location(for item: Item) -> Location? {
        guard let locationId = item.locationId else { return nil }
        return locations.first { $0.id == locationId }
    }

    func itemCount(for location: Location) -> Int {
        items.filter { $0.locationId == location.id }.count
    }

    // MARK: - Data Loading

    func loadData() async {
        isLoading = true
        errorMessage = nil
        do {
            async let fetchedItems = service.fetchItems()
            async let fetchedLocations = service.fetchLocations()
            items = try await fetchedItems
            locations = try await fetchedLocations
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Item CRUD

    func addItem(name: String, notes: String?, locationId: String?) async {
        let item = Item(name: name, notes: notes, locationId: locationId)
        do {
            try await service.addItem(item)
            items.append(item)
            HapticManager.success()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateItem(_ item: Item) async {
        var updated = item
        updated.updatedAt = .now
        do {
            try await service.updateItem(updated)
            if let index = items.firstIndex(where: { $0.id == updated.id }) {
                items[index] = updated
            }
            HapticManager.success()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteItem(_ item: Item) async {
        do {
            try await service.deleteItem(item)
            items.removeAll { $0.id == item.id }
            HapticManager.impact()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func moveItem(_ item: Item, toLocationId: String?) async {
        var updated = item
        updated.locationId = toLocationId
        updated.updatedAt = .now
        do {
            try await service.updateItem(updated)
            if let index = items.firstIndex(where: { $0.id == updated.id }) {
                items[index] = updated
            }
            HapticManager.success()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Location CRUD

    func addLocation(name: String, emoji: String?) async {
        let location = Location(name: name, emoji: emoji)
        do {
            try await service.addLocation(location)
            locations.append(location)
            HapticManager.success()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateLocation(_ location: Location) async {
        do {
            try await service.updateLocation(location)
            if let index = locations.firstIndex(where: { $0.id == location.id }) {
                locations[index] = location
            }
            HapticManager.success()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteLocation(_ location: Location) async {
        do {
            try await service.deleteLocation(location)
            locations.removeAll { $0.id == location.id }
            // Unassign items that were at this location
            for i in items.indices where items[i].locationId == location.id {
                items[i].locationId = nil
                items[i].updatedAt = .now
            }
            HapticManager.impact()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
