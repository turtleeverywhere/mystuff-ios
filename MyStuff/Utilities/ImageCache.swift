import SwiftUI

/// Shared image cache with in-memory (NSCache, size-aware) and on-disk storage.
/// Per-size memory entries avoid decoding 1024 px just to draw a 40 pt circle.
final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()

    private let memoryCache = NSCache<NSString, UIImage>()
    private let fileManager = FileManager.default
    private let diskCacheURL: URL

    private init() {
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        diskCacheURL = caches.appendingPathComponent("ImageCache", isDirectory: true)
        try? fileManager.createDirectory(at: diskCacheURL, withIntermediateDirectories: true)
        // ~64 MB of decoded pixels (cost = w*h*4 bytes).
        memoryCache.totalCostLimit = 64 * 1024 * 1024
    }

    // MARK: - Keys

    private func memoryKey(url: URL, maxPixelSize: CGFloat) -> NSString {
        let sizeTag = maxPixelSize.isFinite ? "\(Int(maxPixelSize))" : "full"
        return "\(url.absoluteString)@\(sizeTag)" as NSString
    }

    private func diskURL(for url: URL) -> URL {
        let safe = url.absoluteString.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? url.absoluteString
        return diskCacheURL.appendingPathComponent(safe)
    }

    private func cost(of image: UIImage) -> Int {
        let cg = image.cgImage
        let w = cg?.width ?? Int(image.size.width * image.scale)
        let h = cg?.height ?? Int(image.size.height * image.scale)
        return max(1, w * h * 4)
    }

    private func storeInMemory(_ image: UIImage, key: NSString) {
        memoryCache.setObject(image, forKey: key, cost: cost(of: image))
    }

    // MARK: - Fetch

    /// Returns a UIImage for `url`, downsampled to at most `maxPixelSize`. Use `.infinity` for full size.
    /// If `persistTo` is provided and the source is remote, the downloaded bytes are also written
    /// to that path (used to lazily migrate remote photos into the on-device primary store).
    func image(for url: URL, maxPixelSize: CGFloat, persistTo: URL? = nil) async -> UIImage? {
        let key = memoryKey(url: url, maxPixelSize: maxPixelSize)

        if let cached = memoryCache.object(forKey: key) {
            return cached
        }

        return await Task.detached(priority: .userInitiated) { [self] () -> UIImage? in
            // 1. Local file — read + downsample directly.
            if url.isFileURL {
                guard fileManager.fileExists(atPath: url.path) else { return nil }
                let img: UIImage?
                if maxPixelSize.isFinite {
                    img = ImageDownsampler.downsample(url: url, maxPixelSize: maxPixelSize)
                } else if let data = try? Data(contentsOf: url) {
                    img = UIImage(data: data)
                } else {
                    img = nil
                }
                if let img { self.storeInMemory(img, key: key) }
                return img
            }

            // 2. Disk cache (raw bytes).
            let disk = diskURL(for: url)
            if let data = try? Data(contentsOf: disk) {
                let img = maxPixelSize.isFinite
                    ? ImageDownsampler.downsample(data: data, maxPixelSize: maxPixelSize)
                    : UIImage(data: data)
                if let img {
                    self.storeInMemory(img, key: key)
                    return img
                }
            }

            // 3. Network.
            guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
            try? data.write(to: disk)
            if let persistTo {
                try? fileManager.createDirectory(at: persistTo.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? data.write(to: persistTo)
            }
            let img = maxPixelSize.isFinite
                ? ImageDownsampler.downsample(data: data, maxPixelSize: maxPixelSize)
                : UIImage(data: data)
            if let img { self.storeInMemory(img, key: key) }
            return img
        }.value
    }

    // MARK: - Memory hints

    /// Pre-populate the memory cache for a freshly-captured image so the next display hits memory instantly.
    func setMemory(_ image: UIImage, for url: URL, maxPixelSize: CGFloat) {
        storeInMemory(image, key: memoryKey(url: url, maxPixelSize: maxPixelSize))
    }

    /// Evict all entries (every cached size) for a given URL, plus the disk-cache file.
    func evict(for url: URL) {
        // NSCache has no enumeration; we wipe known size tags and the disk entry.
        // Memory entries for unknown sizes will simply age out via cost limit.
        for tag in ["full", "84", "120", "240", "300", "900"] {
            memoryCache.removeObject(forKey: "\(url.absoluteString)@\(tag)" as NSString)
        }
        if !url.isFileURL {
            try? fileManager.removeItem(at: diskURL(for: url))
        }
    }
}
