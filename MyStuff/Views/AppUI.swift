import SwiftUI

/// Shared presentation primitives; content stays in the feature views.
struct AppCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 24))
            .overlay {
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(Color.appBorder.opacity(0.7), lineWidth: 1)
                    .allowsHitTesting(false)
            }
    }
}

extension View {
    func appCard() -> some View { modifier(AppCard()) }
}

struct AppSectionHeading: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(Color.appText)
                .accessibilityAddTraits(.isHeader)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(Color.appTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}

struct LocationIcon: View {
    let emoji: String?
    var symbol = "mappin.and.ellipse"

    var body: some View {
        Group {
            if let emoji, !emoji.isEmpty {
                Text(emoji).font(.title2)
            } else {
                Image(systemName: symbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.appPrimary)
            }
        }
        // Decorative icons stay inside their tile while adjacent text scales.
        .dynamicTypeSize(.large)
        .frame(width: 44, height: 44)
        .background(Color.appSurfaceMuted, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityHidden(true)
    }
}

struct AppPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Color.appOnHero)
            .padding(.horizontal, 20)
            .frame(minHeight: 48)
            .background(Color.appHero, in: RoundedRectangle(cornerRadius: 16))
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
    }
}

/// Explicit opt-in to isolated demo data for visual QA; unavailable in release builds.
enum AppPreview {
    static var isEnabled: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-ui-preview")
        #else
        false
        #endif
    }

    /// Opens the normal post-scan sheet with a demo item, without scanner hardware.
    static var itemId: String? {
        guard isEnabled else { return nil }
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-ui-preview-item"),
              arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }
}
