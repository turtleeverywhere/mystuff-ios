import SwiftUI

/// Small capsule marking an item as away from its supposed location.
struct MisplacedBadge: View {
    var iconOnly: Bool = false

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
            if !iconOnly {
                Text("Misplaced")
                    .font(.caption2)
            }
        }
        .foregroundStyle(.orange)
        .padding(.horizontal, iconOnly ? 6 : 8)
        .padding(.vertical, 3)
        .background(.ultraThinMaterial, in: Capsule())
        .accessibilityLabel("Misplaced")
    }
}

/// Context-menu entry that returns an item to its supposed location. Renders nothing
/// when the item is not misplaced, so callers can drop it into any menu unconditionally.
struct PutBackMenuButton: View {
    let item: Item
    let viewModel: StuffViewModel

    var body: some View {
        if viewModel.isMisplaced(item) {
            Button {
                Task { await viewModel.putBackItems([item]) }
            } label: {
                Label("Put Back", systemImage: "arrow.uturn.left.circle")
            }
        }
    }
}
