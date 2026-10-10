import Testing
import UIKit
@testable import MyStuff

#if targetEnvironment(simulator)
private let isSimulator = true
#else
private let isSimulator = false
#endif

/// Runs the real Vision pipeline in the simulator: proves the request types and
/// the Float decoding work, not that recognition is accurate.
@MainActor
struct VisionFeaturePrintEmbedderTests {

    /// A filled circle on a plain background, as JPEG.
    private func image(circle: UIColor, background: UIColor) -> Data {
        let size = CGSize(width: 400, height: 400)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            background.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            circle.setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 100, y: 100, width: 200, height: 200))
        }.jpegData(compressionQuality: 0.9)!
    }

    @Test func sameImageEmbedsToTheSameVector() async throws {
        let embedder = VisionFeaturePrintEmbedder()
        let data = image(circle: .red, background: .white)
        let first = try await embedder.embed(imageData: data)
        let second = try await embedder.embed(imageData: data)
        #expect(!first.vector.isEmpty)
        #expect(ItemMatcher.distance(first.vector, second.vector) < 0.01)
    }

    @Test func thumbnailIsADecodableImageNoLargerThan320() async throws {
        let embedding = try await VisionFeaturePrintEmbedder().embed(imageData: image(circle: .red, background: .white))
        let thumbnail = try #require(UIImage(data: embedding.thumbnail)?.cgImage)
        #expect(max(thumbnail.width, thumbnail.height) <= 320)
    }

    @Test(.disabled(if: isSimulator, "The simulator's CPU feature print is near-constant for every image"))
    func differentImagesAreFartherApartThanIdenticalOnes() async throws {
        let embedder = VisionFeaturePrintEmbedder()
        let red = try await embedder.embed(imageData: image(circle: .red, background: .white))
        let again = try await embedder.embed(imageData: image(circle: .red, background: .white))
        let other = try await embedder.embed(imageData: image(circle: .black, background: .yellow))
        #expect(ItemMatcher.distance(red.vector, other.vector) > ItemMatcher.distance(red.vector, again.vector))
    }

    @Test func unreadableDataThrows() async {
        await #expect(throws: EmbeddingError.self) {
            try await VisionFeaturePrintEmbedder().embed(imageData: Data("not an image".utf8))
        }
    }

    @Test func centerSquareIsCentredAndSquare() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let wide = try #require(UIGraphicsImageRenderer(size: CGSize(width: 200, height: 100), format: format)
            .image { _ in }.cgImage)
        let square = VisionFeaturePrintEmbedder.centerSquare(of: wide)
        #expect(square.width == 70)
        #expect(square.height == 70)
    }
}
