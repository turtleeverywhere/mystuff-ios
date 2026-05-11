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

    // MARK: - Location Tree

    var rootLocations: [Location] {
        locations.filter { $0.parentId == nil }
    }

    func childLocations(for location: Location) -> [Location] {
        locations.filter { $0.parentId == location.id }
    }

    func allDescendantIds(of locationId: String) -> Set<String> {
        var result = Set<String>()
        var queue = locations.filter { $0.parentId == locationId }
        while !queue.isEmpty {
            let loc = queue.removeFirst()
            result.insert(loc.id)
            queue.append(contentsOf: locations.filter { $0.parentId == loc.id })
        }
        return result
    }

    func recursiveItemCount(for location: Location) -> Int {
        let ids = allDescendantIds(of: location.id).union([location.id])
        return items.filter { ids.contains($0.locationId ?? "") }.count
    }

    func locationPath(for location: Location) -> [Location] {
        var path = [location]
        var current = location
        while let pid = current.parentId, let parent = locations.first(where: { $0.id == pid }) {
            path.insert(parent, at: 0)
            current = parent
        }
        return path
    }

    func displayPath(for location: Location) -> String {
        locationPath(for: location).map(\.name).joined(separator: " > ")
    }

    func rootLocation(for location: Location) -> Location {
        locationPath(for: location).first ?? location
    }

    /// DFS flattened tree with depth for pickers
    func flattenedLocationTree(excluding excludeId: String? = nil) -> [(location: Location, depth: Int)] {
        let excluded: Set<String>
        if let excludeId {
            excluded = allDescendantIds(of: excludeId).union([excludeId])
        } else {
            excluded = []
        }

        var result: [(Location, Int)] = []
        func walk(_ parentId: String?, depth: Int) {
            let children = locations
                .filter { $0.parentId == parentId && !excluded.contains($0.id) }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            for child in children {
                result.append((child, depth))
                walk(child.id, depth: depth + 1)
            }
        }
        walk(nil, depth: 0)
        return result
    }

    /// All descendants flattened under a location, grouped by sublocation
    func flattenedDescendantItems(for location: Location) -> [(sublocation: Location, items: [Item])] {
        var result: [(Location, [Item])] = []
        func walk(_ loc: Location) {
            let locItems = items(for: loc)
            if !locItems.isEmpty {
                result.append((loc, locItems))
            }
            for child in childLocations(for: loc).sorted(by: { $0.name < $1.name }) {
                walk(child)
            }
        }
        // Collect children recursively (skip root itself — caller handles root items)
        for child in childLocations(for: location).sorted(by: { $0.name < $1.name }) {
            walk(child)
        }
        return result
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

    private static func deduped<T: Identifiable>(_ values: [T]) -> [T] where T.ID: Hashable {
        var seen = Set<T.ID>()
        return values.filter { seen.insert($0.id).inserted }
    }

    func loadData() async {
        errorMessage = nil

        // Stage 1: hydrate from cache (instant, no spinner)
        async let cachedItems = try? service.fetchItems(source: .cache)
        async let cachedLocations = try? service.fetchLocations(source: .cache)
        async let cachedCategories = try? service.fetchCategories(source: .cache)
        let ci = await cachedItems ?? []
        let cl = await cachedLocations ?? []
        let cc = await cachedCategories ?? []
        if !ci.isEmpty { items = Self.deduped(ci) }
        if !cl.isEmpty { locations = Self.deduped(cl) }
        if !cc.isEmpty { categories = Self.deduped(cc) }

        // Stage 2: refresh from server (spinner only if cache was empty)
        let hadCachedData = !ci.isEmpty || !cl.isEmpty || !cc.isEmpty
        isLoading = !hadCachedData
        do {
            async let serverItems = service.fetchItems(source: .server)
            async let serverLocations = service.fetchLocations(source: .server)
            async let serverCategories = service.fetchCategories(source: .server)
            items = Self.deduped(try await serverItems)
            locations = Self.deduped(try await serverLocations)
            categories = Self.deduped(try await serverCategories)
        } catch {
            // Keep cached data; only surface error if we have nothing
            if !hadCachedData {
                errorMessage = error.localizedDescription
            }
        }
        isLoading = false

        // Wire up offline photo upload handler + process any pending uploads
        setupPhotoUploadHandler()
        await uploadManager.processPending()
    }

    // MARK: - Item CRUD

    func addItem(name: String, notes: String?, locationId: String?, categoryId: String?) async {
        let item = Item(name: name, notes: notes, locationId: locationId, categoryId: categoryId, locationChangedAt: locationId != nil ? .now : nil)
        do {
            try await service.addItem(item)
            if !items.contains(where: { $0.id == item.id }) {
                items.append(item)
            }
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
        // Remove from local state synchronously so SwiftUI's swipe-delete animation
        // and the data source stay in sync. Remote cleanup happens after.
        items.removeAll { $0.id == item.id }
        uploadManager.removeLocal(itemId: item.id, filename: "photo")
        uploadManager.removeLocal(itemId: item.id, filename: "item_photo")
        HapticManager.impact()

        do {
            try await service.deleteItem(item)
        } catch {
            errorMessage = error.localizedDescription
        }
        for url in [item.photoURL, item.itemPhotoURL].compactMap({ $0 }) {
            if url.hasPrefix("http") || url.hasPrefix("gs://") {
                try? await storageService.deletePhoto(url: url)
            }
        }
    }

    // MARK: - Photo (offline-first)

    private let uploadManager = PhotoUploadManager.shared

    func setupPhotoUploadHandler() {
        uploadManager.onUploadComplete = { [weak self] itemId, filename, remoteURL in
            guard let self else { return }
            guard let index = items.firstIndex(where: { $0.id == itemId }) else { return }
            var updated = items[index]
            // Evict local URL from cache
            let field = filename == "photo" ? updated.photoURL : updated.itemPhotoURL
            if let old = field, let url = URL(string: old) {
                ImageCache.shared.evict(for: url)
            }
            // Swap to remote URL
            if filename == "photo" {
                updated.photoURL = remoteURL
            } else {
                updated.itemPhotoURL = remoteURL
            }
            updated.updatedAt = .now
            try? await service.updateItem(updated)
            // Re-resolve index — item may have been deleted during the await
            guard let freshIndex = items.firstIndex(where: { $0.id == itemId }) else {
                // updateItem was an upsert; clean up the resurrected doc.
                try? await service.deleteItem(updated)
                return
            }
            items[freshIndex] = updated
        }
    }

    func setPhoto(for item: Item, imageData: Data) async {
        // Bail if item was deleted before this call ran (avoids upsert recreation).
        guard items.contains(where: { $0.id == item.id }) else { return }
        guard let compressed = ImageHelper.compress(imageData) else { return }
        let oldRemote = item.photoURL?.hasPrefix("file") == true ? nil : item.photoURL
        if let oldURL = item.photoURL, let url = URL(string: oldURL) {
            ImageCache.shared.evict(for: url)
        }

        // Save locally — instant
        let localURL = uploadManager.saveLocally(itemId: item.id, imageData: compressed, filename: "photo")
        var updated = item
        updated.photoURL = localURL.absoluteString
        updated.updatedAt = .now
        do {
            try await service.updateItem(updated)
            // Re-check after await — item may have been deleted during the suspension.
            guard let index = items.firstIndex(where: { $0.id == updated.id }) else {
                try? await service.deleteItem(updated)
                uploadManager.removeLocal(itemId: item.id, filename: "photo")
                return
            }
            items[index] = updated
            HapticManager.success()
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        // Queue background upload
        uploadManager.enqueueUpload(itemId: item.id, filename: "photo", localURL: localURL, oldRemoteURL: oldRemote)
    }

    func setItemPhoto(for item: Item, imageData: Data) async {
        // Bail if item was deleted before this call ran (avoids upsert recreation).
        guard items.contains(where: { $0.id == item.id }) else { return }
        guard let compressed = ImageHelper.compress(imageData) else { return }
        let oldRemote = item.itemPhotoURL?.hasPrefix("file") == true ? nil : item.itemPhotoURL
        if let oldURL = item.itemPhotoURL, let url = URL(string: oldURL) {
            ImageCache.shared.evict(for: url)
        }

        // Save locally — instant
        let localURL = uploadManager.saveLocally(itemId: item.id, imageData: compressed, filename: "item_photo")
        var updated = item
        updated.itemPhotoURL = localURL.absoluteString
        updated.updatedAt = .now
        do {
            try await service.updateItem(updated)
            // Re-check after await — item may have been deleted during the suspension.
            guard let index = items.firstIndex(where: { $0.id == updated.id }) else {
                try? await service.deleteItem(updated)
                uploadManager.removeLocal(itemId: item.id, filename: "item_photo")
                return
            }
            items[index] = updated
            HapticManager.success()
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        // Queue background upload
        uploadManager.enqueueUpload(itemId: item.id, filename: "item_photo", localURL: localURL, oldRemoteURL: oldRemote)
    }

    func deletePhoto(for item: Item) async {
        guard let urlString = item.photoURL else { return }
        if let url = URL(string: urlString) {
            ImageCache.shared.evict(for: url)
        }
        uploadManager.removeLocal(itemId: item.id, filename: "photo")
        do {
            if !urlString.hasPrefix("file") {
                try? await storageService.deletePhoto(url: urlString)
            }
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

    /// Find the item currently paired to a given NFC tag serial.
    func item(forTagUID uid: String) -> Item? {
        items.first { $0.nfcTagUID == uid }
    }

    /// Clear NFC tag pairing on a given item. Used when reassigning a tag.
    func clearNFCTag(itemId: String) async {
        guard let index = items.firstIndex(where: { $0.id == itemId }) else { return }
        var updated = items[index]
        updated.nfcTagUID = nil
        await updateItem(updated)
    }

    /// Set a tag UID on an item without bumping locationChangedAt.
    func setNFCTag(itemId: String, uid: String) async {
        guard let index = items.firstIndex(where: { $0.id == itemId }) else { return }
        var updated = items[index]
        updated.nfcTagUID = uid
        await updateItem(updated)
    }

    /// Update both location and (optionally) location photo from an NFC scan.
    func applyNFCUpdate(itemId: String, locationId: String?, photoData: Data?) async {
        guard let index = items.firstIndex(where: { $0.id == itemId }) else { return }
        var updated = items[index]
        updated.locationId = locationId
        updated.locationChangedAt = .now
        await updateItem(updated)
        if let photoData {
            let refreshed = items.first(where: { $0.id == itemId }) ?? updated
            await setPhoto(for: refreshed, imageData: photoData)
        }
    }

    func moveItem(_ item: Item, toLocationId: String?) async {
        var updated = item
        updated.locationId = toLocationId
        updated.locationChangedAt = .now
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

    func addLocation(name: String, emoji: String?, parentId: String? = nil) async {
        let location = Location(name: name, emoji: emoji, parentId: parentId)
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
            // Promote children to deleted location's parent
            for i in locations.indices where locations[i].parentId == location.id {
                locations[i].parentId = location.parentId
                try await service.updateLocation(locations[i])
            }
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
