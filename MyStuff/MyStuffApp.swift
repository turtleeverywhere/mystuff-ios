import SwiftUI
import FirebaseCore
import FirebaseFirestore
import GoogleSignIn

@main
struct MyStuffApp: App {

    @State private var authService: AuthService

    init() {
        FirebaseApp.configure()

        // Enable persistent on-disk cache so lists render instantly on launch.
        let settings = FirestoreSettings()
        settings.cacheSettings = PersistentCacheSettings(
            sizeBytes: NSNumber(value: FirestoreCacheSizeUnlimited)
        )
        Firestore.firestore().settings = settings

        // Make table/collection/scroll chrome transparent so the global
        // background gradient shows through Lists and Forms.
        UITableView.appearance().backgroundColor = .clear
        UICollectionView.appearance().backgroundColor = .clear
        UIScrollView.appearance().backgroundColor = .clear

        // Transparent tab bar + navigation bar so the gradient shows through.
        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithTransparentBackground()
        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance

        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithTransparentBackground()
        UINavigationBar.appearance().standardAppearance = navAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
        UINavigationBar.appearance().compactAppearance = navAppearance

        _authService = State(initialValue: AuthService())
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                LinearGradient.appBackground.ignoresSafeArea()
                RootView(authService: authService)
                    .foregroundStyle(Color.appText)
            }
            .onOpenURL { url in
                GIDSignIn.sharedInstance.handle(url)
            }
        }
    }
}

/// Root view that switches between sign-in and the main app.
struct RootView: View {
    @Bindable var authService: AuthService

    var body: some View {
        Group {
            if authService.isLoading {
                ProgressView()
                    .scaleEffect(1.5)
            } else if authService.isSignedIn {
                ContentView(authService: authService)
                    .transition(.opacity)
            } else {
                SignInView(authService: authService)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: authService.isSignedIn)
        .animation(.easeInOut(duration: 0.3), value: authService.isLoading)
    }
}
