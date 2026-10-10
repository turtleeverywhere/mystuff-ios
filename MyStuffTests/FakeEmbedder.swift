import Foundation
@testable import MyStuff

/// Reads the "image" bytes as comma-separated floats: `Data("1,0".utf8)` embeds
/// to `[1, 0]`. Anything else throws, standing in for an unreadable photo.
struct FakeEmbedder: ImageEmbedder {
    var modelID = "fake-1"

    func embed(imageData: Data) async throws -> Embedding {
        let parts = String(decoding: imageData, as: UTF8.self).split(separator: ",").map { Float($0) }
        guard !parts.isEmpty, !parts.contains(nil) else { throw EmbeddingError.unreadableImage }
        return Embedding(vector: parts.compactMap { $0 }, thumbnail: imageData)
    }
}

extension Embedding {
    /// An embedding whose thumbnail re-embeds to the same vector under `FakeEmbedder`.
    static func fake(_ vector: [Float]) -> Embedding {
        Embedding(vector: vector, thumbnail: Data(vector.map { "\($0)" }.joined(separator: ",").utf8))
    }
}

extension Data {
    /// Fake image bytes for `FakeEmbedder`.
    static func fakeImage(_ vector: [Float]) -> Data { Embedding.fake(vector).thumbnail }
}
