import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Decode the supplied light-mode screenshots into sRGB before taking samples.
// Usage: swift scripts/sample-light-reference.swift <directory containing 1-照片-1.jpg ...>
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let input = URL(fileURLWithPath: CommandLine.arguments[1])
let output = root.appendingPathComponent("设计取色/light-samples")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
var images: [Int: CGImage] = [:]
var bytes: [Int: [UInt8]] = [:]
for number in 1...3 {
    let file = input.appendingPathComponent("\(number)-照片-\(number).jpg")
    let source = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(file as CFURL, nil)!, 0, nil)!
    var data = [UInt8](repeating: 0, count: source.width * source.height * 4)
    let image = data.withUnsafeMutableBytes { buffer -> CGImage in
        let context = CGContext(data: buffer.baseAddress, width: source.width, height: source.height,
                                bitsPerComponent: 8, bytesPerRow: source.width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
        context.draw(source, in: CGRect(x: 0, y: 0, width: source.width, height: source.height))
        return context.makeImage()!
    }
    images[number] = image; bytes[number] = data
}
func write(_ image: CGImage, to file: URL) {
    let dest = CGImageDestinationCreateWithURL(file as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil); precondition(CGImageDestinationFinalize(dest))
}
let samples: [(String, Int, [Int], String)] = [
    ("paper", 1, [30, 1100, 240, 170], "background"),
    ("text", 1, [265, 110, 150, 36], "dark"),
    ("muted", 1, [169, 211, 380, 25], "medium"),
    ("control", 1, [766, 389, 40, 12], "background"),
    ("icon", 1, [769, 357, 39, 39], "medium"),
    ("selection", 1, [771, 865, 35, 16], "background"),
    ("gold", 3, [419, 266, 224, 28], "gold"),
    ("orange", 1, [94, 304, 245, 242], "orange"),
    ("sheet", 2, [40, 1220, 650, 40], "background"),
    ("cataloguePanel", 2, [260, 346, 300, 22], "background")
]
var report: [[String: Any]] = []
for (name, number, rect, filter) in samples {
    let image = images[number]!, data = bytes[number]!
    var pixels: [[Int]] = []
    for y in rect[1]..<(rect[1]+rect[3]) {
        for x in rect[0]..<(rect[0]+rect[2]) {
            let i = (y * image.width + x) * 4
            let c = [Int(data[i]), Int(data[i+1]), Int(data[i+2])]
            let low = c.min()!, high = c.max()!
            if filter == "dark" && high > 105 { continue }
            if filter == "medium" && (low < 65 || high > 180 || high-low > 45) { continue }
            if filter == "gold" && !(c[0] > 150 && c[1] > 100 && c[1] < 180 && c[2] < 140 && c[0]-c[2] > 60) { continue }
            if filter == "orange" && !(c[0] > 160 && c[0]-c[1] > 55 && c[1]-c[2] > 30) { continue }
            pixels.append(c)
        }
    }
    let median = (0..<3).map { channel in pixels.map { $0[channel] }.sorted()[pixels.count/2] }
    let hex = String(format: "#%02X%02X%02X", median[0], median[1], median[2])
    write(image.cropping(to: CGRect(x: rect[0], y: rect[1], width: rect[2], height: rect[3]))!,
          to: output.appendingPathComponent(name + ".png"))
    report.append(["name": name, "screenshot": number, "rect": rect, "sRGB": hex,
                   "filter": filter, "matchedPixels": pixels.count])
    print("\(name): \(hex) (\(pixels.count) pixels)")
}
try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
    .write(to: root.appendingPathComponent("设计取色/light-reference-colors.json"))
// Unobstructed paper only: no text, icons, stamps, gradients or blurred artwork.
let paper = images[1]!.cropping(to: CGRect(x: 30, y: 1100, width: 240, height: 170))!
for name in ["PaperReference", "PaperPreview1", "PaperPreview2", "PaperPreview3"] {
    let asset = root.appendingPathComponent("Brewwww/Assets.xcassets/\(name).imageset")
    write(paper, to: asset.appendingPathComponent("\(name)-Light@3x.png"))
    let contents: [String: Any] = ["info": ["author": "xcode", "version": 1], "images": [
        ["filename": "\(name)-Light@3x.png", "idiom": "universal", "scale": "3x"],
        ["filename": "\(name)@3x.png", "idiom": "universal", "scale": "3x",
         "appearances": [["appearance": "luminosity", "value": "dark"]]]
    ]]
    try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
        .write(to: asset.appendingPathComponent("Contents.json"))
}
