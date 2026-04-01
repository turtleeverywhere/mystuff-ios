import Foundation

/// In-memory implementation of DataService for development and previews.
final class MockDataService: DataService, @unchecked Sendable {

    private var items: [Item]
    private var locations: [Location]

    init() {
        let livingRoom = Location(id: "loc-1", name: "Living Room", emoji: "🛋️")
        let garage = Location(id: "loc-2", name: "Garage", emoji: "🚗")
        let office = Location(id: "loc-3", name: "Office", emoji: "🖥️")
        let cellar = Location(id: "loc-4", name: "Cellar", emoji: "📦")
        let car = Location(id: "loc-5", name: "Car", emoji: "🚙")

        self.locations = [livingRoom, garage, office, cellar, car]

        self.items = [
            Item(id: "item-1", name: "TV Remote", notes: "Samsung remote, silver", locationId: "loc-1"),
            Item(id: "item-2", name: "Drill", notes: "Bosch cordless", locationId: "loc-2"),
            Item(id: "item-3", name: "Passport", notes: "Expires 2028", locationId: "loc-3"),
            Item(id: "item-4", name: "Christmas Decorations", notes: "3 boxes", locationId: "loc-4"),
            Item(id: "item-5", name: "Umbrella", locationId: "loc-5"),
            Item(id: "item-6", name: "Spare Keys", notes: "Front door + mailbox"),
            Item(id: "item-7", name: "Camping Tent", notes: "4-person tent"),
            Item(id: "item-8", name: "Headphones", notes: "AirPods Max", locationId: "loc-3"),
            Item(id: "item-9", name: "Board Games", notes: "Catan, Ticket to Ride", locationId: "loc-1"),
            Item(id: "item-10", name: "Winter Tires", locationId: "loc-2"),
        ]
    }

    // MARK: - Items

    func fetchItems() async throws -> [Item] {
        items
    }

    func addItem(_ item: Item) async throws {
        items.append(item)
    }

    func updateItem(_ item: Item) async throws {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
        }
    }

    func deleteItem(_ item: Item) async throws {
        items.removeAll { $0.id == item.id }
    }

    // MARK: - Locations

    func fetchLocations() async throws -> [Location] {
        locations
    }

    func addLocation(_ location: Location) async throws {
        locations.append(location)
    }

    func updateLocation(_ location: Location) async throws {
        if let index = locations.firstIndex(where: { $0.id == location.id }) {
            locations[index] = location
        }
    }

    func deleteLocation(_ location: Location) async throws {
        locations.removeAll { $0.id == location.id }
    }
}
