import UIKit

enum ImageHelper {

    static let defaultMaxDimension: CGFloat = 1024
    static let defaultQuality: CGFloat = 0.6
    static let thumbMaxDimension: CGFloat = 320
    static let thumbQuality: CGFloat = 0.7

    static func compress(_ data: Data, maxDimension: CGFloat = defaultMaxDimension, quality: CGFloat = defaultQuality) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        return resize(image, maxDimension: maxDimension)?.jpegData(compressionQuality: quality)
    }

    /// Produce both a full-size and a thumbnail variant from raw camera/library data.
    static func compressWithThumbnail(_ data: Data) -> (full: Data, thumb: Data)? {
        guard let image = UIImage(data: data),
              let full = resize(image, maxDimension: defaultMaxDimension)?.jpegData(compressionQuality: defaultQuality),
              let thumb = resize(image, maxDimension: thumbMaxDimension)?.jpegData(compressionQuality: thumbQuality)
        else { return nil }
        return (full, thumb)
    }

    private static func resize(_ image: UIImage, maxDimension: CGFloat) -> UIImage? {
        let size = image.size
        let scale = min(maxDimension / max(size.width, size.height), 1.0)
        if scale >= 1.0 {
            return image
        }
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
