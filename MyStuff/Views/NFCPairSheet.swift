import SwiftUI

/// Target picker shown when a blank or unrecognized NFC tag is scanned on the
/// NFC tab. Lets the user pair the tag to any item or location.
struct NFCPairSheet: View {
    @Bindable var viewModel: StuffViewModel
    let nfcService: NFCService
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var isPairing = false
    @State private var errorMessage: String?
    @State private var overwriteCandidate: (target: AppLink.Target, previous: AppLink.Target)?

    var body: some View {
        NavigationStack {
            Group {
                if filteredItems.isEmpty && filteredLocations.isEmpty {
                    ContentUnavailableView("Nothing to pair", systemImage: "shippingbox")
                } else {
                    List {
                        if !filteredItems.isEmpty {
                            Section("Items") {
                                ForEach(filteredItems) { item in
                                    row(
                                        target: .item(item.id),
                                        title: item.name,
                                        subtitle: viewModel.location(for: item).map { viewModel.displayPath(for: $0) }
                                    )
                                }
                            }
                        }
                        if !filteredLocations.isEmpty {
                            Section("Locations") {
                                ForEach(filteredLocations, id: \.id) { location in
                                    row(
                                        target: .location(location.id),
                                        title: (location.emoji ?? "📍") + " " + location.name,
                                        subtitle: viewModel.displayPath(for: location)
                                    )
                                }
                            }
                        }
                    }
                    .searchable(text: $searchText, prompt: "Search items and locations...")
                }
            }
            .navigationTitle("Pair Tag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isPairing)
                }
            }
            .overlay {
                if isPairing {
                    Color.black.opacity(0.1)
                        .ignoresSafeArea()
                        .overlay { ProgressView("Hold near tag...") }
                }
            }
            .alert("Pair Failed", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .alert("Tag Already Paired", isPresented: Binding(
                get: { overwriteCandidate != nil },
                set: { if !$0 { overwriteCandidate = nil } }
            )) {
                Button("Reassign", role: .destructive) {
                    if let candidate = overwriteCandidate {
                        overwriteCandidate = nil
                        pair(to: candidate.target, allowOverwrite: true)
                    }
                }
                Button("Cancel", role: .cancel) { overwriteCandidate = nil }
            } message: {
                if let candidate = overwriteCandidate,
                   let previousName = viewModel.displayName(for: candidate.previous),
                   let newName = viewModel.displayName(for: candidate.target) {
                    Text("This tag is already paired to \"\(previousName)\". Reassign to \"\(newName)\"?")
                } else {
                    Text("This tag is already paired to something else. Reassign?")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// One selectable row. The trailing count replaces the old binary
    /// paired/unpaired glyph, since an entity may now hold several tags.
    @ViewBuilder
    private func row(target: AppLink.Target, title: String, subtitle: String?) -> some View {
        let count = viewModel.pairedTags(for: target).count
        Button {
            pair(to: target)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.body)
                        .foregroundStyle(.primary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if count > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "wave.3.right")
                        Text("\(count)")
                    }
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isPairing)
    }

    private var filteredItems: [Item] {
        let sorted = viewModel.items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        guard !searchText.isEmpty else { return sorted }
        return sorted.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var filteredLocations: [Location] {
        let sorted = viewModel.locations.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        guard !searchText.isEmpty else { return sorted }
        return sorted.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private func pair(to target: AppLink.Target, allowOverwrite: Bool = false) {
        isPairing = true
        Task {
            do {
                let result = try await nfcService.write(target: target, allowOverwrite: allowOverwrite)
                if let previous = result.previousTarget {
                    await viewModel.removeNFCTag(uid: result.tagSerial, from: previous)
                }
                await viewModel.addNFCTag(uid: result.tagSerial, to: target)
                isPairing = false
                dismiss()
            } catch NFCError.userCancelled {
                isPairing = false
            } catch NFCError.existingPairing(let previous, _) {
                isPairing = false
                overwriteCandidate = (target, previous)
            } catch {
                isPairing = false
                errorMessage = error.localizedDescription
            }
        }
    }
}
