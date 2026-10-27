import XCTest
@testable import Brewwww

@MainActor final class ShopStampTests: XCTestCase {
    func testLatestCoffeeUsesVisitDateRatherThanInsertionOrder() throws {
        try withStore { store in
            let old = drink("以前的美式", at: 10)
            let latest = drink("最近的拿铁", at: 30)
            let backfill = drink("刚补录的旧咖啡", at: 20)
            store.records = [old, latest, backfill, drink("另一家店的咖啡", shop: "其他店", at: 100)]
            XCTAssertEqual(store.latestDrink(atShop: "测试店")?.id, latest.id)
            XCTAssertNil(store.latestDrink(atShop: "没有记录的店"))
        }
    }

    func testDeletingLatestVisitShowsPreviousCoffee() throws {
        try withStore { store in
            let previous = drink("上一杯", at: 10)
            let latest = drink("最新一杯", at: 20)
            store.records = [previous, latest]
            store.delete(latest)
            XCTAssertEqual(store.latestDrink(atShop: "测试店")?.id, previous.id)
            store.delete(previous)
            XCTAssertNil(store.latestDrink(atShop: "测试店"))
        }
    }

    func testEditingDrinkDateUpdatesRepresentativeCoffee() throws {
        try withStore { store in
            var first = drink("美式", at: 10)
            let second = drink("拿铁", at: 20)
            store.records = [first, second]
            first.date = Date(timeIntervalSince1970: 30)
            try store.update(first)
            XCTAssertEqual(store.latestDrink(atShop: "测试店")?.id, first.id)
            first.date = Date(timeIntervalSince1970: 5)
            try store.update(first)
            XCTAssertEqual(store.latestDrink(atShop: "测试店")?.id, second.id)
        }
    }

    func testMissingPhotoOnLatestVisitDoesNotReuseAnOlderCoffee() throws {
        try withStore { store in
            var photographed = drink("以前拍过的咖啡", at: 10)
            photographed.photoFile = "old.jpg"
            photographed.stickerFile = "old-sticker.png"
            let latest = drink("最近没拍照的咖啡", at: 20)
            store.records = [photographed, latest]
            let representative = store.latestDrink(atShop: "测试店")
            XCTAssertEqual(representative?.id, latest.id)
            XCTAssertNil(representative?.photoFile)
            XCTAssertNil(representative?.stickerFile)
        }
    }

    func testLaterEntryWinsWhenVisitTimesAreIdentical() throws {
        try withStore { store in
            let first = drink("同一时刻的第一条", at: 20)
            let last = drink("同一时刻的后一条", at: 20)
            store.records = [first, last]
            XCTAssertEqual(store.latestDrink(atShop: "测试店")?.id, last.id)
        }
    }

    private func drink(_ name: String, shop: String = "测试店", at time: TimeInterval) -> DrinkRecord {
        DrinkRecord(date: Date(timeIntervalSince1970: time), shop: shop, name: name)
    }

    private func withStore(_ body: (BrewStore) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(BrewStore(directory: directory))
    }
}
