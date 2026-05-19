import SwiftUI

struct SignInView: View {
    @Bindable var authService: AuthService
    @State private var isAnimating = false

    var body: some View {
        ZStack {
            LinearGradient.appBackground
                .ignoresSafeArea()

            VStack(spacing: 40) {
                Spacer()

                // App icon & title
                VStack(spacing: 16) {
                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: 72))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.primary)
                        .scaleEffect(isAnimating ? 1.0 : 0.8)
                        .opacity(isAnimating ? 1.0 : 0.0)
                        .animation(.spring(duration: 0.8, bounce: 0.4), value: isAnimating)

                    Text("MyStuff")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .opacity(isAnimating ? 1.0 : 0.0)
                        .offset(y: isAnimating ? 0 : 20)
                        .animation(.easeOut(duration: 0.6).delay(0.2), value: isAnimating)

                    Text("Know where everything lives.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .opacity(isAnimating ? 1.0 : 0.0)
                        .offset(y: isAnimating ? 0 : 10)
                        .animation(.easeOut(duration: 0.6).delay(0.4), value: isAnimating)
                }

                Spacer()

                // Sign-in card
                VStack(spacing: 20) {
                    Button {
                        Task { await authService.signInWithGoogle() }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "person.badge.key.fill")
                                .font(.title3)
                            Text("Sign in with Google")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.roundedRectangle(radius: 14))
                    .tint(.primary.opacity(0.85))

                    if let error = authService.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .transition(.opacity)
                    }

                    Text("Your data is stored securely and privately.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(28)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
                .padding(.horizontal, 24)
                .opacity(isAnimating ? 1.0 : 0.0)
                .offset(y: isAnimating ? 0 : 30)
                .animation(.easeOut(duration: 0.6).delay(0.6), value: isAnimating)

                Spacer()
                    .frame(height: 40)
            }
        }
        .onAppear { isAnimating = true }
    }
}

#Preview {
    SignInView(authService: AuthService())
}
