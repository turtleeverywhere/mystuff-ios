import UIKit
import FirebaseCore
import FirebaseMessaging
import UserNotifications

/// Notification payload dictionaries aren't Sendable; this box lets us hop
/// them from the (nonisolated) delegate callback over to the main actor.
private struct UncheckedSendableBox<Value>: @unchecked Sendable {
    let value: Value
}

final class AppDelegate: NSObject, UIApplicationDelegate, MessagingDelegate, UNUserNotificationCenterDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        Messaging.messaging().delegate = self
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    // APNs token → FCM.
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }

    // FCM registration token (may fire before sign-in).
    nonisolated func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        Task { @MainActor in
            PushNotificationManager.shared.currentFCMToken = fcmToken
            PushNotificationManager.shared.saveTokenIfPossible()
        }
    }

    // Show banners while the app is foregrounded.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }

    // Tap → stash a nav intent for ContentView.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        let box = UncheckedSendableBox(value: response.notification.request.content.userInfo)
        await MainActor.run { PushNotificationManager.shared.handleTap(userInfo: box.value) }
    }
}
