import SwiftUI

/// Small capsule marking an item as paired to an NFC tag.
struct NFCBadge: View {
    var iconOnly: Bool = false

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "wave.3.right")
                .font(.caption2)
            if !iconOnly {
                Text("Tag")
                    .font(.caption2)
            }
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, iconOnly ? 6 : 8)
        .padding(.vertical, 3)
        .background(.ultraThinMaterial, in: Capsule())
    }
}
