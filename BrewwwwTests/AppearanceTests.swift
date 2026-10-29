import XCTest
import SwiftUI
@testable import Brewwww

final class AppearanceTests: XCTestCase {
    func testSystemAppearanceDoesNotOverrideTheOS() {
        XCTAssertNil(BrewAppearance.system.colorScheme)
        XCTAssertEqual(BrewAppearance.light.colorScheme, .light)
        XCTAssertEqual(BrewAppearance.dark.colorScheme, .dark)
    }

    func testRecordedDarkColorsAndLightScreenshotColorsResolveIndependently() {
        assertColor(BrewStyle.text, style: .dark, hex: 0xD3D0CB)
        assertColor(BrewStyle.text, style: .light, hex: 0x3C2723)
        assertColor(BrewStyle.panel, style: .dark, hex: 0x463E36)
        assertColor(BrewStyle.panel, style: .light, hex: 0xF0EDE7)
        assertColor(BrewStyle.gold, style: .dark, hex: 0xDCAB70)
        assertColor(BrewStyle.gold, style: .light, hex: 0xC5925E)
        assertColor(BrewStyle.control, style: .dark, hex: 0x383734)
        assertColor(BrewStyle.control, style: .light, hex: 0xF1F0EC)
    }

    func testPaperAssetsHaveGenuinelyDifferentLightAndDarkVariants() throws {
        for name in ["PaperReference", "PaperPreview1", "PaperPreview2", "PaperPreview3"] {
            let light = try XCTUnwrap(UIImage(named: name, in: Bundle.main,
                                             compatibleWith: UITraitCollection(userInterfaceStyle: .light)))
            let dark = try XCTUnwrap(UIImage(named: name, in: Bundle.main,
                                            compatibleWith: UITraitCollection(userInterfaceStyle: .dark)))
            XCTAssertGreaterThan(try brightness(light), 0.85, name)
            XCTAssertLessThan(try brightness(dark), 0.30, name)
        }
    }

    func testPhotographyAndStampArtworkKeepTheirOriginalColors() {
        for (color, hex) in [(BrewStyle.photoFrame, UInt32(0xDFB16F)),
                             (BrewStyle.photoWhite, UInt32(0xFEFEFE)),
                             (BrewStyle.photoInk, UInt32(0x321500))] {
            assertColor(color, style: .light, hex: hex)
            assertColor(color, style: .dark, hex: hex)
        }
    }

    private func assertColor(_ color: Color, style: UIUserInterfaceStyle, hex: UInt32,
                             file: StaticString = #filePath, line: UInt = #line) {
        let resolved = UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        XCTAssertTrue(resolved.getRed(&r, green: &g, blue: &b, alpha: &a), file: file, line: line)
        XCTAssertEqual(r, CGFloat((hex >> 16) & 255) / 255, accuracy: 0.002, file: file, line: line)
        XCTAssertEqual(g, CGFloat((hex >> 8) & 255) / 255, accuracy: 0.002, file: file, line: line)
        XCTAssertEqual(b, CGFloat(hex & 255) / 255, accuracy: 0.002, file: file, line: line)
    }

    private func brightness(_ image: UIImage) throws -> Double {
        let source = try XCTUnwrap(image.cgImage)
        var bytes = [UInt8](repeating: 0, count: 4)
        let context = try XCTUnwrap(CGContext(data: &bytes, width: 1, height: 1, bitsPerComponent: 8,
                                              bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.interpolationQuality = .high
        context.draw(source, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return Double(Int(bytes[0]) + Int(bytes[1]) + Int(bytes[2])) / (255 * 3)
    }
}
