import SwiftUI

/// Compact summary row that opens `CodesSheet`. Style-neutral so each detail
/// screen can wrap it in its own idiom (material card vs. List row).
struct CodesRow: View {
    let target: AppLink.Target
    let viewModel: StuffViewModel

    var body: some View {
        let count = viewModel.pairedTags(for: target).count
        HStack(spacing: 8) {
            Image(systemName: "qrcode")
                .foregroundStyle(.tint)
            Text("Codes")
                .fontWeight(.medium)
            Spacer()
            Text(count == 0 ? "QR only" : "QR · \(count) tag\(count == 1 ? "" : "s")")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Every code attached to one entity: its QR sticker plus any number of
/// labelled NFC tags. Identical for items and locations — this is the single
/// place the "both kinds, many of each" rule is expressed.
struct CodesSheet: View {
    let target: AppLink.Target
    @Bindable var viewModel: StuffViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var nfcService: NFCService = CoreNFCService()
    @State private var isPairing = false
    @State private var errorMessage: String?
    @State private var showQR = false
    @State private var renamingTag: NFCTag?
    @State private var renameText = ""
    /// Set when the scanned tag already points elsewhere; drives the reassign alert.
    @State private var overwritePrevious: AppLink.Target?

    private var tags: [NFCTag] { viewModel.pairedTags(for: target) }

    var body: some View {
        NavigationStack {
            List {
                qrSection
                tagsSection
            }
            .navigationTitle("Codes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showQR) {
                if let subject = viewModel.qrSubject(for: target) {
                    QRCodeSheet(subject: subject, viewModel: viewModel)
                }
            }
            .alert("Rename Tag", isPresented: renamingBinding) {
                renameAlertActions
            } message: {
                Text("Name this sticker so you can tell it from the others, e.g. \"front\" or \"inside lid\".")
            }
            .alert("Pair Failed", isPresented: errorBinding) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .alert("Tag Already Paired", isPresented: overwriteBinding) {
                Button("Reassign", role: .destructive) {
                    overwritePrevious = nil
                    pair(allowOverwrite: true)
                }
                Button("Cancel", role: .cancel) { overwritePrevious = nil }
            } message: {
                overwriteAlertMessage
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Sections

    private var qrSection: some View {
        Section {
            Button {
                showQR = true
            } label: {
                Label("Show, Share & Print", systemImage: "qrcode")
            }
            .tint(.primary)
        } header: {
            Text("QR Code")
        } footer: {
            Text("Every sticker for this \(kindNoun) carries the same code — print as many as you like.")
        }
    }

    @ViewBuilder
    private var tagsSection: some View {
        Section {
            if tags.isEmpty {
                Text("No NFC tags paired.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(tags) { tag in
                    tagRow(tag)
                }
            }

            if nfcService.isAvailable {
                Button {
                    pair(allowOverwrite: false)
                } label: {
                    Label(isPairing ? "Hold near tag…" : "Pair NFC Tag", systemImage: "wave.3.right")
                }
                .disabled(isPairing)
            }
        } header: {
            Text("NFC Tags")
        } footer: {
            Text(nfcService.isAvailable
                 ? "Tap a tag to rename it, swipe to unpair. Unpairing only removes the link in MyStuff — the sticker keeps its old code until you write to it again."
                 : "NFC is not available on this device.")
        }
    }

    private func tagRow(_ tag: NFCTag) -> some View {
        Button {
            renamingTag = tag
            renameText = tag.label ?? ""
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(tag.displayName)
                    .foregroundStyle(.primary)
                if tag.label != nil {
                    Text(tag.uid)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                Task { await viewModel.removeNFCTag(uid: tag.uid, from: target) }
            } label: {
                Label("Unpair", systemImage: "trash")
            }
        }
    }

    // MARK: - Alert plumbing

    private var renamingBinding: Binding<Bool> {
        Binding(get: { renamingTag != nil }, set: { if !$0 { renamingTag = nil } })
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private var overwriteBinding: Binding<Bool> {
        Binding(get: { overwritePrevious != nil }, set: { if !$0 { overwritePrevious = nil } })
    }

    @ViewBuilder
    private var renameAlertActions: some View {
        TextField("Label", text: $renameText)
        Button("Save") {
            if let tag = renamingTag {
                let text = renameText
                Task { await viewModel.renameNFCTag(uid: tag.uid, label: text, on: target) }
            }
            renamingTag = nil
        }
        Button("Cancel", role: .cancel) { renamingTag = nil }
    }

    @ViewBuilder
    private var overwriteAlertMessage: some View {
        if let previous = overwritePrevious,
           let name = viewModel.displayName(for: previous) {
            Text("This tag currently points to \"\(name)\". Reassign it?")
        } else {
            Text("This tag points to something else. Reassign it?")
        }
    }

    private var kindNoun: String {
        switch target {
        case .item: return "item"
        case .location: return "location"
        }
    }

    /// Writes the link to a physical tag, then records the serial. Reassigning
    /// strips the serial from its previous owner only — that entity's other
    /// tags stay paired.
    private func pair(allowOverwrite: Bool) {
        isPairing = true
        Task {
            do {
                let result = try await nfcService.write(target: target, allowOverwrite: allowOverwrite)
                if let previous = result.previousTarget {
                    await viewModel.removeNFCTag(uid: result.tagSerial, from: previous)
                }
                await viewModel.addNFCTag(uid: result.tagSerial, to: target)
                isPairing = false
            } catch NFCError.userCancelled {
                isPairing = false
            } catch NFCError.existingPairing(let previous, _) {
                isPairing = false
                overwritePrevious = previous
            } catch {
                isPairing = false
                errorMessage = error.localizedDescription
            }
        }
    }
}
