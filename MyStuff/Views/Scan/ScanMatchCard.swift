import SwiftUI

/// Item row used across the scan screens: item photo, name, and where it is now.
struct ScanItemRow<Trailing: View>: View {
    let item: Item
    let viewModel: StuffViewModel
    /// Replaces the default "current location" caption.
    var subtitle: String? = nil
    @ViewBuilder var trailing: () -> Trailing

    private var place: String {
        viewModel.location(for: item).map { viewModel.displayPath(for: $0) } ?? "Unassigned"
    }

    var body: some View {
        HStack(spacing: 12) {
            PhotoView(item: item, kind: .item, size: .thumbnail(84)) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Image(systemName: "shippingbox.fill").foregroundStyle(.secondary)
            }
            .frame(width: 44, height: 44)
            .background(.quaternary)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).foregroundStyle(.primary)
                Text(subtitle ?? place)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            trailing()
        }
        .contentShape(Rectangle())
    }
}

/// Asks which item a capture shows: the matcher's best guesses, any other item,
/// or a brand-new one. Also reached from the tray to reassign or remove an item.
struct ScanMatchCard: View {
    let capture: ScanSessionModel.Capture
    let viewModel: StuffViewModel
    let onPick: (String) -> Void
    /// Create a new item with this name from the captured photo.
    let onCreate: (String) -> Void
    let onRemove: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showNamePrompt = false
    @State private var newName = ""

    private var candidates: [(match: ItemMatch, item: Item)] {
        capture.candidates.compactMap { match in
            viewModel.items.first { $0.id == match.itemId }.map { (match, $0) }
        }
    }

    private var title: String {
        if capture.itemId != nil { return "Change Item" }
        return candidates.isEmpty ? "Not Recognized" : "Which Item?"
    }

    var body: some View {
        NavigationStack {
            List {
                if let photo = capture.embedding?.thumbnail, let image = UIImage(data: photo) {
                    Section {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: 140)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .listRowBackground(Color.clear)
                    }
                }

                if !candidates.isEmpty {
                    Section("Best guesses") {
                        ForEach(candidates, id: \.item.id) { candidate in
                            Button {
                                onPick(candidate.item.id)
                            } label: {
                                ScanItemRow(item: candidate.item, viewModel: viewModel) {
                                    #if DEBUG
                                    // Threshold tuning aid — see ItemMatcher's constants.
                                    Text(String(format: "%.2f", candidate.match.distance))
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                    #endif
                                    if capture.itemId == candidate.item.id {
                                        LocationPickerCheckmark()
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section {
                    NavigationLink {
                        ScanItemSearchList(viewModel: viewModel, onPick: onPick)
                    } label: {
                        Label("Other item…", systemImage: "magnifyingglass")
                    }
                    if capture.photo != nil {
                        Button {
                            newName = ""
                            showNamePrompt = true
                        } label: {
                            Label("New item", systemImage: "plus.circle")
                        }
                    }
                    Button(role: .destructive) {
                        onRemove()
                    } label: {
                        Label(capture.itemId == nil ? "Discard" : "Remove from scan", systemImage: "trash")
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("New item", isPresented: $showNamePrompt) {
                TextField("Name", text: $newName)
                Button("Create") {
                    let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !name.isEmpty { onCreate(name) }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("The photo you just took becomes its item photo.")
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Every item, searchable — for when the right one isn't among the guesses.
private struct ScanItemSearchList: View {
    let viewModel: StuffViewModel
    let onPick: (String) -> Void
    @State private var searchText = ""

    private var results: [Item] {
        viewModel.items
            .filter { searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        List(results) { item in
            Button {
                onPick(item.id)
            } label: {
                ScanItemRow(item: item, viewModel: viewModel) { EmptyView() }
            }
            .buttonStyle(.plain)
        }
        .overlay {
            if results.isEmpty { ContentUnavailableView.search(text: searchText) }
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search items")
        .navigationTitle("Choose Item")
        .navigationBarTitleDisplayMode(.inline)
    }
}
