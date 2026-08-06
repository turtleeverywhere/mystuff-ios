import Foundation

struct Item: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var name: String
    var notes: String?
    var locationId: String?
    /// Location this item is *supposed* to live in. nil = no expected place, so the
    /// item can never be misplaced. Optional so legacy docs decode cleanly — same
    /// idiom as ownerId/memberIds.
    var homeLocationId: String?
    var categoryId: String?
    /// Local hint — relative path "Photos/{id}_photo.jpg" or nil. Primary store for location photo.
    var photoURL: String?
    /// Local hint — relative path "Photos/{id}_item_photo.jpg" or nil. Primary store for item photo.
    var itemPhotoURL: String?
    /// Firebase Storage URL for location photo (full size). Used for cross-device sync.
    var remotePhotoURL: String?
    /// Firebase Storage URL for item photo (full size). Used for cross-device sync.
    var remoteItemPhotoURL: String?
    var locationChangedAt: Date?
    var nfcTagUID: String?
    /// Legacy single-tag field above is kept for decode only. All paired tags
    /// live here; reads go through `pairedTags`, which prefers this list and
    /// only falls back to the legacy field while this is still nil.
    var nfcTags: [NFCTag]?
    /// When true, automatic member-propagation flows (e.g. moveLocation subtree share)
    /// skip this item. Manual sharing is unaffected. Optional so legacy docs missing the
    /// field decode cleanly — same idiom as ownerId/memberIds.
    var isPrivate: Bool?
    /// Owner's uid. Writes route to `users/{ownerId}/items`. nil on legacy docs until migrated.
    var ownerId: String?
    /// `[ownerId] + sharedWith`. The array queried for visibility. nil on legacy docs until migrated.
    var memberIds: [String]?
    /// Transient marker set on every write in a coalesced share/move batch. Cloud Functions
    /// use it to suppress per-doc push notifications (one summary push covers the batch).
    /// Optional so legacy docs missing the field decode cleanly.
    var shareBatchId: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        name: String,
        notes: String? = nil,
        locationId: String? = nil,
        homeLocationId: String? = nil,
        categoryId: String? = nil,
        photoURL: String? = nil,
        itemPhotoURL: String? = nil,
        remotePhotoURL: String? = nil,
        remoteItemPhotoURL: String? = nil,
        locationChangedAt: Date? = nil,
        nfcTagUID: String? = nil,
        nfcTags: [NFCTag]? = nil,
        isPrivate: Bool? = nil,
        ownerId: String? = nil,
        memberIds: [String]? = nil,
        shareBatchId: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.notes = notes
        self.locationId = locationId
        self.homeLocationId = homeLocationId
        self.categoryId = categoryId
        self.photoURL = photoURL
        self.itemPhotoURL = itemPhotoURL
        self.remotePhotoURL = remotePhotoURL
        self.remoteItemPhotoURL = remoteItemPhotoURL
        self.locationChangedAt = locationChangedAt
        self.nfcTagUID = nfcTagUID
        self.nfcTags = nfcTags
        self.isPrivate = isPrivate
        self.ownerId = ownerId
        self.memberIds = memberIds
        self.shareBatchId = shareBatchId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// True when this item has a home location and is not currently in it.
    /// Matching is exact: sitting in a *child* of the home location still counts as
    /// misplaced, and a nil `locationId` counts as misplaced. Views must not read
    /// this directly — go through `StuffViewModel.isMisplaced(_:)`, which also
    /// verifies the home location still exists.
    var isMisplaced: Bool {
        guard let homeLocationId else { return false }
        return locationId != homeLocationId
    }

    /// Non-optional membership convenience; falls back to `[ownerId]` for legacy docs.
    var members: [String] {
        if let memberIds, !memberIds.isEmpty { return memberIds }
        if let ownerId { return [ownerId] }
        return []
    }

    /// Non-optional tag list. A non-nil `nfcTags` means this item has been
    /// migrated, so it wins even when empty — otherwise unpairing the last
    /// tag would fall back to the legacy field and resurrect it. (The legacy
    /// field survives in Firestore because `merge: true` writes omit nil.)
    var pairedTags: [NFCTag] {
        if let nfcTags { return nfcTags }
        if let nfcTagUID { return [NFCTag(uid: nfcTagUID)] }
        return []
    }
}
