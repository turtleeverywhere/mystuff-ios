import SwiftUI

/// Compact summary row that opens `CodesSheet`. Style-neutral so each screen
/// can wrap it in its own idiom (material card vs. List row). Takes the tag
/// list directly so a form sheet can show its staged count and a detail
/// screen its live one.
struct CodesRow: View {
    let tags: [NFCTag]

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "qrcode")
                .foregroundStyle(Color.appAccent)
            Text("Codes")
                .fontWeight(.medium)
            Spacer()
            Text(tags.isEmpty ? "QR only" : "QR · \(tags.count) tag\(tags.count == 1 ? "" : "s")")
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
    let subject: QRSubject
    let tags: [NFCTag]
    /// Called with the scanned tag serial after a successful NDEF write.
    let onPair: @MainActor (String) async -> Void
    /// Called with the serial to unpair.
    let onRemove: @MainActor (String) async -> Void
    /// Called with the serial and its new label (nil clears it).
    let onRename: @MainActor (String, String?) async -> Void
    /// Needed only to name the *other* entity in the reassign alert.
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

    private var target: AppLink.Target { subject.target }

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
                QRCodeSheet(subject: subject, viewModel: viewModel)
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
                Task { await onRemove(tag.uid) }
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
                Task { await onRename(tag.uid, text) }
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
                await onPair(result.tagSerial)
                isPairing = false
            } catch NFCError.userCancelled {
                isPairing = false
            } catch NFCError.existingPairing(let previous, let serial) {
                isPairing = false
                // Name the entity our records know about; the sticker's NDEF
                // may still point at an owner that unpaired it.
                overwritePrevious = viewModel.target(forTagUID: serial) ?? previous
            } catch {
                isPairing = false
                errorMessage = error.localizedDescription
            }
        }
    }
}

extension CodesSheet {
    /// Live mode: every edit writes straight through to the view model. Used by
    /// the detail screens, where the entity already exists. The staging form
    /// sheets use the memberwise initializer with buffer-mutating closures.
    init(live subject: QRSubject, tags: [NFCTag], viewModel: StuffViewModel) {
        let target = subject.target
        self.init(
            subject: subject,
            tags: tags,
            onPair: { serial in
                // Strip the serial from whatever entity our records say owns it —
                // not from whatever the sticker's (possibly stale) NDEF pointed at.
                if let previous = viewModel.target(forTagUID: serial), previous != target {
                    await viewModel.removeNFCTag(uid: serial, from: previous)
                }
                await viewModel.addNFCTag(uid: serial, to: target)
            },
            onRemove: { serial in
                await viewModel.removeNFCTag(uid: serial, from: target)
            },
            onRename: { serial, label in
                await viewModel.renameNFCTag(uid: serial, label: label, on: target)
            },
            viewModel: viewModel
        )
    }
}
