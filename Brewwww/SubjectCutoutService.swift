import Foundation
import CoreGraphics
import CoreImage
import ImageIO
import Vision

struct SubjectCutoutResult: Sendable {
    let pngData: Data
    let subjectCount: Int
    let processingTime: TimeInterval
}

enum SubjectCutoutError: LocalizedError {
    case invalidImage
    case noSubject
    case renderingFailed
    case unavailableInSimulator

    var errorDescription: String? {
        switch self {
        case .invalidImage: return "无法读取这张照片，请重新选择。"
        case .noSubject: return "没有找到清晰主体，可以重试或使用原图。"
        case .renderingFailed: return "暂时无法生成贴纸，可以重试或使用原图。"
        case .unavailableInSimulator: return "当前模拟器无法运行主体抠图，请在 iPhone 上试用。"
        }
    }
}

/// Vision inference and compositing run on this actor, away from the UI actor.
/// Only the sticker input is resized; the separately saved original is unchanged.
actor SubjectCutoutService {
    static let shared = SubjectCutoutService()

    private let context = CIContext(options: [.cacheIntermediates: false])
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private let maximumDimension: CGFloat = 1600
    private var attemptedPreparation = false

    /// Begin loading Vision while the user is choosing a photo, without delaying UI.
    func prepareIfNeeded() {
        guard !attemptedPreparation, !Task.isCancelled else { return }
        attemptedPreparation = true
        let image = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5))
            .cropped(to: CGRect(x: 0, y: 0, width: 512, height: 512))
        let request = VNGenerateForegroundInstanceMaskRequest()
        try? VNImageRequestHandler(ciImage: image, options: [:]).perform([request])
    }

    func makeSticker(from image: CGImage,
                     orientation: CGImagePropertyOrientation = .up) throws -> SubjectCutoutResult {
        try Task.checkCancellation()
        let started = Date()
        return try autoreleasepool {
            var input = CIImage(cgImage: image).oriented(orientation)
            input = input.transformed(by: CGAffineTransform(translationX: -input.extent.minX,
                                                           y: -input.extent.minY))
            let longestEdge = max(input.extent.width, input.extent.height)
            guard longestEdge > 0 else { throw SubjectCutoutError.invalidImage }
            if longestEdge > maximumDimension {
                let scale = maximumDimension / longestEdge
                input = input.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            }

            let request = VNGenerateForegroundInstanceMaskRequest()
            let handler = VNImageRequestHandler(ciImage: input, options: [:])
            do {
                try handler.perform([request])
            } catch {
                #if targetEnvironment(simulator)
                let error = error as NSError
                if error.domain == "com.apple.Vision", error.code == 9 {
                    throw SubjectCutoutError.unavailableInSimulator
                }
                #endif
                throw error
            }
            try Task.checkCancellation()

            guard let observation = request.results?.first, !observation.allInstances.isEmpty else {
                throw SubjectCutoutError.noSubject
            }
            // Keep all detected subjects in the first version, including multiple cups.
            let masked = try observation.generateMaskedImage(ofInstances: observation.allInstances,
                                                             from: handler,
                                                             croppedToInstancesExtent: true)
            let foreground = CIImage(cvPixelBuffer: masked)
            let png = try outlinedPNG(for: foreground)
            try Task.checkCancellation()
            return SubjectCutoutResult(pngData: png,
                                       subjectCount: observation.allInstances.count,
                                       processingTime: Date().timeIntervalSince(started))
        }
    }

    /// Expand the alpha silhouette, then composite white beneath the foreground.
    /// This makes a real contour border and leaves the outside transparent.
    func outlinedPNG(for foreground: CIImage) throws -> Data {
        let bounds = foreground.extent
        guard !bounds.isEmpty, !bounds.isInfinite else { throw SubjectCutoutError.invalidImage }
        let radius = max(4, min(30, max(bounds.width, bounds.height) * 0.018))
        let paddedBounds = bounds.insetBy(dx: -ceil(radius + 2), dy: -ceil(radius + 2)).integral
        let clear = CIImage(color: .clear).cropped(to: paddedBounds)
        let expandedInput = foreground.composited(over: clear)
        let dilated = expandedInput.applyingFilter("CIMorphologyMaximum", parameters: [
            kCIInputRadiusKey: radius
        ]).cropped(to: paddedBounds)
        let white = CIImage(color: .white).cropped(to: paddedBounds)
        let outline = white.applyingFilter("CIBlendWithAlphaMask", parameters: [
            kCIInputBackgroundImageKey: clear,
            kCIInputMaskImageKey: dilated
        ])
        let sticker = foreground.composited(over: outline).cropped(to: paddedBounds)
        guard let png = context.pngRepresentation(of: sticker, format: .RGBA8,
                                                   colorSpace: colorSpace, options: [:]) else {
            throw SubjectCutoutError.renderingFailed
        }
        return png
    }
}
