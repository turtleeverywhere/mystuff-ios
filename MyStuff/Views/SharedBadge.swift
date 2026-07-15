import SwiftUI

/// Small capsule marking an entity as shared, or (with ownerName) shared *with me* by someone.
struct SharedBadge: View {
    var iconOnly: Bool = false
    var ownerName: String? = nil

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "person.2.fill")
                .font(.caption2)
            if !iconOnly {
                Text(ownerName.map { "Shared by \($0)" } ?? "Shared")
                    .font(.caption2)
            }
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, iconOnly ? 6 : 8)
        .padding(.vertical, 3)
        .background(.ultraThinMaterial, in: Capsule())
    }
}
