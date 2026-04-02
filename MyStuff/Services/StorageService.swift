import Foundation

protocol StorageService: Sendable {
    func uploadPhoto(itemId: String, imageData: Data, filename: String) async throws -> String
    func deletePhoto(url: String) async throws
}
