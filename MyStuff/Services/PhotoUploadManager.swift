import Foundation
import Network
import UIKit

/// Manages offline-first photo storage: full + thumb files saved locally for instant display,
/// full image uploaded to Firebase Storage in the background for sync. Thumbs are local-only —
/// other devices generate their own on first remote fetch.
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
        let oldRemoteURL: String? // previous remote URL to delete after upload
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

    // MARK: - Path helpers

    /// Relative path stored on `Item` (e.g. "Photos/abc_photo.jpg").
    static func relativePath(itemId: String, filename: String) -> String {
        "Photos/\(itemId)_\(filename).jpg"
    }

    static func relativeThumbPath(itemId: String, filename: String) -> String {
        "Photos/\(itemId)_\(filename)_thumb.jpg"
    }

    /// Resolve a relative photo path against the Documents directory.
    static func absoluteURL(forRelative path: String) -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent(path)
    }

    /// Derive the thumbnail path for a given full-size relative path.
    static func thumbPath(forFullRelative path: String) -> String {
        guard path.hasSuffix(".jpg") else { return path + "_thumb" }
        return String(path.dropLast(4)) + "_thumb.jpg"
    }

    func localFullURL(itemId: String, filename: String) -> URL {
        localPhotosDir.appendingPathComponent("\(itemId)_\(filename).jpg")
    }

    func localThumbURL(itemId: String, filename: String) -> URL {
        localPhotosDir.appendingPathComponent("\(itemId)_\(filename)_thumb.jpg")
    }

    // MARK: - Local Storage

    /// Saves compressed full + thumb photos locally. Pre-warms image cache. Returns the
    /// relative path the item should store (e.g. "Photos/abc_photo.jpg").
    func saveLocally(itemId: String, fullData: Data, thumbData: Data, filename: String) -> String {
        let fullURL = localFullURL(itemId: itemId, filename: filename)
        let thumbURL = localThumbURL(itemId: itemId, filename: filename)
        try? fullData.write(to: fullURL)
        try? thumbData.write(to: thumbURL)

        // Pre-populate image cache so next render hits memory instantly.
        if let full = UIImage(data: fullData) {
            ImageCache.shared.setMemory(full, for: fullURL, maxPixelSize: .infinity)
        }
        if let thumb = UIImage(data: thumbData) {
            ImageCache.shared.setMemory(thumb, for: thumbURL, maxPixelSize: ImageHelper.thumbMaxDimension)
            // Most common list sizes also benefit from a pre-warm under common keys.
            for size in [CGFloat(84), 120, 240] {
                ImageCache.shared.setMemory(thumb, for: thumbURL, maxPixelSize: size)
            }
        }

        return Self.relativePath(itemId: itemId, filename: filename)
    }

    /// Queues a background upload of the full-size photo. Call after saving locally + updating the item.
    func enqueueUpload(itemId: String, filename: String, oldRemoteURL: String?) {
        pending.removeAll { $0.itemId == itemId && $0.filename == filename }
        pending.append(PendingUpload(itemId: itemId, filename: filename, oldRemoteURL: oldRemoteURL))
        savePending()
        Task { await processPending() }
    }

    // MARK: - Local Cleanup

    /// Remove local full + thumb files for a given item/filename.
    func removeLocal(itemId: String, filename: String) {
        try? fileManager.removeItem(at: localFullURL(itemId: itemId, filename: filename))
        try? fileManager.removeItem(at: localThumbURL(itemId: itemId, filename: filename))
        pending.removeAll { $0.itemId == itemId && $0.filename == filename }
        savePending()
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

    /// Callback fired after the full-size upload completes. ViewModel updates `remotePhotoURL`.
    var onUploadComplete: ((_ itemId: String, _ filename: String, _ remoteURL: String) async -> Void)?

    func processPending() async {
        guard isConnected, !isProcessing, !pending.isEmpty else { return }
        isProcessing = true
        defer { isProcessing = false }

        let toProcess = pending
        for upload in toProcess {
            let fullURL = localFullURL(itemId: upload.itemId, filename: upload.filename)
            guard let data = try? Data(contentsOf: fullURL) else {
                pending.removeAll { $0.itemId == upload.itemId && $0.filename == upload.filename }
                savePending()
                continue
            }

            do {
                let storageService: StorageService = FirebaseStorageService()

                if let oldURL = upload.oldRemoteURL {
                    try? await storageService.deletePhoto(url: oldURL)
                }

                let remoteURL = try await storageService.uploadPhoto(
                    itemId: upload.itemId,
                    imageData: data,
                    filename: upload.filename
                )

                await onUploadComplete?(upload.itemId, upload.filename, remoteURL)

                pending.removeAll { $0.itemId == upload.itemId && $0.filename == upload.filename }
                savePending()
            } catch {
                // Network error — stop processing; retry on next connectivity event.
                break
            }
        }
    }

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
}
