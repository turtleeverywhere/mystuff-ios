import Foundation

/// One recognition sample for an item: an embedding vector plus bookkeeping.
/// Lives on-device only (see `RecognitionStore`); never written to Firestore.
struct ItemReference: Codable, Identifiable, Hashable, Sendable {
    enum Source: String, Codable, Sendable {
        /// Derived from the item's item photo. At most one per item.
        case itemPhoto
        /// Captured by the user through "Add angles".
        case enrolled
        /// A scan capture the user confirmed for this item.
        case learned
    }

    var id: String
    var itemId: String
    var source: Source
    /// Model + revision that produced `vector`. Vectors only compare within one modelID.
    var modelID: String
    var vector: [Float]
    /// `itemPhoto` only: `remoteItemPhotoURL ?? itemPhotoURL` at embed time, to detect a changed photo.
    var sourceKey: String?
    var createdAt: Date

    init(
        id: String = UUID().uuidString,
        itemId: String,
        source: Source,
        modelID: String,
        vector: [Float],
        sourceKey: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.itemId = itemId
        self.source = source
        self.modelID = modelID
        self.vector = vector
        self.sourceKey = sourceKey
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, itemId, source, modelID, vector, sourceKey, createdAt
    }

    /// The vector is stored as raw Float32 bytes — a third the size of a plist number array.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        itemId = try container.decode(String.self, forKey: .itemId)
        source = try container.decode(Source.self, forKey: .source)
        modelID = try container.decode(String.self, forKey: .modelID)
        vector = [Float](rawData: try container.decode(Data.self, forKey: .vector))
        sourceKey = try container.decodeIfPresent(String.self, forKey: .sourceKey)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(itemId, forKey: .itemId)
        try container.encode(source, forKey: .source)
        try container.encode(modelID, forKey: .modelID)
        try container.encode(vector.rawData, forKey: .vector)
        try container.encodeIfPresent(sourceKey, forKey: .sourceKey)
        try container.encode(createdAt, forKey: .createdAt)
    }
}

extension Array where Element == Float {
    /// Reads raw Float32 bytes. Trailing bytes that don't fill a Float are dropped.
    init(rawData: Data) {
        let count = rawData.count / MemoryLayout<Float>.size
        self = rawData.withUnsafeBytes { bytes in
            (0..<count).map { bytes.loadUnaligned(fromByteOffset: $0 * MemoryLayout<Float>.size, as: Float.self) }
        }
    }

    var rawData: Data {
        withUnsafeBufferPointer { Data(buffer: $0) }
    }
}
