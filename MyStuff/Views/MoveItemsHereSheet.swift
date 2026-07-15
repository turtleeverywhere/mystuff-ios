import SwiftUI

/// Multi-select picker to bulk-move items into `destination`.
/// Grouped by current location or category, searchable, mirroring the Home screen.
struct MoveItemsHereSheet: View {
    let destination: Location
    let viewModel: StuffViewModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var selected: Set<String> = []
    @State private var grouping: StuffViewModel.GroupingMode = .location
    @State private var searchText = ""

    /// All items except those already directly in the destination, filtered by search.
    private var candidates: [Item] {
        var result = viewModel.items.filter { $0.locationId != destination.id }
        if !searchText.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(searchText)
                || ($0.notes?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
        return result
    }

    /// True when nothing is movable regardless of search (drives the empty state).
    private var hasAnyCandidate: Bool {
        viewModel.items.contains { $0.locationId != destination.id }
    }

    var body: some View {
        // Detents are ignored in regular width (iPad form sheet); use page sizing there.
        if horizontalSizeClass == .regular {
            content.presentationSizing(.page)
        } else {
            content.presentationDetents([.medium, .large])
        }
    }

    private var content: some View {
        NavigationStack {
            Group {
                if !hasAnyCandidate {
                    ContentUnavailableView("Nothing to move here", systemImage: "tray")
                } else {
                    List {
                        Picker("Group by", selection: $grouping) {
                            ForEach(StuffViewModel.GroupingMode.allCases, id: \.self) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)

                        switch grouping {
                        case .location: locationSections
                        case .category: categorySections
                        }
                    }
                }
            }
            .navigationTitle("Move Items")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search items")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Move (\(selected.count))") { confirmMove() }
                        .disabled(selected.isEmpty)
                }
            }
        }
    }

    // MARK: - Grouped sections

    @ViewBuilder
    private var locationSections: some View {
        ForEach(viewModel.flattenedLocationTree(), id: \.location.id) { entry in
            let items = candidates.filter { $0.locationId == entry.location.id }
            if !items.isEmpty {
                Section((entry.location.emoji ?? "📍") + " " + entry.location.name) {
                    ForEach(items) { item in itemRow(item) }
                }
            }
        }
        let unassigned = candidates.filter { $0.locationId == nil }
        if !unassigned.isEmpty {
            Section("Unassigned") {
                ForEach(unassigned) { item in itemRow(item) }
            }
        }
    }

    @ViewBuilder
    private var categorySections: some View {
        ForEach(viewModel.categories) { category in
            let items = candidates.filter { $0.categoryId == category.id }
            if !items.isEmpty {
                Section(category.name) {
                    ForEach(items) { item in itemRow(item) }
                }
            }
        }
        let uncategorized = candidates.filter { $0.categoryId == nil }
        if !uncategorized.isEmpty {
            Section("Uncategorized") {
                ForEach(uncategorized) { item in itemRow(item) }
            }
        }
    }

    // MARK: - Row

    private func itemRow(_ item: Item) -> some View {
        Button {
            if selected.contains(item.id) {
                selected.remove(item.id)
            } else {
                selected.insert(item.id)
            }
        } label: {
            HStack {
                Text(item.name).foregroundStyle(.primary)
                Spacer()
                if selected.contains(item.id) {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Confirm

    private func confirmMove() {
        let dest = viewModel.locations.first { $0.id == destination.id } ?? destination
        let selectedItems = viewModel.items.filter { selected.contains($0.id) }
        Task {
            // Auto-share the destination with moved items' collaborators (owner-managed only).
            if viewModel.canManageSharing(of: dest) {
                var missing: [String] = []
                for item in selectedItems where viewModel.canManageSharing(of: item) {
                    missing.append(contentsOf: viewModel.membersMissing(
                        from: dest,
                        forItemMembers: viewModel.sharedMembers(of: item)
                    ))
                }
                let union = Array(Set(missing))
                if !union.isEmpty {
                    await viewModel.addMembers(union, toLocation: dest)
                }
            }
            await viewModel.moveItems(selectedItems, toLocationId: dest.id)
            dismiss()
        }
    }
}
