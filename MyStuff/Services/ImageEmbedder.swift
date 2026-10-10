import CoreImage
import CoreML
import Foundation
import UIKit
import Vision

/// The result of embedding one photo.
struct Embedding: Sendable, Equatable {
    let vector: [Float]
    /// JPEG of the crop that was embedded, at most 320 px. Stored as the reference thumbnail.
    let thumbnail: Data
}

enum EmbeddingError: Error {
    case unreadableImage
    case emptyVector
}

/// Turns a photo into a vector such that photos of the same object land close
/// together. Behind a protocol so the model can be swapped (e.g. for MobileCLIP)
/// without touching storage, matching, or UI.
protocol ImageEmbedder: Sendable {
    /// Identifies model + revision. Vectors are only comparable within one modelID.
    var modelID: String { get }
    /// `imageData` is an encoded image (JPEG/HEIC/PNG); EXIF orientation is honoured.
    func embed(imageData: Data) async throws -> Embedding
}

/// Apple Vision feature print over the photo's foreground subject.
struct VisionFeaturePrintEmbedder: ImageEmbedder {
    let modelID = "vision-featureprint-r2"

    static let workingPixelSize: CGFloat = 1024
    static let thumbnailPixelSize: CGFloat = 320
    /// Subjects smaller than this are treated as noise and ignored.
    static let minSubjectSide = 64
    static let fallbackCropFraction: CGFloat = 0.7

    func embed(imageData: Data) async throws -> Embedding {
        guard let source = ImageDownsampler.downsample(data: imageData, maxPixelSize: Self.workingPixelSize)?.cgImage else {
            throw EmbeddingError.unreadableImage
        }
        // Embed the subject alone so the shelf behind it doesn't dominate the vector.
        // References and scan captures both go through here, so they stay comparable.
        let crop = (try? await Self.subjectCrop(of: source)) ?? Self.centerSquare(of: source)

        var request = GenerateImageFeaturePrintRequest(.revision2)
        #if targetEnvironment(simulator)
        // The simulator's default (GPU) device can't build an inference context, so
        // pin to CPU. That keeps the flow usable there, but the vectors it produces
        // are near-constant: recognition quality can only be judged on a device.
        // Don't look the device up via `request.supportedComputeStageDevices` — that
        // symbol is missing from iOS 26 runtimes and the app dies in dyld at launch.
        if let cpu = MLComputeDevice.allComputeDevices.first(where: { if case .cpu = $0 { true } else { false } }) {
            request.setComputeDevice(cpu, for: .main)
        }
        #endif
        let observation = try await request.perform(on: crop)
        guard observation.elementType == .float else { throw EmbeddingError.emptyVector }
        let vector = [Float](rawData: observation.data)
        guard !vector.isEmpty else { throw EmbeddingError.emptyVector }

        guard let jpeg = UIImage(cgImage: crop).jpegData(compressionQuality: 0.8),
              let thumbnail = ImageDownsampler.downsample(data: jpeg, maxPixelSize: Self.thumbnailPixelSize)?
                .jpegData(compressionQuality: 0.7)
        else { throw EmbeddingError.unreadableImage }

        return Embedding(vector: vector, thumbnail: thumbnail)
    }

    /// The foreground object under the image centre (else every foreground object),
    /// background blacked out, cropped to its extent. nil when Vision finds no subject.
    /// Throws in the simulator, which can't run this request; the caller falls back.
    private static func subjectCrop(of image: CGImage) async throws -> CGImage? {
        let handler = ImageRequestHandler(image)
        guard let observation = try await handler.perform(GenerateForegroundInstanceMaskRequest()) else { return nil }

        var instances = observation.instanceAtPoint(NormalizedPoint(x: 0.5, y: 0.5))
        instances.remove(0) // index 0 is the background
        if instances.isEmpty { instances = observation.allInstances }
        guard !instances.isEmpty else { return nil }

        let buffer = try observation.generateMaskedImage(
            for: instances,
            imageFrom: handler,
            croppedToInstancesExtent: true
        )
        let masked = CIImage(cvPixelBuffer: buffer)
        let opaque = masked.composited(over: CIImage(color: .black).cropped(to: masked.extent))
        guard let result = CIContext().createCGImage(opaque, from: masked.extent),
              min(result.width, result.height) >= minSubjectSide
        else { return nil }
        return result
    }

    /// Fallback when no subject is found: the middle of the frame, where the reticle is.
    static func centerSquare(of image: CGImage) -> CGImage {
        let side = (CGFloat(min(image.width, image.height)) * fallbackCropFraction).rounded()
        let rect = CGRect(
            x: ((CGFloat(image.width) - side) / 2).rounded(),
            y: ((CGFloat(image.height) - side) / 2).rounded(),
            width: side,
            height: side
        )
        return image.cropping(to: rect) ?? image
    }
}
