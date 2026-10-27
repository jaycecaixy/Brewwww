import Foundation
import AVFoundation
import AppKit
import ImageIO
import UniformTypeIdentifiers

@main struct RecordingFrames {
    static func main() async throws {
        let args = CommandLine.arguments
        let input = URL(fileURLWithPath: args[1]), output = URL(fileURLWithPath: args[2], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let asset = AVURLAsset(url: input)
        let duration = try await asset.load(.duration).seconds
        let track = try await asset.loadTracks(withMediaType: .video).first!
        let size = try await track.load(.naturalSize), transform = try await track.load(.preferredTransform)
        let fps = try await track.load(.nominalFrameRate)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1000, height: 1000)
        generator.requestedTimeToleranceBefore = .zero; generator.requestedTimeToleranceAfter = .zero
        let times: [Double] = args.count > 3 ? args[3].split(separator: ",").compactMap { Double($0) }
            : Array(stride(from: 0.0, to: duration - 0.05, by: 2))
        var frames: [NSImage] = [], names: [String] = []
        for second in times where second < duration {
            let source = try generator.copyCGImage(at: CMTime(seconds: second, preferredTimescale: 600), actualTime: nil)
            let name = String(format: "%07.3f", second)
            let url = output.appendingPathComponent(name + ".png")
            let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
            CGImageDestinationAddImage(dest, source, nil); CGImageDestinationFinalize(dest)
            frames.append(NSImage(cgImage: source, size: NSSize(width: source.width, height: source.height)))
            names.append(name)
        }
        let cols = 4, tileW = 330, tileH = 350
        for page in stride(from: 0, to: frames.count, by: 16) {
            let selected = Array(frames[page..<min(page + 16, frames.count)])
            let rows = (selected.count + cols - 1) / cols
            let bitmap = NSBitmapImageRep(bitmapDataPlanes:nil, pixelsWide:cols*tileW, pixelsHigh:rows*tileH,
                bitsPerSample:8, samplesPerPixel:4, hasAlpha:true, isPlanar:false, colorSpaceName:.deviceRGB, bytesPerRow:0, bitsPerPixel:0)!
            NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
            NSColor(white:0.12,alpha:1).setFill(); NSRect(x:0,y:0,width:cols*tileW,height:rows*tileH).fill()
            for (index,img) in selected.enumerated() {
                let x = (index % cols) * tileW, y = (rows - 1 - index / cols) * tileH
                let scale = min(Double(tileW-12)/img.size.width, Double(tileH-30)/img.size.height)
                let rect=NSRect(x:Double(x)+6,y:Double(y)+25,width:img.size.width*scale,height:img.size.height*scale)
                img.draw(in:rect)
                (names[page+index]+"s" as NSString).draw(at:NSPoint(x:x+10,y:y+5), withAttributes:[.foregroundColor:NSColor.white,.font:NSFont.monospacedSystemFont(ofSize:14,weight:.medium)])
            }
            NSGraphicsContext.restoreGraphicsState()
            try bitmap.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent("contact-\(page/16).png"))
        }
        let info:[String:Any] = ["source":input.lastPathComponent,"duration":duration,"naturalSize":[size.width,size.height],"transform":[transform.a,transform.b,transform.c,transform.d,transform.tx,transform.ty],"fps":fps,"times":times]
        try JSONSerialization.data(withJSONObject:info,options:[.prettyPrinted,.sortedKeys]).write(to:output.appendingPathComponent("metadata.json"))
        print(String(data:try JSONSerialization.data(withJSONObject:info),encoding:.utf8)!)
    }
}
