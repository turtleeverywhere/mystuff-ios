import SwiftUI

/// Shared building blocks for every "which location?" UI in the app.
///
/// The tree is presented the same way everywhere: one section per top-level
/// place, so one location is visually separated from the next, and that place's
/// sublocations nested underneath with an indent rail per level. This replaces
/// the old flat `Picker` menus, which faked hierarchy with leading spaces.

// MARK: - Tree Grouping

enum LocationTree {
    typealias Entry = (location: Location, depth: Int)
    typealias Group = (root: Location, entries: [Entry])

    /// The flattened tree cut into one group per top-level location: the root
    /// itself first, then its subtree in DFS order.
    @MainActor
    static func groups(_ viewModel: StuffViewModel, excluding: String? = nil) -> [Group] {
        var result: [Group] = []
        for entry in viewModel.flattenedLocationTree(excluding: excluding) {
            if entry.depth == 0 {
                result.append((root: entry.location, entries: [entry]))
            } else if !result.isEmpty {
                result[result.count - 1].entries.append(entry)
            }
        }
        return result
    }
}

// MARK: - Row

/// One row in a location tree picker. Depth 0 is the place itself; deeper rows
/// are its sublocations, set off by an indent rail so nesting reads at a glance.
struct LocationTreeRow: View {
    let location: Location
    let depth: Int
    var isSelected: Bool = false
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                if depth > 0 {
                    Rectangle()
                        .fill(.tertiary)
                        .frame(width: 2, height: 20)
                        .padding(.leading, CGFloat(depth - 1) * 18)
                }
                Text(location.emoji ?? "📍")
                Text(location.name)
                    .fontWeight(depth == 0 ? .semibold : .regular)
                Spacer()
                if isSelected { LocationPickerCheckmark() }
            }
        }
        .tint(.primary)
    }
}

struct LocationPickerCheckmark: View {
    var body: some View {
        Image(systemName: "checkmark")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color.accentColor)
    }
}

// MARK: - Sections

/// Grouped location rows, ready to drop into a `List` alongside a screen's own
/// sections (scanner buttons, an "Unassigned" row, headers and footers).
struct LocationTreeSections: View {
    let viewModel: StuffViewModel
    var selectedId: String?
    /// Location whose subtree to leave out — a location can't move into itself.
    var excluding: String?
    let onSelect: (String) -> Void

    var body: some View {
        ForEach(LocationTree.groups(viewModel, excluding: excluding), id: \.root.id) { group in
            Section {
                ForEach(group.entries, id: \.location.id) { entry in
                    LocationTreeRow(
                        location: entry.location,
                        depth: entry.depth,
                        isSelected: selectedId == entry.location.id
                    ) {
                        onSelect(entry.location.id)
                    }
                }
            }
        }
    }
}

// MARK: - Form Row

/// Form row showing the chosen location and opening the full picker on tap —
/// the replacement for an inline `Picker` inside a `Form`.
struct LocationPickerRow: View {
    let viewModel: StuffViewModel
    /// Row label, e.g. "Location".
    let label: String
    /// Title of the picker sheet, e.g. "Choose Location".
    var pickerTitle: String
    /// Shown, and offered in the picker, when nothing is chosen.
    var emptyLabel: String = "Unassigned"
    /// Location whose subtree to leave out — for parent pickers.
    var excluding: String?
    @Binding var selection: String?

    @State private var showPicker = false

    private var location: Location? {
        viewModel.locations.first { $0.id == selection }
    }

    var body: some View {
        Button {
            showPicker = true
        } label: {
            HStack(spacing: 10) {
                Text(label)
                Spacer(minLength: 12)
                if let location {
                    Text(location.emoji ?? "📍")
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(location.name)
                        if location.parentId != nil {
                            Text(viewModel.displayPath(for: location))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text(emptyLabel)
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .tint(.primary)
        .sheet(isPresented: $showPicker) {
            LocationSearchSheet(
                viewModel: viewModel,
                title: pickerTitle,
                selectedId: selection,
                unassignedLabel: emptyLabel,
                excluding: excluding
            ) { selection = $0 }
        }
    }
}

// MARK: - Search Sheet

/// Searchable location picker. Browsing shows the grouped tree; typing flattens
/// the list to matches, each with its full path for context.
struct LocationSearchSheet: View {
    let viewModel: StuffViewModel
    var title: String = "Move to Location"
    /// Currently chosen location, checkmarked while browsing. `nil` means none.
    var selectedId: String?
    /// Label of the "no location" row; `nil` hides that row entirely.
    var unassignedLabel: String? = "Unassigned"
    var unassignedIcon: String = "questionmark.circle"
    var excluding: String?
    let onSelect: (String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var matches: [LocationTree.Entry] {
        viewModel.flattenedLocationTree(excluding: excluding)
            .filter { $0.location.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            List {
                if searchText.isEmpty {
                    if let unassignedLabel {
                        Section {
                            Button {
                                choose(nil)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: unassignedIcon)
                                        .foregroundStyle(.secondary)
                                    Text(unassignedLabel)
                                    Spacer()
                                    if selectedId == nil { LocationPickerCheckmark() }
                                }
                            }
                            .tint(.primary)
                        }
                    }

                    LocationTreeSections(
                        viewModel: viewModel,
                        selectedId: selectedId,
                        excluding: excluding
                    ) { choose($0) }
                } else {
                    ForEach(matches, id: \.location.id) { entry in
                        Button {
                            choose(entry.location.id)
                        } label: {
                            HStack(spacing: 10) {
                                Text(entry.location.emoji ?? "📍")
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.location.name)
                                    Text(viewModel.displayPath(for: entry.location))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if selectedId == entry.location.id { LocationPickerCheckmark() }
                            }
                        }
                        .tint(.primary)
                    }
                }
            }
            .overlay {
                if !searchText.isEmpty && matches.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search locations"
            )
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func choose(_ locationId: String?) {
        onSelect(locationId)
        dismiss()
    }
}
