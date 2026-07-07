import ImageIO
import UIKit

/// Memory-efficient image downsampling via ImageIO. Decodes only the pixels needed.
enum ImageDownsampler {

    /// Downsample a file URL to a UIImage capped at `maxPixelSize` in its largest dimension.
    static func downsample(url: URL, maxPixelSize: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }
        return makeThumbnail(from: source, maxPixelSize: maxPixelSize)
    }

    /// Downsample raw Data (e.g. just-fetched from network) to a UIImage at target pixel size.
    static func downsample(data: Data, maxPixelSize: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        return makeThumbnail(from: source, maxPixelSize: maxPixelSize)
    }

    private static func makeThumbnail(from source: CGImageSource, maxPixelSize: CGFloat) -> UIImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }
}
