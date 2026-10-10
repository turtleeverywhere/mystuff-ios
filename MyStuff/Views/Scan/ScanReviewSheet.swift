import SwiftUI

/// The one confirmation step of a scan session: every collected item with where
/// it is going. Nothing has been written before Confirm.
struct ScanReviewSheet: View {
    let session: ScanSessionModel
    let viewModel: StuffViewModel
    /// Called after a successful move so the presenter can close the whole session.
    let onFinished: () -> Void

    @Environment(\.dismiss) private var dismiss
    /// Tracks exclusions so every item starts selected.
    @State private var deselected: Set<String> = []
    @State private var showDestinationPicker = false
    @State private var isSaving = false
    @State private var moveFailed = false

    private var destination: Location? {
        viewModel.locations.first { $0.id == session.destinationId }
    }

    private var trayItems: [Item] {
        session.trayItemIds.compactMap { id in viewModel.items.first { $0.id == id } }
    }

    private var chosen: [Item] {
        trayItems.filter { !deselected.contains($0.id) }
    }

    /// Chosen items that aren't already directly in the destination.
    private var toMove: [Item] {
        guard let destination else { return [] }
        return chosen.filter { $0.locationId != destination.id }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Destination") {
                    Button {
                        showDestinationPicker = true
                    } label: {
                        HStack(spacing: 10) {
                            Text(destination?.emoji ?? "📍")
                            if let destination {
                                Text(viewModel.displayPath(for: destination))
                            } else {
                                Text("Choose location").foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .tint(.primary)
                }

                Section("Items") {
                    ForEach(trayItems) { item in
                        Button {
                            if !deselected.insert(item.id).inserted { deselected.remove(item.id) }
                        } label: {
                            ScanItemRow(item: item, viewModel: viewModel, subtitle: caption(for: item)) {
                                Image(systemName: deselected.contains(item.id) ? "circle" : "checkmark.circle.fill")
                                    .foregroundStyle(deselected.contains(item.id) ? Color.secondary : Color.accentColor)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(toMove.isEmpty ? "Done" : "Move (\(toMove.count))") { confirm() }
                        .disabled(destination == nil || chosen.isEmpty || isSaving)
                }
            }
            .sheet(isPresented: $showDestinationPicker) {
                LocationSearchSheet(
                    viewModel: viewModel,
                    title: "Destination",
                    selectedId: session.destinationId,
                    unassignedLabel: nil
                ) { session.destinationId = $0 }
            }
            .alert("Couldn't move items", isPresented: $moveFailed) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Nothing from this scan was lost. Try again.")
            }
        }
    }

    private func caption(for item: Item) -> String {
        let current = viewModel.location(for: item).map { viewModel.displayPath(for: $0) } ?? "Unassigned"
        guard let destination else { return current }
        if item.locationId == destination.id { return "Already here" }
        return "\(current) → \(destination.name)"
    }

    private func confirm() {
        guard let destination else { return }
        let chosenIds = Set(chosen.map(\.id))
        let moving = toMove
        isSaving = true
        Task {
            let moved = await viewModel.moveItemsSharingDestination(moving, to: destination)
            isSaving = false
            guard moved else {
                moveFailed = true
                return
            }
            // Items that were already here confirm the match just as well as moved ones.
            session.saveLearnedReferences(selected: chosenIds)
            if moving.isEmpty { HapticManager.success() }
            onFinished()
        }
    }
}
