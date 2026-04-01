import SwiftUI

struct HomeView: View {
    @Bindable var viewModel: StuffViewModel
    @State private var selectedItem: Item?

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.items.isEmpty && viewModel.locations.isEmpty {
                    emptyState
                } else {
                    mainContent
                }
            }
            .navigationTitle("My Stuff")
            .sheet(item: $selectedItem) { item in
                MoveItemSheet(
                    item: item,
                    locations: viewModel.locations,
                    onMove: { locationId in
                        Task { await viewModel.moveItem(item, toLocationId: locationId) }
                    }
                )
                .presentationDetents([.medium])
            }
        }
    }

    // MARK: - Main Content

    private var mainContent: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                // Locations with their items
                ForEach(viewModel.locations) { location in
                    locationCard(location)
                }

                // Unassigned items
                if !viewModel.unassignedItems.isEmpty {
                    unassignedCard
                }
            }
            .padding()
        }
    }

    // MARK: - Location Card

    private func locationCard(_ location: Location) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(location.emoji ?? "📍")
                    .font(.title2)
                Text(location.name)
                    .font(.headline)
                Spacer()
                Text("\(viewModel.itemCount(for: location))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule())
            }

            let locationItems = viewModel.items(for: location)
            if locationItems.isEmpty {
                Text("No items here")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 4)
            } else {
                ForEach(locationItems) { item in
                    itemRow(item)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Unassigned Card

    private var unassignedCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("❓")
                    .font(.title2)
                Text("Unassigned")
                    .font(.headline)
                Spacer()
                Text("\(viewModel.unassignedItems.count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule())
            }

            ForEach(viewModel.unassignedItems) { item in
                itemRow(item)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Item Row

    private func itemRow(_ item: Item) -> some View {
        Button {
            selectedItem = item
        } label: {
            HStack {
                Image(systemName: "shippingbox")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading) {
                    Text(item.name)
                        .font(.subheadline)
                    if let notes = item.notes {
                        Text(notes)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Image(systemName: "arrow.right.circle")
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Welcome to MyStuff", systemImage: "shippingbox.fill")
        } description: {
            Text("Start by adding some locations and items.\nYou'll never lose track of your stuff again!")
        }
    }
}

// MARK: - Move Item Sheet

struct MoveItemSheet: View {
    let item: Item
    let locations: [Location]
    let onMove: (String?) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Move \"\(item.name)\" to…") {
                    Button {
                        onMove(nil)
                        dismiss()
                    } label: {
                        Label("Unassigned", systemImage: "questionmark.circle")
                    }
                    .tint(item.locationId == nil ? .accentColor : .primary)

                    ForEach(locations) { location in
                        Button {
                            onMove(location.id)
                            dismiss()
                        } label: {
                            Label {
                                Text(location.name)
                            } icon: {
                                Text(location.emoji ?? "📍")
                            }
                        }
                        .tint(item.locationId == location.id ? .accentColor : .primary)
                    }
                }
            }
            .navigationTitle("Move Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    ContentView(authService: AuthService())
}
