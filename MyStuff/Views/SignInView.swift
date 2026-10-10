import SwiftUI

struct SignInView: View {
    @Bindable var authService: AuthService
    @State private var isSigningIn = false
    @ScaledMetric(relativeTo: .largeTitle) private var iconSize = 64

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                VStack(alignment: .leading, spacing: 24) {
                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: iconSize))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.appPrimary)
                        .padding(24)
                        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 28))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 12) {
                        Text("MyStuff")
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                            .foregroundStyle(Color.appText)
                        Text("Less searching.\nMore living.")
                            .font(.system(.title, design: .rounded, weight: .semibold))
                            .foregroundStyle(Color.appText)
                        Text("Keep track of what you own and where it lives.")
                            .font(.body).foregroundStyle(Color.appTertiary)
                    }
                }
                VStack(alignment: .leading, spacing: 20) {
                    benefit("A place for everything", detail: "Organize items by room, shelf, or box.", symbol: "mappin.and.ellipse")
                    benefit("Find it when you need it", detail: "Search your inventory in seconds.", symbol: "magnifyingglass")
                    benefit("Always with you", detail: "Your inventory syncs across your devices.", symbol: "icloud")
                }

            }
            .padding(24)
            .padding(.vertical, 24)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background(LinearGradient.appBackground.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            signInCard
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
        }
    }

    private var signInCard: some View {
        VStack(spacing: 16) {
            Button {
                guard !isSigningIn else { return }
                isSigningIn = true
                Task {
                    await authService.signInWithGoogle()
                    isSigningIn = false
                }
            } label: {
                HStack(spacing: 12) {
                    if isSigningIn { ProgressView().tint(Color.appOnHero) }
                    Text(isSigningIn ? "Signing in…" : "Continue with Google").font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(Color.appOnHero)
                .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 16))
            .tint(Color.appHero)
            .disabled(isSigningIn)
            if let error = authService.errorMessage {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.subheadline).foregroundStyle(Color.appAccent)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Label("Your inventory is private by default.", systemImage: "lock")
                .font(.caption).foregroundStyle(Color.appTertiary)
        }
        .padding(24)
        .appCard()
    }

    private func benefit(_ title: String, detail: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol)
                .font(.title3).foregroundStyle(Color.appPrimary)
                .frame(width: 28, height: 28).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline).foregroundStyle(Color.appText)
                Text(detail).font(.subheadline).foregroundStyle(Color.appTertiary)
            }
        }
    }
}

#Preview { SignInView(authService: AuthService()) }
