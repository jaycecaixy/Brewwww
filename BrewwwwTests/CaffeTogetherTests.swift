import XCTest
import UIKit
@testable import Brewwww

@MainActor final class CaffeTogetherTests: XCTestCase {
    func testHiddenUnlockPersistsAndRestoresRealProgressInEverySeries() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = BrewStore(directory: folder)
        store.records = (0..<6).map { _ in DrinkRecord(shop: "巷子咖啡", name: "拿铁") }
        let earned = store.unlockedCaffeStamps
        let records = store.records
        store.allStampsUnlocked = true
        XCTAssertEqual(Set(store.unlockedCaffeStamps), Set(CaffeTogetherStamp.allCases))
        for series in CaffeStampSeries.allCases {
            XCTAssertTrue(series.stamps.allSatisfy { $0.isUnlocked(drinkCount: store.stampProgress(for: series)) })
        }
        let reloaded = BrewStore(directory: folder)
        XCTAssertTrue(reloaded.allStampsUnlocked)
        XCTAssertEqual(reloaded.unlockedCaffeStamps.count, CaffeTogetherStamp.allCases.count)
        reloaded.allStampsUnlocked = false
        XCTAssertEqual(reloaded.unlockedCaffeStamps, earned)
        XCTAssertEqual(reloaded.records, records)
        XCTAssertFalse(BrewStore(directory: folder).allStampsUnlocked)
    }

    func testMugTenTapsToggleAndHoldCanDrainOrLatchFull() async throws {
        let mug = PlayfulMugState()
        for _ in 0..<2 {
            for _ in 0..<9 { XCTAssertFalse(mug.tap()) }
            XCTAssertTrue(mug.tap())
        }
        XCTAssertFalse(mug.tap())
        try await Task.sleep(for: .milliseconds(850))
        for _ in 0..<9 { XCTAssertFalse(mug.tap()) }
        XCTAssertTrue(mug.tap())
        mug.setPressed(true)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(mug.fill, 0)
        mug.setPressed(false)
        XCTAssertFalse(mug.consumedHold)
        mug.setPressed(true)
        try await Task.sleep(for: .milliseconds(850))
        XCTAssertTrue(mug.charging)
        XCTAssertGreaterThan(mug.fill, 0)
        XCTAssertLessThan(mug.fill, 1)
        mug.setPressed(false)
        XCTAssertEqual(mug.burst, 0)
        try await Task.sleep(for: .milliseconds(750))
        XCTAssertEqual(mug.fill, 0)
        mug.setPressed(true)
        try await Task.sleep(for: .milliseconds(1900))
        XCTAssertEqual(mug.fill, 1)
        XCTAssertEqual(mug.burst, 1) // Celebration starts while the finger is still down.
        mug.setPressed(false)
        try await Task.sleep(for: .milliseconds(750))
        XCTAssertEqual(mug.fill, 1)
        XCTAssertEqual(mug.burst, 1)
        mug.cancel()
    }

    func testPartialMugResumesImmediatelyAndFullMugRestoresAddAction() async throws {
        let mug = PlayfulMugState()
        mug.setPressed(true)
        try await Task.sleep(for: .milliseconds(900))
        mug.setPressed(false)
        let partial = mug.fill
        XCTAssertGreaterThan(partial, 0.3)
        XCTAssertLessThan(partial, 0.6)

        if #available(iOS 26.0, *) {
            var sourceMenuOpens = 0
            let button = NativeAddRecordButton.Coordinator(action: { sourceMenuOpens += 1 }) { pressing in
                mug.setPressed(pressing)
                return mug.consumedHold
            }
            button.began()
            XCTAssertTrue(mug.charging) // Immediate, before the next task or run-loop turn.
            XCTAssertTrue(mug.consumedHold)
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertGreaterThan(mug.fill, partial)
            button.pressed()
            XCTAssertEqual(sourceMenuOpens, 0) // Even a short tap belongs to the liquid.

            button.began()
            try await Task.sleep(for: .milliseconds(1050))
            XCTAssertEqual(mug.fill, 1)
            button.pressed()
            XCTAssertEqual(sourceMenuOpens, 0) // Finishing this press still belongs to the liquid.
            button.began()
            XCTAssertFalse(mug.consumedHold)
            button.pressed()
            XCTAssertEqual(sourceMenuOpens, 1)
            button.began()
            try await Task.sleep(for: .milliseconds(350))
            button.pressed()
            XCTAssertEqual(sourceMenuOpens, 2) // A full cup restores long presses as well.
            XCTAssertEqual(mug.burst, 1)
        }
        mug.cancel()
    }

    func testPourHapticsRunContinuouslyOnlyWhileLiquidRises() async throws {
        let previous = UserDefaults.standard.object(forKey: "haptics")
        UserDefaults.standard.set(true, forKey: "haptics")
        defer { UserDefaults.standard.set(previous, forKey: "haptics") }
        let feedback = PourHapticSpy()
        let mug = PlayfulMugState(risingFeedback: feedback)
        defer { mug.cancel() }
        mug.setPressed(true)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertFalse(feedback.playing)
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertTrue(feedback.playing)
        XCTAssertEqual(feedback.durations.count, 1)
        XCTAssertEqual(try XCTUnwrap(feedback.durations.first), 1.5, accuracy: 0.01)
        mug.setPressed(false)
        XCTAssertFalse(feedback.playing)
        mug.setPressed(true)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(feedback.playing)
        XCTAssertEqual(feedback.durations.count, 2)
        XCTAssertLessThan(try XCTUnwrap(feedback.durations.last), 1.5)
        try await Task.sleep(for: .milliseconds(1400))
        XCTAssertEqual(mug.fill, 1)
        XCTAssertFalse(feedback.playing) // Stops at full even while the finger stays down.
        mug.setPressed(false)
        mug.setPressed(true)
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertFalse(feedback.playing)
        XCTAssertEqual(feedback.durations.count, 2)
    }

    func testCancellingPourStopsHapticsAndDisabledPreferenceSkipsPlayback() async throws {
        let previous = UserDefaults.standard.object(forKey: "haptics")
        defer { UserDefaults.standard.set(previous, forKey: "haptics") }
        let feedback = PourHapticSpy()
        let mug = PlayfulMugState(risingFeedback: feedback)
        defer { mug.cancel() }
        UserDefaults.standard.set(true, forKey: "haptics")
        mug.setPressed(true)
        try await Task.sleep(for: .milliseconds(450))
        XCTAssertTrue(feedback.playing)
        mug.cancel()
        XCTAssertFalse(feedback.playing)
        UserDefaults.standard.set(false, forKey: "haptics")
        mug.setPressed(true)
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertTrue(mug.charging)
        XCTAssertFalse(feedback.playing)
        XCTAssertEqual(feedback.durations.count, 1)
    }

    func testEveryMilestoneBoundaryInBothCollections() {
        for series in CaffeStampSeries.allCases {
            XCTAssertEqual(series.stamps.count, series == .together ? 20 : 8)
            XCTAssertTrue(CaffeTogetherStamp.unlocked(drinkCount: 0, series: series).isEmpty)
            for (index, stamp) in series.stamps.enumerated() {
                XCTAssertEqual(stamp.requiredCount, (index + 1) * series.interval)
                XCTAssertEqual(CaffeTogetherStamp.unlocked(drinkCount: stamp.requiredCount - 1, series: series).count, index)
                XCTAssertEqual(CaffeTogetherStamp.unlocked(drinkCount: stamp.requiredCount, series: series).count, index + 1)
                XCTAssertEqual(stamp.progress(drinkCount: -1), 0)
                XCTAssertEqual(stamp.remaining(drinkCount: -1), stamp.requiredCount)
                XCTAssertEqual(stamp.progress(drinkCount: 10000), 1)
                XCTAssertEqual(stamp.remaining(drinkCount: 10000), 0)
            }
        }
        XCTAssertEqual(Set(CaffeTogetherStamp.allCases.map(\.assetName)).count, 28)
    }

    func testChainMatchingNormalizesAliasesAndBranchNames() {
        for shop in ["瑞幸咖啡（上海店）", "瑞兴", "LUCKIN Coffee", "库迪", "COTTI COFFEE", "星巴克臻选", "Starbucks Reserve", "幸运咖", "Lucky Cup", "ＭＡＮＮＥＲ Coffee", "沪咖", "NOWWA 挪瓦", "K COFFEE 肯悦", "Tims 天好", "Tim Hortons", "M Stand（静安店）", "m-stand"] {
            XCTAssertTrue(CoffeeChainPolicy.isChain(shop: shop), shop)
            XCTAssertFalse(CoffeeChainPolicy.qualifies(DrinkRecord(shop: shop, name: "拿铁")), shop)
        }
        XCTAssertEqual(CoffeeChainPolicy.brandAliases.count, 10)
        for shop in ["MIND BALANCE", "巷子咖啡", "山间咖啡工作室"] {
            XCTAssertFalse(CoffeeChainPolicy.isChain(shop: shop), shop)
        }
        XCTAssertFalse(CoffeeChainPolicy.qualifies(DrinkRecord(shop: " ", name: "美式")))
        XCTAssertFalse(CoffeeChainPolicy.qualifies(DrinkRecord(shop: "巷子咖啡", name: "抹茶拿铁")))
        XCTAssertFalse(CoffeeChainPolicy.qualifies(DrinkRecord(shop: "巷子咖啡", name: "果汁")))
        XCTAssertTrue(CoffeeChainPolicy.qualifies(DrinkRecord(shop: "巷子咖啡", name: "燕麦拿铁")))
    }

    func testHistoricalRecordsEditingDeletionAndReloadUpdateBothCollections() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = BrewStore(directory: folder)
        store.records = (0..<10).map { _ in DrinkRecord(date: Date(timeIntervalSince1970: 0), shop: "巷子咖啡", name: "咖啡") }
        XCTAssertEqual(store.independentCoffeeCount, 10)
        XCTAssertEqual(store.unlockedCaffeStamps.count, 5) // two cups and three tools
        XCTAssertEqual(store.stampCount, 6) // one shop
        var record = try XCTUnwrap(store.records.last)
        record.shop = "M Stand"
        try store.update(record)
        XCTAssertEqual(store.independentCoffeeCount, 9)
        store.delete(try XCTUnwrap(store.records.first))
        XCTAssertEqual(store.independentCoffeeCount, 8)
        XCTAssertEqual(store.unlockedCaffeStamps.count, 3)
        let reloaded = BrewStore(directory: folder)
        XCTAssertEqual(reloaded.unlockedCaffeStamps, store.unlockedCaffeStamps)
        store.records = []
        XCTAssertEqual(store.stampCount, 0)
    }

    func testAllArtworkAssetsExistWithTransparentMargins() throws {
        for stamp in CaffeTogetherStamp.allCases {
            let image = try XCTUnwrap(UIImage(named: stamp.assetName), stamp.assetName)
            XCTAssertGreaterThanOrEqual(image.size.width, 140)
            let source = try XCTUnwrap(image.cgImage)
            var pixels = [UInt8](repeating: 0, count: 4 * 4 * 4)
            let context = try XCTUnwrap(CGContext(data: &pixels, width: 4, height: 4, bitsPerComponent: 8,
                                                 bytesPerRow: 16, space: CGColorSpaceCreateDeviceRGB(),
                                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(source, in: CGRect(x: 0, y: 0, width: 4, height: 4))
            XCTAssertLessThan(pixels[3], 30, stamp.assetName)
        }
    }
}

@MainActor private final class PourHapticSpy: BrewContinuousHaptics {
    private(set) var playing = false
    private(set) var durations: [TimeInterval] = []
    func prepare() {}
    func startContinuous(duration: TimeInterval) {
        durations.append(duration)
        playing = true
    }
    func stopContinuous() { playing = false }
}
