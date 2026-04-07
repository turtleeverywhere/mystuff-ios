import Foundation
import Network
import UIKit

/// Manages offline-first photo storage: saves locally for instant display, uploads to cloud in background.
@MainActor
final class PhotoUploadManager: @unchecked Sendable {
    static let shared = PhotoUploadManager()

    private let fileManager = FileManager.default
    private let localPhotosDir: URL
    private let pendingFile: URL
    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "PhotoUploadMonitor")
    private var isConnected = true
    private var isProcessing = false

    struct PendingUpload: Codable {
        let itemId: String
        let filename: String      // "photo" or "item_photo"
        let localPath: String     // relative to localPhotosDir
        let oldRemoteURL: String? // previous remote URL to delete
    }

    private var pending: [PendingUpload] = []

    private init() {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        localPhotosDir = docs.appendingPathComponent("Photos", isDirectory: true)
        pendingFile = docs.appendingPathComponent("pending_uploads.json")
        try? fileManager.createDirectory(at: localPhotosDir, withIntermediateDirectories: true)
        loadPending()
        startMonitoring()
    }

    // MARK: - Local Storage

    /// Saves compressed photo locally and returns the local file URL immediately.
    func saveLocally(itemId: String, imageData: Data, filename: String) -> URL {
        let name = "\(itemId)_\(filename).jpg"
        let fileURL = localPhotosDir.appendingPathComponent(name)
        try? imageData.write(to: fileURL)

        // Pre-populate image cache so CachedAsyncImage picks it up instantly
        if let img = UIImage(data: imageData) {
            ImageCache.shared.setMemory(img, for: fileURL)
        }

        return fileURL
    }

    /// Queues a background upload. Call after saving locally + updating the item.
    func enqueueUpload(itemId: String, filename: String, localURL: URL, oldRemoteURL: String?) {
        // Remove any existing pending upload for same item+filename
        pending.removeAll { $0.itemId == itemId && $0.filename == filename }

        let upload = PendingUpload(
            itemId: itemId,
            filename: filename,
            localPath: localURL.lastPathComponent,
            oldRemoteURL: oldRemoteURL
        )
        pending.append(upload)
        savePending()
        Task { await processPending() }
    }

    // MARK: - Network Monitoring

    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                let wasDisconnected = self?.isConnected == false
                self?.isConnected = path.status == .satisfied
                if wasDisconnected && path.status == .satisfied {
                    await self?.processPending()
                }
            }
        }
        monitor.start(queue: monitorQueue)
    }

    // MARK: - Upload Processing

    /// Callback set by StuffViewModel to update item URLs after upload.
    var onUploadComplete: ((_ itemId: String, _ filename: String, _ remoteURL: String) async -> Void)?

    func processPending() async {
        guard isConnected, !isProcessing, !pending.isEmpty else { return }
        isProcessing = true
        defer { isProcessing = false }

        // Snapshot current pending to iterate
        let toProcess = pending

        for upload in toProcess {
            let localURL = localPhotosDir.appendingPathComponent(upload.localPath)
            guard let data = try? Data(contentsOf: localURL) else {
                // File gone, remove from queue
                pending.removeAll { $0.localPath == upload.localPath }
                savePending()
                continue
            }

            do {
                let storageService: StorageService = FirebaseStorageService()

                // Delete old remote photo if replacing
                if let oldURL = upload.oldRemoteURL {
                    try? await storageService.deletePhoto(url: oldURL)
                }

                let remoteURL = try await storageService.uploadPhoto(
                    itemId: upload.itemId,
                    imageData: data,
                    filename: upload.filename
                )

                // Update item with remote URL
                await onUploadComplete?(upload.itemId, upload.filename, remoteURL)

                // Cache the image under the new remote URL too
                if let img = UIImage(data: data), let url = URL(string: remoteURL) {
                    ImageCache.shared.setMemory(img, for: url)
                }

                // Clean up
                pending.removeAll { $0.localPath == upload.localPath }
                savePending()

                // Keep local file for cache but it'll be superseded by remote cache
            } catch {
                // Network error — stop processing, will retry when connected
                break
            }
        }
    }

    /// Number of pending uploads (for UI indicator if desired)
    var pendingCount: Int { pending.count }

    // MARK: - Persistence

    private func loadPending() {
        guard let data = try? Data(contentsOf: pendingFile),
              let decoded = try? JSONDecoder().decode([PendingUpload].self, from: data) else { return }
        pending = decoded
    }

    private func savePending() {
        let data = try? JSONEncoder().encode(pending)
        try? data?.write(to: pendingFile)
    }

    /// Clean up local file when a photo is deleted
    func removeLocal(itemId: String, filename: String) {
        let name = "\(itemId)_\(filename).jpg"
        let fileURL = localPhotosDir.appendingPathComponent(name)
        try? fileManager.removeItem(at: fileURL)
        pending.removeAll { $0.itemId == itemId && $0.filename == filename }
        savePending()
    }
}
