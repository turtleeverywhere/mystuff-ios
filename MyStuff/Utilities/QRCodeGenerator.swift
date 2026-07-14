import UIKit
import CoreImage.CIFilterBuiltins

/// Generates crisp QR-code images from a string using CoreImage.
enum QRCodeGenerator {
    private static let context = CIContext()

    /// - Parameter scale: point multiplier applied to the raw QR matrix (higher = larger/crisper).
    /// - Returns: nil if generation fails.
    static func image(for string: String, scale: CGFloat = 12) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
