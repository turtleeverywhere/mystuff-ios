import SwiftUI

/// Shared image cache with in-memory (NSCache) and on-disk storage.
final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()

    private let memoryCache = NSCache<NSString, UIImage>()
    private let fileManager = FileManager.default
    private let diskCacheURL: URL

    private init() {
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        diskCacheURL = caches.appendingPathComponent("ImageCache", isDirectory: true)
        try? fileManager.createDirectory(at: diskCacheURL, withIntermediateDirectories: true)
        memoryCache.countLimit = 100
    }

    private func diskURL(for key: String) -> URL {
        let safe = key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? key
        return diskCacheURL.appendingPathComponent(safe)
    }

    func image(for url: URL) async -> UIImage? {
        let key = url.absoluteString as NSString

        // 1. Memory
        if let cached = memoryCache.object(forKey: key) {
            return cached
        }

        // 2. Local file URL — read directly
        if url.isFileURL {
            if let data = try? Data(contentsOf: url), let img = UIImage(data: data) {
                memoryCache.setObject(img, forKey: key)
                return img
            }
            return nil
        }

        // 3. Disk cache
        let disk = diskURL(for: url.absoluteString)
        if let data = try? Data(contentsOf: disk), let img = UIImage(data: data) {
            memoryCache.setObject(img, forKey: key)
            return img
        }

        // 4. Network
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let img = UIImage(data: data) else {
            return nil
        }
        memoryCache.setObject(img, forKey: key)
        try? data.write(to: disk)
        return img
    }

    /// Pre-populate memory cache (used for instant display of locally-saved photos).
    func setMemory(_ image: UIImage, for url: URL) {
        let key = url.absoluteString as NSString
        memoryCache.setObject(image, forKey: key)
    }

    func evict(for url: URL) {
        let key = url.absoluteString as NSString
        memoryCache.removeObject(forKey: key)
        if !url.isFileURL {
            try? fileManager.removeItem(at: diskURL(for: url.absoluteString))
        }
    }
}

/// Drop-in replacement for AsyncImage that uses the shared disk+memory cache.
struct CachedAsyncImage: View {
    let url: URL?
    let content: (Image) -> AnyView
    let placeholder: () -> AnyView

    @State private var uiImage: UIImage?

    init<C: View, P: View>(
        url: URL?,
        @ViewBuilder content: @escaping (Image) -> C,
        @ViewBuilder placeholder: @escaping () -> P
    ) {
        self.url = url
        self.content = { AnyView(content($0)) }
        self.placeholder = { AnyView(placeholder()) }
    }

    var body: some View {
        Group {
            if let uiImage {
                content(Image(uiImage: uiImage))
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            guard let url else {
                uiImage = nil
                return
            }
            uiImage = await ImageCache.shared.image(for: url)
        }
    }
}
