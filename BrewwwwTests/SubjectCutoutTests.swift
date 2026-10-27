import XCTest
import CoreImage
import ImageIO
import UIKit
@testable import Brewwww

final class SubjectCutoutTests: XCTestCase {
    func testOldRecordsStillDecodeWithoutSticker() throws {
        let json = """
        {"id":"A600E6B6-EB14-4989-A117-2B6CE5BAC734","date":0,"shop":"店铺","city":"上海市","name":"咖啡","note":"","favorite":false,"photoFile":"original.jpg"}
        """
        let record = try JSONDecoder().decode(DrinkRecord.self, from: Data(json.utf8))
        XCTAssertEqual(record.photoFile, "original.jpg")
        XCTAssertNil(record.stickerFile)
    }

    func testContourHasWhiteBorderAndTransparentOutside() async throws {
        let foreground = Self.foreground()
        let data = try await SubjectCutoutService.shared.outlinedPNG(for: CIImage(cgImage: foreground))
        let image = try XCTUnwrap(UIImage(data: data)?.cgImage)
        let pixels = Self.pixels(image)
        XCTAssertGreaterThan(image.width, foreground.width)
        XCTAssertEqual(pixels[3], 0, "贴纸四周应透明")
        let center = ((image.height / 2) * image.width + image.width / 2) * 4
        XCTAssertGreaterThan(pixels[center], 220)
        XCTAssertLessThan(pixels[center + 1], 30)
        XCTAssertEqual(pixels[center + 3], 255)
        let whitePixels = stride(from: 0, to: pixels.count, by: 4).filter {
            pixels[$0] > 240 && pixels[$0 + 1] > 240 && pixels[$0 + 2] > 240 && pixels[$0 + 3] > 240
        }.count
        XCTAssertGreaterThan(whitePixels, 100, "白边应沿真实主体轮廓绘制")
    }

    @MainActor func testPhotoAndStickerPersistSeparatelyAndCanBeRemoved() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = UIImage(cgImage: Self.foreground())
        let sticker = try await SubjectCutoutService.shared.outlinedPNG(for: CIImage(cgImage: Self.foreground()))
        let store = BrewStore(directory: directory)
        try store.add(DrinkRecord(shop: "测试", name: "美式"), photo: original, stickerData: sticker)
        let record = try XCTUnwrap(store.records.first)
        XCTAssertNotEqual(record.photoFile, record.stickerFile)
        let originalFile = directory.appendingPathComponent(try XCTUnwrap(record.photoFile))
        let stickerFile = directory.appendingPathComponent(try XCTUnwrap(record.stickerFile))
        XCTAssertTrue(FileManager.default.fileExists(atPath: originalFile.path))
        XCTAssertEqual(try Data(contentsOf: stickerFile), sticker)

        let reopened = BrewStore(directory: directory)
        let saved = try XCTUnwrap(reopened.records.first)
        XCTAssertNotNil(reopened.image(for: saved))
        XCTAssertNotNil(reopened.sticker(for: saved))

        var originalOnly = saved
        originalOnly.stickerFile = nil
        try reopened.update(originalOnly)
        XCTAssertFalse(FileManager.default.fileExists(atPath: stickerFile.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: originalFile.path))
        reopened.delete(originalOnly)
        XCTAssertFalse(FileManager.default.fileExists(atPath: originalFile.path))
        XCTAssertTrue(BrewStore(directory: directory).records.isEmpty)
    }

    func testRealCoffeePhotoWithAppleVision() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "coffee", withExtension: "jpg"))
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let input = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let result: SubjectCutoutResult
        do {
            result = try await SubjectCutoutService.shared.makeSticker(from: input)
        } catch SubjectCutoutError.unavailableInSimulator {
            throw XCTSkip("当前模拟器无法创建 Vision 推理上下文；真实照片效果已通过同一处理代码在 Mac 验证，iPhone 需真机复核。")
        }
        XCTAssertGreaterThan(result.subjectCount, 0)
        let image = try XCTUnwrap(UIImage(data: result.pngData))
        let cgImage = try XCTUnwrap(image.cgImage)
        let pixels = Self.pixels(cgImage)
        let transparent = stride(from: 3, to: pixels.count, by: 4).filter { pixels[$0] == 0 }.count
        XCTAssertGreaterThan(transparent, cgImage.width * cgImage.height / 100)
        let attachment = XCTAttachment(image: image)
        attachment.name = "Apple-Vision-coffee-cutout"
        attachment.lifetime = .keepAlways
        add(attachment)
        print("VISION_COFFEE subjects=\(result.subjectCount) seconds=\(result.processingTime) bytes=\(result.pngData.count)")
    }

    private static func foreground() -> CGImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100), format: format).image { context in
            UIColor.red.setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 20, y: 20, width: 60, height: 60))
        }.cgImage!
    }

    private static func pixels(_ image: CGImage) -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        pixels.withUnsafeMutableBytes { bytes in
            let context = CGContext(data: bytes.baseAddress, width: image.width, height: image.height,
                                    bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return pixels
    }
}
