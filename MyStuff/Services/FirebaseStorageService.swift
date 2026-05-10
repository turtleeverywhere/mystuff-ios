import FirebaseAuth
import FirebaseStorage
import Foundation

final class FirebaseStorageService: StorageService, @unchecked Sendable {

    private var storageRef: StorageReference {
        Storage.storage().reference()
    }

    private var uid: String {
        Auth.auth().currentUser!.uid
    }

    func uploadPhoto(itemId: String, imageData: Data, filename: String) async throws -> String {
        let ref = storageRef.child("users/\(uid)/items/\(itemId)/\(filename).jpg")
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        _ = try await ref.putDataAsync(imageData, metadata: metadata)
        let url = try await ref.downloadURL()
        return url.absoluteString
    }

    func deletePhoto(url: String) async throws {
        let ref = Storage.storage().reference(forURL: url)
        try await ref.delete()
    }
}
