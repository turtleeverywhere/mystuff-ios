import SwiftUI

struct LocationsView: View {
    @Bindable var viewModel: StuffViewModel
    @State private var showingAddSheet = false
    @State private var editingLocation: Location?

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.locations.isEmpty {
                    emptyState
                } else {
                    locationsList
                }
            }
            .navigationTitle("Locations")
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
                    onSave: { name, emoji in
                        Task { await viewModel.addLocation(name: name, emoji: emoji) }
                    }
                )
            }
            .sheet(item: $editingLocation) { location in
                LocationFormSheet(
                    location: location,
                    onSave: { name, emoji in
                        var updated = location
                        updated.name = name
                        updated.emoji = emoji
                        Task { await viewModel.updateLocation(updated) }
                    }
                )
            }
        }
    }

    // MARK: - Locations List

    private var locationsList: some View {
        List {
            ForEach(viewModel.locations) { location in
                Button {
                    editingLocation = location
                } label: {
                    HStack {
                        Text(location.emoji ?? "📍")
                            .font(.title2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(location.name)
                                .font(.body)
                                .foregroundStyle(.primary)
                        }
                        Spacer()
                        Text("\(viewModel.itemCount(for: location)) items")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        Task { await viewModel.deleteLocation(location) }
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
    let onSave: (String, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var emoji: String

    private let popularEmojis = ["🏠", "🚗", "📦", "🏢", "🛋️", "🖥️", "🚙", "🏠", "🔧", "🏕️", "🎒", "🗄️"]

    init(location: Location? = nil, onSave: @escaping (String, String?) -> Void) {
        self.location = location
        self.onSave = onSave
        _name = State(initialValue: location?.name ?? "")
        _emoji = State(initialValue: location?.emoji ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Location name", text: $name)
                    TextField("Emoji icon (optional)", text: $emoji)
                        .textInputAutocapitalization(.never)
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
                        onSave(name, emoji.isEmpty ? nil : emoji)
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
