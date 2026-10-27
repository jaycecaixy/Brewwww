import Foundation
import AVFoundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

@main
struct ExtractReferenceFrames {
    static func main() async throws {
        let input = URL(fileURLWithPath: CommandLine.arguments[1])
        let output = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let asset = AVURLAsset(url: input)
        let duration = try await asset.load(.duration)
        let track = try await asset.loadTracks(withMediaType: .video).first!
        let descriptions = try await track.load(.formatDescriptions)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let times = [0, 1, 5, 10, 24, 28, 35, 39, 44, 50, 52, 60, 65, 75, 81, 90, 95, 99, 100, 110, 112, 123, 125]
        var frames: [[String: Any]] = []
        for second in times {
            var actual = CMTime.zero
            let source = try generator.copyCGImage(at: CMTime(seconds: Double(second), preferredTimescale: 600), actualTime: &actual)
            let width = source.width, height = source.height
            var data = Data(count: width * height * 4)
            let converted: CGImage = data.withUnsafeMutableBytes { bytes in
                let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                                        bitsPerComponent: 8, bytesPerRow: width * 4,
                                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
                context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
                return context.makeImage()!
            }
            let name = String(format: "%03d", second)
            let pngURL = output.appendingPathComponent(name + ".png")
            let destination = CGImageDestinationCreateWithURL(pngURL as CFURL, UTType.png.identifier as CFString, 1, nil)!
            CGImageDestinationAddImage(destination, converted, nil)
            guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
            try data.write(to: output.appendingPathComponent(name + ".rgba"))
            frames.append(["second": second, "actualSecond": actual.seconds, "width": width, "height": height,
                           "sourceColorSpace": source.colorSpace?.name as String? ?? "unknown",
                           "outputColorSpace": "sRGB", "png": name + ".png", "rgba": name + ".rgba"])
        }
        let metadata: [String: Any] = ["source": input.lastPathComponent, "duration": duration.seconds,
                                      "formatExtensions": descriptions.map { String(describing: CMFormatDescriptionGetExtensions($0)) },
                                      "frames": frames]
        try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("metadata.json"))
        print("Extracted \(frames.count) original-resolution frames in sRGB to \(output.path)")
    }
}
