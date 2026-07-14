import SwiftUI

struct LocationsView: View {
    @Bindable var viewModel: StuffViewModel
    @State private var showingAddSheet = false
    @State private var locationToDelete: Location?
    @State private var expandedIds: Set<String> = []
    @State private var path: [Location] = []

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if viewModel.locations.isEmpty {
                    emptyState
                } else {
                    locationsList
                }
            }
            .navigationTitle("Locations")
            .navigationDestination(for: Location.self) { loc in
                LocationDetailView(location: loc, viewModel: viewModel)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                LocationFormSheet(
                    viewModel: viewModel,
                    onSave: { name, emoji, parentId in
                        Task { await viewModel.addLocation(name: name, emoji: emoji, parentId: parentId) }
                    }
                )
            }
            .alert("Delete Location?", isPresented: Binding(
                get: { locationToDelete != nil },
                set: { if !$0 { locationToDelete = nil } }
            )) {
                Button("Delete", role: .destructive) {
                    if let loc = locationToDelete {
                        let hasChildren = !viewModel.childLocations(for: loc).isEmpty
                        Task {
                            await viewModel.deleteLocation(loc)
                            _ = hasChildren // suppress unused warning
                        }
                    }
                }
                Button("Cancel", role: .cancel) { locationToDelete = nil }
            } message: {
                if let loc = locationToDelete, !viewModel.childLocations(for: loc).isEmpty {
                    Text("Sub-locations will be moved up one level. Items at this location will be unassigned.")
                } else {
                    Text("Items at this location will be unassigned.")
                }
            }
        }
        .containerBackground(LinearGradient.appBackground, for: .navigation)
    }

    // MARK: - Locations List

    /// Visible locations based on expanded state
    private var visibleEntries: [(location: Location, depth: Int)] {
        var result: [(Location, Int)] = []
        func walk(_ parentId: String?, depth: Int) {
            let children = viewModel.locations
                .filter { $0.parentId == parentId }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            for child in children {
                result.append((child, depth))
                if expandedIds.contains(child.id) {
                    walk(child.id, depth: depth + 1)
                }
            }
        }
        walk(nil, depth: 0)
        return result
    }

    private var locationsList: some View {
        List {
            ForEach(visibleEntries, id: \.location.id) { entry in
                let hasChildren = !viewModel.childLocations(for: entry.location).isEmpty
                HStack(spacing: 0) {
                    // Expand/collapse button
                    if hasChildren {
                        Button {
                            withAnimation {
                                if expandedIds.contains(entry.location.id) {
                                    expandedIds.remove(entry.location.id)
                                } else {
                                    expandedIds.insert(entry.location.id)
                                }
                            }
                        } label: {
                            Image(systemName: expandedIds.contains(entry.location.id) ? "chevron.down" : "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Spacer().frame(width: 24)
                    }

                    // Location label -> detail
                    NavigationLink(value: entry.location) {
                        HStack {
                            Text(entry.location.emoji ?? "📍")
                                .font(.title2)
                            Text(entry.location.name)
                                .font(.body)
                                .foregroundStyle(.primary)
                            Spacer()
                            Text("\(viewModel.recursiveItemCount(for: entry.location)) items")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(.ultraThinMaterial, in: Capsule())
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding(.leading, CGFloat(entry.depth) * 24)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        locationToDelete = entry.location
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Locations Yet", systemImage: "mappin.circle")
        } description: {
            Text("Add locations like \"Living Room\", \"Garage\", or \"Car\" to start organizing your stuff.")
        } actions: {
            Button("Add Location") {
                showingAddSheet = true
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

// MARK: - Location Form Sheet

struct LocationFormSheet: View {
    let location: Location?
    let viewModel: StuffViewModel
    let onSave: (String, String?, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var emoji: String
    @State private var selectedParentId: String

    private static let noParentSentinel = "__none__"
    private let popularEmojis = ["🏠", "🚗", "📦", "🏢", "🛋️", "🖥️", "🚙", "🏠", "🔧", "🏕️", "🎒", "🗄️"]

    init(location: Location? = nil, viewModel: StuffViewModel, onSave: @escaping (String, String?, String?) -> Void) {
        self.location = location
        self.viewModel = viewModel
        self.onSave = onSave
        _name = State(initialValue: location?.name ?? "")
        _emoji = State(initialValue: location?.emoji ?? "")
        _selectedParentId = State(initialValue: location?.parentId ?? Self.noParentSentinel)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Location name", text: $name)
                    TextField("Emoji icon (optional)", text: $emoji)
                        .textInputAutocapitalization(.never)
                }

                Section("Parent Location") {
                    Picker("Parent", selection: $selectedParentId) {
                        Text("None (Root)").tag(Self.noParentSentinel)
                        ForEach(viewModel.flattenedLocationTree(excluding: location?.id), id: \.location.id) { entry in
                            Text(String(repeating: "  ", count: entry.depth) + (entry.location.emoji ?? "📍") + " " + entry.location.name)
                                .tag(entry.location.id)
                        }
                    }
                }

                Section("Quick Pick") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(popularEmojis, id: \.self) { e in
                            Button {
                                emoji = e
                            } label: {
                                Text(e)
                                    .font(.title2)
                                    .padding(8)
                                    .background(
                                        emoji == e ? Color.accentColor.opacity(0.2) : Color.clear,
                                        in: RoundedRectangle(cornerRadius: 8)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle(location == nil ? "New Location" : "Edit Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let parentId = selectedParentId == Self.noParentSentinel ? nil : selectedParentId
                        onSave(name, emoji.isEmpty ? nil : emoji, parentId)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

#Preview {
    ContentView(authService: AuthService())
}
