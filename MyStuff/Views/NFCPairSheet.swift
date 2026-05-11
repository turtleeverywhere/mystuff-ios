import SwiftUI

/// Item picker shown when a blank/unknown NFC tag is scanned on the NFC tab.
/// Lets the user choose which item to pair the tag to.
struct NFCPairSheet: View {
    @Bindable var viewModel: StuffViewModel
    let nfcService: NFCService
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var isPairing = false
    @State private var errorMessage: String?
    @State private var overwriteCandidate: (item: Item, previousId: String)?

    var body: some View {
        NavigationStack {
            Group {
                if filteredItems.isEmpty {
                    ContentUnavailableView("No items", systemImage: "shippingbox")
                } else {
                    List {
                        ForEach(filteredItems) { item in
                            Button {
                                pair(item: item)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.name)
                                            .font(.body)
                                            .foregroundStyle(.primary)
                                        if let location = viewModel.location(for: item) {
                                            Text(viewModel.displayPath(for: location))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    if item.nfcTagUID != nil {
                                        Image(systemName: "wave.3.right")
                                            .foregroundStyle(.tertiary)
                                            .font(.caption)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(isPairing)
                        }
                    }
                    .searchable(text: $searchText, prompt: "Search items...")
                }
            }
            .navigationTitle("Pair Tag To Item")
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
                        pair(item: candidate.item, allowOverwrite: true)
                    }
                }
                Button("Cancel", role: .cancel) { overwriteCandidate = nil }
            } message: {
                if let candidate = overwriteCandidate,
                   let prevItem = viewModel.items.first(where: { $0.id == candidate.previousId }) {
                    Text("This tag is already paired to \"\(prevItem.name)\". Reassign to \"\(candidate.item.name)\"?")
                } else {
                    Text("This tag is already paired to another item. Reassign?")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var filteredItems: [Item] {
        let sorted = viewModel.items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        guard !searchText.isEmpty else { return sorted }
        return sorted.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private func pair(item: Item, allowOverwrite: Bool = false) {
        isPairing = true
        Task {
            do {
                let result = try await nfcService.writeItem(id: item.id, allowOverwrite: allowOverwrite)
                if let prevId = result.previousItemId {
                    await viewModel.clearNFCTag(itemId: prevId)
                }
                await viewModel.setNFCTag(itemId: item.id, uid: result.tagSerial)
                isPairing = false
                dismiss()
            } catch NFCError.userCancelled {
                isPairing = false
            } catch NFCError.existingPairing(let previousId, _) {
                isPairing = false
                overwriteCandidate = (item, previousId)
            } catch {
                isPairing = false
                errorMessage = error.localizedDescription
            }
        }
    }
}
