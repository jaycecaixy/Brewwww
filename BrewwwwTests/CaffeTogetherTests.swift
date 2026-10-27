import XCTest
import UIKit
@testable import Brewwww

@MainActor final class CaffeTogetherTests: XCTestCase {
    func testThresholdBoundariesUnlockExactlyTheExpectedStamps() {
        let cases: [(Int, [CaffeTogetherStamp])] = [
            (0, []), (1, [.firstSip]), (9, [.firstSip]),
            (10, [.firstSip, .sameTable]), (19, [.firstSip, .sameTable]),
            (20, [.firstSip, .sameTable, .slowRitual]), (39, [.firstSip, .sameTable, .slowRitual]),
            (40, CaffeTogetherStamp.allCases), (1000, CaffeTogetherStamp.allCases)
        ]
        for (count, expected) in cases {
            XCTAssertEqual(CaffeTogetherStamp.unlocked(drinkCount: count), expected, "\(count) 杯")
        }
        XCTAssertEqual(Set(CaffeTogetherStamp.allCases.map(\.id)).count, 4)
    }

    func testProgressAndRemainingAreClamped() {
        for stamp in CaffeTogetherStamp.allCases {
            XCTAssertEqual(stamp.progress(drinkCount: -1), 0)
            XCTAssertEqual(stamp.remaining(drinkCount: -1), stamp.requiredCount)
            XCTAssertEqual(stamp.progress(drinkCount: stamp.requiredCount), 1)
            XCTAssertEqual(stamp.remaining(drinkCount: 10000), 0)
        }
        XCTAssertEqual(CaffeTogetherStamp.sameTable.progress(drinkCount: 4), 0.4)
        XCTAssertEqual(CaffeTogetherStamp.sameTable.remaining(drinkCount: 4), 6)
    }

    func testExistingHistoricalRecordsCountWithoutACampaignDateWindow() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = BrewStore(directory: folder)
        store.records = (0..<20).map { index in
            DrinkRecord(date: Date(timeIntervalSince1970: Double(index) * 86400), shop: "已有店铺", name: "已有咖啡")
        }
        XCTAssertEqual(store.unlockedCaffeStamps, [.firstSip, .sameTable, .slowRitual])
        XCTAssertEqual(store.stampCount, 4)
        let reloaded = BrewStore(directory: folder)
        XCTAssertEqual(reloaded.unlockedCaffeStamps, store.unlockedCaffeStamps)
        XCTAssertEqual(reloaded.stampCount, store.stampCount)
    }

    func testSharedStampCountTracksCollectionAndRecordDeletion() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = BrewStore(directory: folder)
        store.records = (0..<10).map { _ in DrinkRecord(shop: "A店", name: "咖啡") }
        XCTAssertEqual(store.stampCount, 3) // one shop, two collected system stamps
        store.delete(try XCTUnwrap(store.records.last))
        XCTAssertEqual(store.unlockedCaffeStamps, [.firstSip])
        XCTAssertEqual(store.stampCount, 2)
        store.records = []
        XCTAssertEqual(store.stampCount, 0)
    }

    func testAllFourArtworkAssetsExistAndRetainTransparency() throws {
        for stamp in CaffeTogetherStamp.allCases {
            let image = try XCTUnwrap(UIImage(named: stamp.assetName), stamp.assetName)
            let source = try XCTUnwrap(image.cgImage)
            XCTAssertGreaterThanOrEqual(source.width, 512)
            var pixels = [UInt8](repeating: 0, count: 4 * 4 * 4)
            let context = try XCTUnwrap(CGContext(data: &pixels, width: 4, height: 4, bitsPerComponent: 8,
                                                 bytesPerRow: 16, space: CGColorSpaceCreateDeviceRGB(),
                                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(source, in: CGRect(x: 0, y: 0, width: 4, height: 4))
            XCTAssertLessThan(pixels[3], 30, "插画外侧应透明：\(stamp.assetName)")
        }
    }
}
