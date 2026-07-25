import Foundation

/// Universal-link router for the app's deep-link targets.
/// URLs look like `https://mystuff.coding-turtle.org/{item|location}/<uuid>`.
enum AppLink {
    static let host = "mystuff.coding-turtle.org"

    enum Target: Equatable, Hashable, Identifiable {
        case item(String)
        case location(String)

        /// Stable, kind-qualified identity. Two entities of different kinds
        /// could in principle share a UUID, so the kind is part of the id.
        var id: String {
            switch self {
            case .item(let id): return "item:\(id)"
            case .location(let id): return "location:\(id)"
            }
        }

        /// The bare entity UUID, without the kind prefix.
        var entityId: String {
            switch self {
            case .item(let id), .location(let id): return id
            }
        }

        var kind: TargetKind {
            switch self {
            case .item: return .item
            case .location: return .location
            }
        }
    }

    /// Filter for scanners that only accept one kind of code.
    /// `Target.kind` never returns `.any`; it exists for the filter side only.
    enum TargetKind {
        case any, item, location

        func accepts(_ target: Target) -> Bool {
            switch self {
            case .any: return true
            case .item: return target.kind == .item
            case .location: return target.kind == .location
            }
        }

        /// Inline message shown when a scanned code is the wrong kind.
        var rejectionMessage: String {
            switch self {
            case .any: return "Not a MyStuff code"
            case .item: return "That's not an item code"
            case .location: return "That's not a location code"
            }
        }
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
