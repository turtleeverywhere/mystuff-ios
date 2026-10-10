import SwiftUI

/// The filter selection shared by the Home and Items tabs. A value type so each
/// host view owns its own state; search text stays with the host because the two
/// tabs source it differently.
struct ItemFilter: Equatable {
    var categoryIds: Set<String> = []
    var locationIds: Set<String> = []
    var misplacedOnly = false

    var isActive: Bool {
        !categoryIds.isEmpty || !locationIds.isEmpty || misplacedOnly
    }

    /// Facets currently narrowing the list — drives the count badge in the header.
    var activeCount: Int {
        (categoryIds.isEmpty ? 0 : 1) + (locationIds.isEmpty ? 0 : 1) + (misplacedOnly ? 1 : 0)
    }

    /// Applies every facet plus `searchText`. Selecting a location also matches its
    /// descendants. Pass an empty `searchText` when the caller has already searched.
    ///
    /// `@MainActor`: `StuffViewModel` is main-actor isolated; unlike `HomeView`, this
    /// struct doesn't conform to `View` so it gets no free actor inference.
    @MainActor
    func apply(to items: [Item], searchText: String, viewModel: StuffViewModel) -> [Item] {
        var result = items
        if !searchText.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(searchText)
                || ($0.notes?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
        if !categoryIds.isEmpty {
            result = result.filter { categoryIds.contains($0.categoryId ?? "") }
        }
        if !locationIds.isEmpty {
            let allIds = locationIds.reduce(into: locationIds) { acc, id in
                acc.formUnion(viewModel.allDescendantIds(of: id))
            }
            result = result.filter { allIds.contains($0.locationId ?? "") }
        }
        if misplacedOnly {
            result = result.filter { viewModel.isMisplaced($0) }
        }
        return result
    }
}

/// Collapsible chip bar: Categories, Locations, Status, and the action row.
struct ItemFilterBar: View {
    @Binding var filter: ItemFilter
    @Binding var isExpanded: Bool
    let viewModel: StuffViewModel
    /// Host-computed: true when search text *or* any facet is active. Drives "Clear All".
    let isFiltering: Bool
    /// Items "Put All Back" would act on — already narrowed by the host's visible list.
    let putBackTargets: [Item]
    let onPutAllBack: () -> Void
    let onClearAll: () -> Void
    @State private var confirmingPutAllBack = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation { isExpanded.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "line.3.horizontal.decrease")
                    Text("Filters")
                        .font(.subheadline)
                    if filter.activeCount > 0 {
                        Text("\(filter.activeCount)")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor, in: Capsule())
                            .foregroundStyle(.white)
                    }
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            if isExpanded {
                if !viewModel.categories.isEmpty {
                    Text("Categories")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(viewModel.categories) { category in
                                chip(
                                    label: category.name,
                                    isSelected: filter.categoryIds.contains(category.id)
                                ) {
                                    toggle(category.id, in: &filter.categoryIds)
                                }
                            }
                        }
                    }
                }

                if !viewModel.locations.isEmpty {
                    Text("Locations")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    // Chips can't indent, so hierarchy shows two other ways: a
                    // divider between top-level places, and a "↳" per level for
                    // sublocations within one.
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(LocationTree.groups(viewModel).enumerated()), id: \.element.root.id) { index, group in
                                if index > 0 {
                                    Divider().frame(height: 20)
                                }
                                ForEach(group.entries, id: \.location.id) { entry in
                                    chip(
                                        label: String(repeating: "↳", count: entry.depth) + (entry.location.emoji ?? "📍") + " " + entry.location.name,
                                        isSelected: filter.locationIds.contains(entry.location.id)
                                    ) {
                                        toggle(entry.location.id, in: &filter.locationIds)
                                    }
                                }
                            }
                        }
                    }
                }

                Text("Status")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                chip(label: "⚠️ Misplaced", isSelected: filter.misplacedOnly) {
                    filter.misplacedOnly.toggle()
                }

                actionRow
            }
        }
        .confirmationDialog(
            "Put back \(putBackTargets.count) \(putBackTargets.count == 1 ? "item" : "items")?",
            isPresented: $confirmingPutAllBack,
            titleVisibility: .visible
        ) {
            Button("Put All Back", role: .destructive, action: onPutAllBack)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Each item moves to its supposed location.")
        }
    }

    /// Full-width buttons on their own row so both clear the 44pt touch target and
    /// can't be mistaken for each other.
    @ViewBuilder
    private var actionRow: some View {
        let showPutBack = filter.misplacedOnly && !putBackTargets.isEmpty
        if showPutBack || isFiltering {
            HStack(spacing: 12) {
                if showPutBack {
                    Button {
                        confirmingPutAllBack = true
                    } label: {
                        Text("Put All Back (\(putBackTargets.count))")
                            .frame(maxWidth: .infinity, minHeight: 30)
                    }
                    .buttonStyle(.borderedProminent)
                }
                if isFiltering {
                    Button(action: onClearAll) {
                        Text("Clear All")
                            .frame(maxWidth: .infinity, minHeight: 30)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .font(.subheadline)
            .controlSize(.large)
            .padding(.top, 4)
        }
    }

    private func toggle(_ id: String, in set: inout Set<String>) {
        if set.contains(id) { set.remove(id) } else { set.insert(id) }
    }

    private func chip(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor.opacity(0.2) : .clear, in: Capsule())
                .overlay(Capsule().stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
