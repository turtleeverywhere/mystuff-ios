import Foundation

/// Minimal public-facing profile stored at `users/{uid}`. Written on sign-in;
/// resolved by email through the `lookupUserByEmail` Cloud Function.
struct UserProfile: Identifiable, Codable, Hashable, Sendable {
    var uid: String
    /// Normalized: trimmed + lowercased.
    var email: String
    var displayName: String
    var photoURL: String?

    var id: String { uid }

    init(uid: String, email: String, displayName: String, photoURL: String? = nil) {
        self.uid = uid
        self.email = email
        self.displayName = displayName
        self.photoURL = photoURL
    }
}
