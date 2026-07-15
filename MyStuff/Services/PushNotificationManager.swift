import Foundation
import FirebaseAuth
import FirebaseFirestore
import UserNotifications
import UIKit

/// Owns notification permission, FCM-token persistence, and tap→navigation intents.
@MainActor
@Observable
final class PushNotificationManager {
    static let shared = PushNotificationManager()
    private init() {}

    var currentFCMToken: String?

    // Nav intents consumed by ContentView after a notification tap.
    var pendingItemId: String?
    var pendingLocationId: String?
    var openFriends: Bool = false

    /// Ask for alert permission and register with APNs. Safe to call repeatedly.
    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            Task { @MainActor in UIApplication.shared.registerForRemoteNotifications() }
        }
    }

    /// Persist the current FCM token under the signed-in user (token = doc id, dedup-free).
    func saveTokenIfPossible() {
        guard let uid = Auth.auth().currentUser?.uid, let token = currentFCMToken else { return }
        Firestore.firestore()
            .collection("users").document(uid)
            .collection("fcmTokens").document(token)
            .setData(["token": token, "platform": "ios", "updatedAt": FieldValue.serverTimestamp()], merge: true)
    }

    /// Parse a notification payload into a nav intent.
    func handleTap(userInfo: [AnyHashable: Any]) {
        switch userInfo["type"] as? String {
        case "itemShared":
            if let id = userInfo["itemId"] as? String { pendingItemId = id }
        case "locationShared":
            if let id = userInfo["locationId"] as? String { pendingLocationId = id }
        case "friendRequest", "friendAccepted":
            openFriends = true
        default:
            break
        }
    }
}
