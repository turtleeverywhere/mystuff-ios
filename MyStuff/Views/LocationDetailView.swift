import SwiftUI

/// A location's home: its items and sub-locations, with Edit and QR actions.
/// Used both pushed (Locations tab) and presented as a sheet (deep-link / scan).
struct LocationDetailView: View {
    let location: Location
    @Bindable var viewModel: StuffViewModel

    @State private var showingEdit = false
    @State private var showingQR = false
    @State private var detailItem: Item?

    /// Follow live edits so the header/list update after Edit.
    private var live: Location {
        viewModel.locations.first(where: { $0.id == location.id }) ?? location
    }

    private var children: [Location] {
        viewModel.childLocations(for: live)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var directItems: [Item] {
        viewModel.items(for: live)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    Text(live.emoji ?? "📍").font(.largeTitle)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(live.name).font(.title2.weight(.semibold))
                        Text("\(viewModel.recursiveItemCount(for: live)) items")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            }

            if !children.isEmpty {
                Section("Sub-locations") {
                    ForEach(children) { child in
                        NavigationLink {
                            LocationDetailView(location: child, viewModel: viewModel)
                        } label: {
                            Label { Text(child.name) } icon: { Text(child.emoji ?? "📍") }
                        }
                    }
                }
            }

            Section("Items") {
                if directItems.isEmpty {
                    Text("No items here yet.").foregroundStyle(.secondary)
                } else {
                    ForEach(directItems) { item in
                        Button {
                            detailItem = item
                        } label: {
                            Text(item.name).foregroundStyle(.primary)
                        }
                    }
                }
            }
        }
        .navigationTitle(live.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { showingQR = true } label: { Image(systemName: "qrcode") }
                Button("Edit") { showingEdit = true }
            }
        }
        .sheet(isPresented: $showingQR) {
            QRCodeSheet(location: live)
        }
        .sheet(isPresented: $showingEdit) {
            LocationFormSheet(
                location: live,
                viewModel: viewModel,
                onSave: { name, emoji, parentId in
                    var updated = live
                    updated.name = name
                    updated.emoji = emoji
                    updated.parentId = parentId
                    Task { await viewModel.updateLocation(updated) }
                }
            )
        }
        .sheet(item: $detailItem) { item in
            ItemDetailSheet(item: item, viewModel: viewModel)
        }
        .containerBackground(LinearGradient.appBackground, for: .navigation)
    }
}
