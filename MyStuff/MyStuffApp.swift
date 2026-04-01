import SwiftUI
import FirebaseCore
import GoogleSignIn

@main
struct MyStuffApp: App {

    @State private var authService = AuthService()

    init() {
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootView(authService: authService)
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
