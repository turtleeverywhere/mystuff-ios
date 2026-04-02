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
    var categories: [Category] = []
    var selectedGrouping: GroupingMode = .location

    enum GroupingMode: String, CaseIterable {
        case location = "Location"
        case category = "Category"
    }

    // MARK: - Private

    /// Swap this single line to switch between Mock and Firebase:
    // private let service: DataService = MockDataService()
    private let service: DataService = FirebaseDataService()
    // private let storageService: StorageService = MockStorageService()
    private let storageService: StorageService = FirebaseStorageService()

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

    // MARK: - Category Computed

    var uncategorizedItems: [Item] {
        items.filter { $0.categoryId == nil }
    }

    func items(for category: Category) -> [Item] {
        items.filter { $0.categoryId == category.id }
    }

    func category(for item: Item) -> Category? {
        guard let categoryId = item.categoryId else { return nil }
        return categories.first { $0.id == categoryId }
    }

    func itemCount(for category: Category) -> Int {
        items.filter { $0.categoryId == category.id }.count
    }

    // MARK: - Data Loading

    func loadData() async {
        isLoading = true
        errorMessage = nil
        do {
            async let fetchedItems = service.fetchItems()
            async let fetchedLocations = service.fetchLocations()
            async let fetchedCategories = service.fetchCategories()
            items = try await fetchedItems
            locations = try await fetchedLocations
            categories = try await fetchedCategories
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Item CRUD

    func addItem(name: String, notes: String?, locationId: String?, categoryId: String?) async {
        let item = Item(name: name, notes: notes, locationId: locationId, categoryId: categoryId)
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
            if item.photoURL != nil {
                try? await storageService.deletePhoto(url: item.photoURL!)
            }
            try await service.deleteItem(item)
            items.removeAll { $0.id == item.id }
            HapticManager.impact()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Photo

    func setPhoto(for item: Item, imageData: Data) async {
        guard let compressed = ImageHelper.compress(imageData) else { return }
        do {
            if let oldURL = item.photoURL {
                try? await storageService.deletePhoto(url: oldURL)
            }
            let url = try await storageService.uploadPhoto(itemId: item.id, imageData: compressed)
            var updated = item
            updated.photoURL = url
            updated.updatedAt = .now
            try await service.updateItem(updated)
            if let index = items.firstIndex(where: { $0.id == updated.id }) {
                items[index] = updated
            }
            HapticManager.success()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deletePhoto(for item: Item) async {
        guard let url = item.photoURL else { return }
        do {
            try? await storageService.deletePhoto(url: url)
            var updated = item
            updated.photoURL = nil
            updated.updatedAt = .now
            try await service.updateItem(updated)
            if let index = items.firstIndex(where: { $0.id == updated.id }) {
                items[index] = updated
            }
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
                try await service.updateItem(items[i])
            }
            HapticManager.impact()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Category CRUD

    @discardableResult
    func addCategory(name: String) async -> Category? {
        let category = Category(name: name)
        do {
            try await service.addCategory(category)
            categories.append(category)
            HapticManager.success()
            return category
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func updateCategory(_ category: Category) async {
        do {
            try await service.updateCategory(category)
            if let index = categories.firstIndex(where: { $0.id == category.id }) {
                categories[index] = category
            }
            HapticManager.success()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteCategory(_ category: Category) async {
        do {
            try await service.deleteCategory(category)
            categories.removeAll { $0.id == category.id }
            for i in items.indices where items[i].categoryId == category.id {
                items[i].categoryId = nil
                items[i].updatedAt = .now
                try await service.updateItem(items[i])
            }
            HapticManager.impact()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
