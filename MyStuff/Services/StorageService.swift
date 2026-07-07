import Foundation

protocol StorageService: Sendable {
    /// Uploads `imageData` under a deterministic path. `filename` is the base (e.g. "photo" or "photo_thumb").
    func uploadPhoto(itemId: String, imageData: Data, filename: String) async throws -> String
    func deletePhoto(url: String) async throws
}
