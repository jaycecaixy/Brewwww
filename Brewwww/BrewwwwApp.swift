import SwiftUI
import UIKit

/// Reuse the existing brand artwork. A native silhouette mask excludes its
/// baked-in paper surround, so the real home paper stays continuous underneath.
struct LaunchLogoMark: View {
    var body: some View {
        Image("LaunchBrand").resizable().scaledToFit()
            .mask(LaunchBrandSilhouette())
            .accessibilityLabel("Un Caffèee!")
    }
}

private struct LaunchBrandSilhouette: Shape {
    private static let outline: Path = {
        guard let image = UIImage(named: "LaunchBrand")?.cgImage else { return Path() }
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let rendered = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard rendered else { return Path() }
        var left: [CGPoint] = [], right: [CGPoint] = []
        for y in 0..<height {
            var first: Int?, last = 0
            for x in 0..<width {
                let offset = (y * width + x) * 4
                let r = Int(pixels[offset]), g = Int(pixels[offset + 1]), b = Int(pixels[offset + 2])
                if r > g + 25 && g > b + 25 {
                    if first == nil { first = x }
                    last = x
                }
            }
            if let first {
                left.append(CGPoint(x: Double(first) / Double(width), y: Double(y) / Double(height)))
                right.append(CGPoint(x: Double(last + 1) / Double(width), y: Double(y) / Double(height)))
            }
        }
        // Scan only the outer contour; white lettering inside remains intact.
        var path = Path()
        path.addLines(left + right.reversed())
        path.closeSubpath()
        return path
    }()

    func path(in rect: CGRect) -> Path {
        Self.outline.applying(CGAffineTransform(scaleX: rect.width, y: rect.height)
            .concatenating(CGAffineTransform(translationX: rect.minX, y: rect.minY)))
    }
}

@main
struct BrewwwwApp: App {
    @UIApplicationDelegateAdaptor(BrewAppDelegate.self) private var appDelegate
    @StateObject private var store = BrewStore()
    @AppStorage("appearanceMode") private var appearanceMode = BrewAppearance.system.rawValue

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .preferredColorScheme((BrewAppearance(rawValue: appearanceMode) ?? .system).colorScheme)
        }
    }
}

final class BrewAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        BrewOrientationPolicy.shared.mask(for: window?.windowScene)
    }
}
