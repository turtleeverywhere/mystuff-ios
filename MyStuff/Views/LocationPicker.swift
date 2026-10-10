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
    var path: String?
    let onSelect: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                if depth > 0 && !dynamicTypeSize.isAccessibilitySize {
                    Rectangle()
                        .fill(Color.appBorder)
                        .frame(width: 2, height: 28)
                        .padding(.leading, CGFloat(min(depth - 1, 3)) * 12)
                        .accessibilityHidden(true)
                }
                LocationIcon(emoji: location.emoji)
                VStack(alignment: .leading, spacing: 4) {
                    Text(location.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.appText)
                    if let path {
                        Text(path)
                            .font(.caption)
                            .foregroundStyle(Color.appTertiary)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer()
                if isSelected { LocationPickerCheckmark() }
            }
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(path ?? location.name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .listRowBackground(isSelected ? Color.appSurfaceMuted : Color.appSurface)
    }
}

struct LocationPickerCheckmark: View {
    var body: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.title3)
            .foregroundStyle(Color.appPrimary)
            .accessibilityHidden(true)
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
                        isSelected: selectedId == entry.location.id,
                        path: entry.depth > 0 ? viewModel.displayPath(for: entry.location) : nil
                    ) {
                        onSelect(entry.location.id)
                    }
                }
            } header: {
                Text(group.root.name)
                    .foregroundStyle(Color.appTertiary)
            }
        }
    }
}

/// Reused by scan capture and review, and by item forms.
struct LocationSelectionLabel: View {
    let viewModel: StuffViewModel
    let locationId: String?
    var title = "Store in"
    var emptyLabel = "Choose location"

    private var location: Location? {
        viewModel.locations.first { $0.id == locationId }
    }

    var body: some View {
        HStack(spacing: 12) {
            LocationIcon(emoji: location?.emoji)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.appTertiary)
                Text(location.map { viewModel.displayPath(for: $0) } ?? emptyLabel)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.appText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .dynamicTypeSize(.large)
                .foregroundStyle(Color.appTertiary)
                .accessibilityHidden(true)
        }
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }
}

struct UnassignedLocationRow: View {
    var title = "Unassigned"
    var symbol = "questionmark.circle"
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                LocationIcon(emoji: nil, symbol: symbol)
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.appText)
                Spacer()
                if isSelected { LocationPickerCheckmark() }
            }
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .listRowBackground(isSelected ? Color.appSurfaceMuted : Color.appSurface)
    }
}

/// Shared browsing/search content. Searches full paths to retain parent context.
struct LocationSelectionSections: View {
    let viewModel: StuffViewModel
    var selectedId: String?
    var unassignedLabel: String? = "Unassigned"
    var unassignedIcon = "questionmark.circle"
    var excluding: String?
    var searchText = ""
    let onSelect: (String?) -> Void

    private var query: String { searchText.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var matches: [LocationTree.Entry] {
        viewModel.flattenedLocationTree(excluding: excluding).filter {
            viewModel.displayPath(for: $0.location).localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        if query.isEmpty {
            if let unassignedLabel {
                Section {
                    UnassignedLocationRow(title: unassignedLabel, symbol: unassignedIcon, isSelected: selectedId == nil) {
                        onSelect(nil)
                    }
                }
            }
            if viewModel.flattenedLocationTree(excluding: excluding).isEmpty {
                ContentUnavailableView("No locations yet", systemImage: "mappin.and.ellipse", description: Text("Create a location to give your items a home."))
                    .listRowBackground(Color.clear)
            } else {
                LocationTreeSections(viewModel: viewModel, selectedId: selectedId, excluding: excluding) { onSelect($0) }
            }
        } else if matches.isEmpty {
            ContentUnavailableView.search(text: query)
                .listRowBackground(Color.clear)
        } else {
            Section("Results") {
                ForEach(matches, id: \.location.id) { entry in
                    LocationTreeRow(location: entry.location, depth: 0, isSelected: selectedId == entry.location.id,
                                    path: viewModel.displayPath(for: entry.location)) {
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

    var body: some View {
        Button {
            showPicker = true
        } label: {
            LocationSelectionLabel(viewModel: viewModel, locationId: selection, title: label, emptyLabel: emptyLabel)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Choose a storage location")
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
    var subtitle: String = "Choose a place or a specific shelf."
    /// Currently chosen location, checkmarked while browsing. `nil` means none.
    var selectedId: String?
    /// Label of the "no location" row; `nil` hides that row entirely.
    var unassignedLabel: String? = "Unassigned"
    var unassignedIcon: String = "questionmark.circle"
    var excluding: String?
    let onSelect: (String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            List {
                if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    AppSectionHeading(title: "Find a home", subtitle: subtitle)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                LocationSelectionSections(
                    viewModel: viewModel,
                    selectedId: selectedId,
                    unassignedLabel: unassignedLabel,
                    unassignedIcon: unassignedIcon,
                    excluding: excluding,
                    searchText: searchText,
                    onSelect: choose
                )
            }
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
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
            .tint(.appPrimary)
        }
    }

    private func choose(_ locationId: String?) {
        onSelect(locationId)
        dismiss()
    }
}
