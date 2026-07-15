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

    /// Mirror of SocialViewModel.friends, synced by ContentView — lets sharing UI read
    /// friends off the already-threaded StuffViewModel without a SocialViewModel reference.
    var friends: [Friend] = []

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

    @ObservationIgnored private var syncTasks: [Task<Void, Never>] = []

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
        let visibleIds = Set(locations.map(\.id))
        return locations.filter { loc in
            // Root, or a shared child whose parent isn't visible to me (show it at root).
            guard let pid = loc.parentId else { return true }
            return !visibleIds.contains(pid)
        }
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
        if !ci.isEmpty { items = Self.deduped(Self.migratedPhotoFields(ci)) }
        if !cl.isEmpty { locations = Self.deduped(cl) }
        if !cc.isEmpty { categories = Self.deduped(cc) }

        // Stage 2: refresh from server (spinner only if cache was empty)
        let hadCachedData = !ci.isEmpty || !cl.isEmpty || !cc.isEmpty
        isLoading = !hadCachedData
        do {
            let currentUid = service.currentUserId
            await backfillOwnSharingFieldsIfNeeded(currentUid: currentUid)
            async let serverItems = service.fetchItems(source: .server)
            async let serverLocations = service.fetchLocations(source: .server)
            async let serverCategories = service.fetchCategories(source: .server)
            let rawItems = try await serverItems
            let rawLocations = try await serverLocations
            items = Self.deduped(Self.migratedPhotoFields(rawItems).map { Self.migratedSharingFields($0, currentUid: currentUid) })
            locations = Self.deduped(rawLocations.map { Self.migratedSharingFields($0, currentUid: currentUid) })
            categories = Self.deduped(try await serverCategories)
            // Persist any in-place migrations back to Firestore.
            await persistPhotoMigrationsIfNeeded(rawItems: rawItems)
            await persistSharingMigrationsIfNeeded(rawItems: rawItems, rawLocations: rawLocations, currentUid: currentUid)
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

    /// Start real-time listeners so shared/edited items, locations, and categories update live.
    /// Idempotent; call after `loadData()`. Cancel via `stopLiveSync()`.
    func startLiveSync() {
        guard syncTasks.isEmpty else { return }
        let currentUid = service.currentUserId
        let service = self.service

        syncTasks.append(Task { [weak self] in
            for await raw in service.itemsStream() {
                guard let self else { return }
                self.items = Self.deduped(Self.migratedPhotoFields(raw).map { Self.migratedSharingFields($0, currentUid: currentUid) })
            }
        })
        syncTasks.append(Task { [weak self] in
            for await raw in service.locationsStream() {
                guard let self else { return }
                self.locations = Self.deduped(raw.map { Self.migratedSharingFields($0, currentUid: currentUid) })
            }
        })
        syncTasks.append(Task { [weak self] in
            for await raw in service.categoriesStream() {
                guard let self else { return }
                self.categories = Self.deduped(raw)
            }
        })
    }

    /// Cancel live-sync tasks (removes the underlying Firestore listeners via stream termination).
    func stopLiveSync() {
        syncTasks.forEach { $0.cancel() }
        syncTasks.removeAll()
    }

    // MARK: - Photo schema migration
    //
    // Legacy `photoURL` / `itemPhotoURL` could be either a Firebase https URL (uploaded image)
    // or a file:// URL (offline-pending). New schema: those fields hold a local-relative
    // path like "Photos/{id}_photo.jpg"; the remote URL lives in `remotePhotoURL` /
    // `remoteItemPhotoURL`. Migrate transparently.

    private static func migratedPhotoFields(_ items: [Item]) -> [Item] {
        items.map { migratedPhotoFields($0) }
    }

    private static func migratedPhotoFields(_ item: Item) -> Item {
        var updated = item
        if let url = updated.photoURL {
            if url.hasPrefix("http") || url.hasPrefix("gs://") {
                if updated.remotePhotoURL == nil { updated.remotePhotoURL = url }
                updated.photoURL = nil
            } else if url.hasPrefix("file://") {
                // Stale absolute path from a prior install. Local file is gone.
                updated.photoURL = nil
            }
        }
        if let url = updated.itemPhotoURL {
            if url.hasPrefix("http") || url.hasPrefix("gs://") {
                if updated.remoteItemPhotoURL == nil { updated.remoteItemPhotoURL = url }
                updated.itemPhotoURL = nil
            } else if url.hasPrefix("file://") {
                updated.itemPhotoURL = nil
            }
        }
        return updated
    }

    private func persistPhotoMigrationsIfNeeded(rawItems: [Item]) async {
        for raw in rawItems {
            let migrated = Self.migratedPhotoFields(raw)
            let changed =
                raw.photoURL != migrated.photoURL
                || raw.itemPhotoURL != migrated.itemPhotoURL
                || raw.remotePhotoURL != migrated.remotePhotoURL
                || raw.remoteItemPhotoURL != migrated.remoteItemPhotoURL
            if changed {
                try? await service.updateItem(migrated)
            }
        }
    }

    // MARK: - Sharing schema migration
    //
    // Legacy Item/Location docs predate `ownerId`/`memberIds`. Backfill on load so
    // collectionGroup `memberIds arrayContains` queries (P2) find them, and writes
    // route to the correct owner subcollection.

    private static func migratedSharingFields(_ item: Item, currentUid: String) -> Item {
        var u = item
        let owner = u.ownerId ?? currentUid
        u.ownerId = owner
        if u.memberIds == nil || (u.memberIds?.isEmpty ?? true) { u.memberIds = [owner] }
        return u
    }

    private static func migratedSharingFields(_ location: Location, currentUid: String) -> Location {
        var u = location
        let owner = u.ownerId ?? currentUid
        u.ownerId = owner
        if u.memberIds == nil || (u.memberIds?.isEmpty ?? true) { u.memberIds = [owner] }
        return u
    }

    private func persistSharingMigrationsIfNeeded(rawItems: [Item], rawLocations: [Location], currentUid: String) async {
        for raw in rawItems {
            let migrated = Self.migratedSharingFields(raw, currentUid: currentUid)
            if raw.ownerId != migrated.ownerId || raw.memberIds != migrated.memberIds {
                try? await service.updateItem(migrated)
            }
        }
        for raw in rawLocations {
            let migrated = Self.migratedSharingFields(raw, currentUid: currentUid)
            if raw.ownerId != migrated.ownerId || raw.memberIds != migrated.memberIds {
                try? await service.updateLocation(migrated)
            }
        }
    }

    /// One-time-per-user backfill of `ownerId`/`memberIds` on the user's OWN docs, read via
    /// the pre-sharing per-owner path. Guarantees own docs carry `memberIds` so the
    /// collectionGroup `arrayContains` read returns them. Guarded by a UserDefaults flag.
    private func backfillOwnSharingFieldsIfNeeded(currentUid: String) async {
        guard !currentUid.isEmpty else { return }
        let key = "sharingBackfillDone_\(currentUid)"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        do {
            let ownItems = try await service.fetchOwnItems()
            for raw in ownItems {
                let migrated = Self.migratedSharingFields(raw, currentUid: currentUid)
                if raw.ownerId != migrated.ownerId || raw.memberIds != migrated.memberIds {
                    try? await service.updateItem(migrated)
                }
            }
            let ownLocations = try await service.fetchOwnLocations()
            for raw in ownLocations {
                let migrated = Self.migratedSharingFields(raw, currentUid: currentUid)
                if raw.ownerId != migrated.ownerId || raw.memberIds != migrated.memberIds {
                    try? await service.updateLocation(migrated)
                }
            }
            UserDefaults.standard.set(true, forKey: key)
        } catch {
            // Leave the flag unset so we retry on the next launch.
        }
    }

    // MARK: - Item CRUD

    func addItem(name: String, notes: String?, locationId: String?, categoryId: String?) async {
        let owner = service.currentUserId
        let item = Item(name: name, notes: notes, locationId: locationId, categoryId: categoryId, locationChangedAt: locationId != nil ? .now : nil, ownerId: owner, memberIds: [owner])
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
        for url in [item.remotePhotoURL, item.remoteItemPhotoURL].compactMap({ $0 }) {
            try? await storageService.deletePhoto(url: url)
        }
    }

    // MARK: - Photo (offline-first)

    private let uploadManager = PhotoUploadManager.shared

    func setupPhotoUploadHandler() {
        uploadManager.onUploadComplete = { [weak self] itemId, filename, remoteURL in
            guard let self else { return }
            guard let index = items.firstIndex(where: { $0.id == itemId }) else { return }
            var updated = items[index]
            if filename == "photo" {
                updated.remotePhotoURL = remoteURL
            } else {
                updated.remoteItemPhotoURL = remoteURL
            }
            updated.updatedAt = .now
            try? await service.updateItem(updated)
            guard let freshIndex = items.firstIndex(where: { $0.id == itemId }) else {
                // updateItem was an upsert; clean up the resurrected doc.
                try? await service.deleteItem(updated)
                return
            }
            items[freshIndex] = updated
        }
    }

    func setPhoto(for item: Item, imageData: Data) async {
        await setPhoto(for: item, imageData: imageData, filename: "photo")
    }

    func setItemPhoto(for item: Item, imageData: Data) async {
        await setPhoto(for: item, imageData: imageData, filename: "item_photo")
    }

    /// Shared photo-write path used by both location and item photos.
    private func setPhoto(for item: Item, imageData: Data, filename: String) async {
        // Bail if item was deleted before this call ran (avoids upsert recreation).
        guard items.contains(where: { $0.id == item.id }) else { return }
        guard let pair = ImageHelper.compressWithThumbnail(imageData) else { return }

        let oldRemote: String? = (filename == "photo") ? item.remotePhotoURL : item.remoteItemPhotoURL

        // Evict any cached entries pointing at the previous local files (so new bytes show).
        let fullURL = uploadManager.localFullURL(itemId: item.id, filename: filename)
        let thumbURL = uploadManager.localThumbURL(itemId: item.id, filename: filename)
        ImageCache.shared.evict(for: fullURL)
        ImageCache.shared.evict(for: thumbURL)

        // Save locally — instant.
        let relPath = uploadManager.saveLocally(
            itemId: item.id,
            fullData: pair.full,
            thumbData: pair.thumb,
            filename: filename
        )

        var updated = item
        if filename == "photo" {
            updated.photoURL = relPath
        } else {
            updated.itemPhotoURL = relPath
        }
        updated.updatedAt = .now
        do {
            try await service.updateItem(updated)
            guard let index = items.firstIndex(where: { $0.id == updated.id }) else {
                try? await service.deleteItem(updated)
                uploadManager.removeLocal(itemId: item.id, filename: filename)
                return
            }
            items[index] = updated
            HapticManager.success()
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        uploadManager.enqueueUpload(itemId: item.id, filename: filename, oldRemoteURL: oldRemote)
    }

    func deletePhoto(for item: Item) async {
        await deletePhoto(for: item, filename: "photo")
    }

    func deleteItemPhoto(for item: Item) async {
        await deletePhoto(for: item, filename: "item_photo")
    }

    private func deletePhoto(for item: Item, filename: String) async {
        let hadLocal = (filename == "photo") ? item.photoURL != nil : item.itemPhotoURL != nil
        let oldRemote: String? = (filename == "photo") ? item.remotePhotoURL : item.remoteItemPhotoURL
        guard hadLocal || oldRemote != nil else { return }

        uploadManager.removeLocal(itemId: item.id, filename: filename)

        var updated = item
        if filename == "photo" {
            updated.photoURL = nil
            updated.remotePhotoURL = nil
        } else {
            updated.itemPhotoURL = nil
            updated.remoteItemPhotoURL = nil
        }
        updated.updatedAt = .now

        do {
            try await service.updateItem(updated)
            if let index = items.firstIndex(where: { $0.id == updated.id }) {
                items[index] = updated
            }
            HapticManager.impact()
        } catch {
            errorMessage = error.localizedDescription
        }

        if let oldRemote {
            try? await storageService.deletePhoto(url: oldRemote)
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
        var updated = items.first(where: { $0.id == item.id }) ?? item
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
        let owner = service.currentUserId
        let location = Location(name: name, emoji: emoji, parentId: parentId, ownerId: owner, memberIds: [owner])
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

    // MARK: - Sharing

    /// Current signed-in uid, surfaced for views/badges.
    var currentUserId: String { service.currentUserId }

    /// Members an entity is shared with (everyone except its owner).
    func sharedMembers(of item: Item) -> [String] {
        item.members.filter { $0 != (item.ownerId ?? currentUserId) }
    }
    func sharedMembers(of location: Location) -> [String] {
        location.members.filter { $0 != (location.ownerId ?? currentUserId) }
    }

    func isShared(_ item: Item) -> Bool { !sharedMembers(of: item).isEmpty }
    func isShared(_ location: Location) -> Bool { !sharedMembers(of: location).isEmpty }

    /// True if this entity is owned by someone else (i.e. shared *with* me).
    func isSharedWithMe(_ item: Item) -> Bool { (item.ownerId ?? currentUserId) != currentUserId }
    func isSharedWithMe(_ location: Location) -> Bool { (location.ownerId ?? currentUserId) != currentUserId }

    /// Member uids of an item that are NOT members of `location` — i.e. who would lose
    /// visibility of the item's location if the item moved there. Drives the move/share dialog.
    func membersMissing(from location: Location, forItemMembers itemMembers: [String]) -> [String] {
        let locMembers = Set(location.members)
        return itemMembers.filter { !locMembers.contains($0) }
    }

    func shareItem(_ item: Item, withFriend friendUid: String) async {
        guard var updated = items.first(where: { $0.id == item.id }) else { return }
        guard !updated.members.contains(friendUid) else { return }
        updated.memberIds = updated.members + [friendUid]
        await persistItemMembers(updated)
    }

    func unshareItem(_ item: Item, fromFriend friendUid: String) async {
        guard var updated = items.first(where: { $0.id == item.id }) else { return }
        updated.memberIds = updated.members.filter { $0 != friendUid }
        await persistItemMembers(updated)
    }

    /// Reset an item to private: members become exactly `[owner]`.
    func makeItemPrivate(_ item: Item) async {
        guard var updated = items.first(where: { $0.id == item.id }) else { return }
        updated.memberIds = [updated.ownerId ?? currentUserId]
        await persistItemMembers(updated)
    }

    func shareLocation(_ location: Location, withFriend friendUid: String) async {
        guard var updated = locations.first(where: { $0.id == location.id }) else { return }
        guard !updated.members.contains(friendUid) else { return }
        updated.memberIds = updated.members + [friendUid]
        await persistLocationMembers(updated)
    }

    func unshareLocation(_ location: Location, fromFriend friendUid: String) async {
        guard var updated = locations.first(where: { $0.id == location.id }) else { return }
        updated.memberIds = updated.members.filter { $0 != friendUid }
        await persistLocationMembers(updated)
    }

    /// Add member uids to a location (union). Used to resolve a move/share conflict by
    /// sharing the destination location with the item's members.
    func addMembers(_ uids: [String], toLocation location: Location) async {
        guard var updated = locations.first(where: { $0.id == location.id }) else { return }
        var members = updated.members
        for uid in uids where !members.contains(uid) { members.append(uid) }
        updated.memberIds = members
        await persistLocationMembers(updated)
    }

    func friend(forUid uid: String) -> Friend? {
        friends.first { $0.uid == uid }
    }

    /// Sharing controls are owner-only — you can't reshare someone else's entity.
    func canManageSharing(of item: Item) -> Bool { !isSharedWithMe(item) }
    func canManageSharing(of location: Location) -> Bool { !isSharedWithMe(location) }

    /// Persist a membership change on an item. If the change removed *me* from the members,
    /// drop it from local state (it will no longer be returned by my collectionGroup query).
    private func persistItemMembers(_ item: Item) async {
        var updated = item
        updated.updatedAt = .now
        do {
            try await service.updateItem(updated)
            if updated.members.contains(currentUserId) {
                if let i = items.firstIndex(where: { $0.id == updated.id }) { items[i] = updated }
            } else {
                items.removeAll { $0.id == updated.id }
            }
            HapticManager.success()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func persistLocationMembers(_ location: Location) async {
        var updated = location
        do {
            try await service.updateLocation(updated)
            if updated.members.contains(currentUserId) {
                if let i = locations.firstIndex(where: { $0.id == updated.id }) { locations[i] = updated }
            } else {
                locations.removeAll { $0.id == updated.id }
            }
            HapticManager.success()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// On unfriend: remove the pair from every shared entity in the loaded set, in both
    /// directions — strip the friend from things I own, and strip me from things they own
    /// (allowed because a member may update, per security rules).
    func unshareEverything(withFriend friendUid: String) async {
        let me = currentUserId
        for item in items {
            let owner = item.ownerId ?? me
            if owner == me, item.members.contains(friendUid) {
                var u = item; u.memberIds = item.members.filter { $0 != friendUid }
                await persistItemMembers(u)
            } else if owner == friendUid, item.members.contains(me) {
                var u = item; u.memberIds = item.members.filter { $0 != me }
                await persistItemMembers(u)
            }
        }
        for location in locations {
            let owner = location.ownerId ?? me
            if owner == me, location.members.contains(friendUid) {
                var u = location; u.memberIds = location.members.filter { $0 != friendUid }
                await persistLocationMembers(u)
            } else if owner == friendUid, location.members.contains(me) {
                var u = location; u.memberIds = location.members.filter { $0 != me }
                await persistLocationMembers(u)
            }
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
