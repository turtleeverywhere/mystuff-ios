import SwiftUI

/// Item-detail card listing the photos the scanner knows this item by, with a
/// way to add more angles by hand. References stay on this device.
struct RecognitionPhotosSection: View {
    let item: Item
    let viewModel: StuffViewModel

    @State private var showEnroll = false

    private var store: RecognitionStore { viewModel.recognition }
    private var references: [ItemReference] { store.references(for: item.id) }
    private var enrolledCount: Int { references.filter { $0.source == .enrolled }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Recognition photos", systemImage: "camera.viewfinder")
                .font(.headline)

            if references.isEmpty {
                Text("None yet. Scanning learns this item as you confirm matches, or add a few angles now.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(references) { reference in
                            thumbnail(reference)
                        }
                    }
                }
            }

            Button {
                showEnroll = true
            } label: {
                Label("Add angles", systemImage: "plus.viewfinder")
            }
            .disabled(enrolledCount >= RecognitionStore.maxEnrolled)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .fullScreenCover(isPresented: $showEnroll) {
            EnrollCaptureView(item: item, store: store)
        }
    }

    private func thumbnail(_ reference: ItemReference) -> some View {
        ReferenceThumbnail(url: store.thumbnailURL(for: reference))
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: icon(for: reference.source))
                    .font(.caption2)
                    .padding(3)
                    .background(.ultraThinMaterial, in: Circle())
                    .padding(3)
            }
            .contextMenu {
                // The item-photo reference follows the item photo; change that instead.
                if reference.source != .itemPhoto {
                    Button(role: .destructive) {
                        store.remove(reference)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            .accessibilityLabel(label(for: reference.source))
    }

    private func icon(for source: ItemReference.Source) -> String {
        switch source {
        case .itemPhoto: return "photo"
        case .enrolled: return "camera"
        case .learned: return "sparkles"
        }
    }

    private func label(for source: ItemReference.Source) -> String {
        switch source {
        case .itemPhoto: return "From item photo"
        case .enrolled: return "Added angle"
        case .learned: return "Learned from a scan"
        }
    }
}

/// A reference thumbnail loaded from its file on disk.
private struct ReferenceThumbnail: View {
    let url: URL
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Rectangle().fill(.quaternary)
            }
        }
        .task(id: url) {
            image = UIImage(contentsOfFile: url.path)
        }
    }
}

/// Multi-shot capture for "Add angles": every shutter tap stores one enrolled reference.
private struct EnrollCaptureView: View {
    let item: Item
    let store: RecognitionStore

    @Environment(\.dismiss) private var dismiss
    @State private var isWorking = false
    @State private var lastFailed = false

    private var count: Int {
        store.references(for: item.id).filter { $0.source == .enrolled }.count
    }

    private var isFull: Bool { count >= RecognitionStore.maxEnrolled }

    private var status: String {
        if isFull { return "All \(RecognitionStore.maxEnrolled) angles saved" }
        if lastFailed { return "Couldn't read that photo — try again" }
        return "Turn the item between shots · \(count)/\(RecognitionStore.maxEnrolled)"
    }

    var body: some View {
        NavigationStack {
            ScanCaptureStage(isBusy: isWorking || isFull, onPhoto: add) {
                Text(status)
                    .font(.callout)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .navigationTitle(item.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func add(_ data: Data) {
        isWorking = true
        Task {
            let saved = await store.enroll(imageData: data, itemId: item.id)
            lastFailed = !saved
            isWorking = false
            if saved { HapticManager.success() }
        }
    }
}
