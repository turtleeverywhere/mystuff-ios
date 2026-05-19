import SwiftUI

/// Central palette. Change a hex value here to update the color across the app.
enum AppColor {
    case background  // #1F363D — darkest, intended for surfaces / backgrounds
    case primary     // #40798C — primary brand
    case secondary   // #70A9A1 — secondary brand
    case tertiary    // #9EC1A3 — tertiary / muted
    case text        // #CFE0C3 — default foreground for text
    case accent      // #EE7674 — accent / call-to-action / alert

    var color: Color {
        switch self {
        case .background: return Color(hex: 0x1F363D)
        case .primary:    return Color(hex: 0x40798C)
        case .secondary:  return Color(hex: 0x70A9A1)
        case .tertiary:   return Color(hex: 0x9EC1A3)
        case .text:       return Color(hex: 0xCFE0C3)
        case .accent:     return Color(hex: 0xEE7674)
        }
    }
}

extension Color {
    static var appBackground: Color { AppColor.background.color }
    static var appPrimary: Color    { AppColor.primary.color }
    static var appSecondary: Color  { AppColor.secondary.color }
    static var appTertiary: Color   { AppColor.tertiary.color }
    static var appText: Color       { AppColor.text.color }
    static var appAccent: Color     { AppColor.accent.color }

    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >>  8) & 0xFF) / 255
        let b = Double( hex        & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

extension LinearGradient {
    /// Default app background gradient — mid-blue → cream, top to bottom.
    static let appBackground = LinearGradient(
        colors: [.appPrimary, .appText],
        startPoint: .top,
        endPoint: .bottom
    )
}
