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
    @State private var showingScanner = false
    /// Non-nil while a scan couldn't be turned into a selection.
    @State private var scanIssue: String?

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

                        if QRScannerView.isSupported || CoreNFCService.readingAvailable {
                            Section {
                                if QRScannerView.isSupported {
                                    Button {
                                        showingScanner = true
                                    } label: {
                                        Label("Scan item QR", systemImage: "qrcode.viewfinder")
                                    }
                                }

                                NFCScanButton(accepts: .item) { target in
                                    selectScanned(target)
                                } label: { scanning in
                                    Label(scanning ? "Hold near tag…" : "Scan item NFC tag",
                                          systemImage: "wave.3.right")
                                }
                            }
                        }

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
            .sheet(isPresented: $showingScanner) {
                QRScannerSheet(accepts: .item) { target in
                    selectScanned(target)
                }
            }
            .alert("Can't add that item", isPresented: Binding(
                get: { scanIssue != nil },
                set: { if !$0 { scanIssue = nil } }
            )) {
                Button("OK", role: .cancel) { scanIssue = nil }
            } message: {
                Text(scanIssue ?? "")
            }
        }
    }

    /// Shared by both scanners: adds the scanned item to the selection.
    private func selectScanned(_ target: AppLink.Target) {
        let itemId = target.entityId
        guard let item = viewModel.items.first(where: { $0.id == itemId }) else {
            scanIssue = "That code points to an item that no longer exists."
            return
        }
        guard item.locationId != destination.id else {
            scanIssue = "\(item.name) is already in \(destination.name)."
            return
        }
        selected.insert(itemId)
        // Same reset as tapping a row — a scan is a pick.
        searchText = ""
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
                // Reset the query after a pick so the next search starts fresh —
                // picking several items usually means several separate searches.
                searchText = ""
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
