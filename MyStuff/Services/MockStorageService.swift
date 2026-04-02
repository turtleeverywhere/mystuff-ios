import Foundation

final class MockStorageService: StorageService, @unchecked Sendable {

    func uploadPhoto(itemId: String, imageData: Data, filename: String) async throws -> String {
        "mock://photo-\(UUID().uuidString)"
    }

    func deletePhoto(url: String) async throws {}
}
