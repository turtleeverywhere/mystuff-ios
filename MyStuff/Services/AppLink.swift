import Foundation

/// Universal-link router for the app's deep-link targets.
/// URLs look like `https://mystuff.coding-turtle.org/{item|location}/<uuid>`.
enum AppLink {
    static let host = "mystuff.coding-turtle.org"

    enum Target: Equatable {
        case item(String)
        case location(String)
    }

    private static let itemPrefix = "/item/"
    private static let locationPrefix = "/location/"

    static func url(for target: Target) -> URL {
        let path: String
        switch target {
        case .item(let id): path = itemPrefix + id
        case .location(let id): path = locationPrefix + id
        }
        return URL(string: "https://\(host)\(path)")!
    }

    static func parse(_ url: URL) -> Target? {
        guard url.scheme == "https", url.host == host else { return nil }
        if url.path.hasPrefix(itemPrefix) {
            let id = String(url.path.dropFirst(itemPrefix.count))
            return id.isEmpty ? nil : .item(id)
        }
        if url.path.hasPrefix(locationPrefix) {
            let id = String(url.path.dropFirst(locationPrefix.count))
            return id.isEmpty ? nil : .location(id)
        }
        return nil
    }
}
