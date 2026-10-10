import SwiftUI
import UIKit

/// Semantic colors keep surfaces and controls readable in both appearances.
enum AppColor {
    case background, primary, secondary, tertiary, text, accent

    var color: Color {
        switch self {
        case .background: return .adaptive(light: 0xF3F6F5, dark: 0x101C20)
        case .primary: return .adaptive(light: 0x256374, dark: 0x8DCED3)
        case .secondary: return .adaptive(light: 0x376D64, dark: 0xA0CFC3)
        case .tertiary: return .adaptive(light: 0x52686D, dark: 0xAEC1C5)
        case .text: return .adaptive(light: 0x18343B, dark: 0xE6F0ED)
        case .accent: return .adaptive(light: 0xAA4342, dark: 0xFFABA4)
        }
    }
}

extension Color {
    static var appBackground: Color { AppColor.background.color }
    static var appPrimary: Color { AppColor.primary.color }
    static var appSecondary: Color { AppColor.secondary.color }
    static var appTertiary: Color { AppColor.tertiary.color }
    static var appText: Color { AppColor.text.color }
    static var appAccent: Color { AppColor.accent.color }
    static var appSurface: Color { .adaptive(light: 0xFFFFFF, dark: 0x1B2B30) }
    static var appSurfaceMuted: Color { .adaptive(light: 0xE7EFED, dark: 0x253A40) }
    static var appBorder: Color { .adaptive(light: 0xCDDCD8, dark: 0x3D555B) }
    static var appHero: Color { .adaptive(light: 0x234D58, dark: 0x203F48) }
    static var appOnHero: Color { .white }
    static var appHeroSecondary: Color { Color(hex: 0xD6E9E5) }

    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }

    init(hex: UInt32, alpha: Double = 1.0) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }
}

extension LinearGradient {
    static let appBackground = LinearGradient(
        colors: [.appBackground, .appSurfaceMuted],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}
