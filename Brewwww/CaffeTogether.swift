import Foundation

/// Permanent collections, calculated from saved records so edits and deletions stay in sync.
enum CaffeStampSeries: String, CaseIterable, Identifiable {
    case together, explore
    var id: String { rawValue }
    var title: String { self == .together ? "Caffe Together" : "Caffe Explore" }
    var subtitle: String { self == .together ? "一杯杯，收藏日常。" : "一间间，探索咖啡的可能。" }
    var rule: String { self == .together ? "每记录 5 杯，解锁一枚杯子印章。" : "每记录 3 杯非连锁咖啡，解锁一枚器具印章。" }
    var interval: Int { self == .together ? 5 : 3 }
    var stamps: [CaffeTogetherStamp] { CaffeTogetherStamp.allCases.filter { $0.series == self } }
    var route: StampRoute { self == .together ? .caffeTogether : .caffeExplore }
}

// Kept as a single stamp type so collection, catalogue and detail share one source of truth.
enum CaffeTogetherStamp: String, CaseIterable, Identifiable {
    case ribbed, checker, espresso, floralSaucer, takeaway, tumbler, daisy, grid, doubleGlass, enamel
    case travel, cappuccino, thermos, botanical, wavy, straw, beaker, teaBowl, sports, garden
    case pourOver, moka, espressoMachine, handGrinder, electricGrinder, frenchPress, siphon, aeroPress

    var id: String { rawValue }
    var series: CaffeStampSeries { Self.allCases.firstIndex(of: self)! < 20 ? .together : .explore }
    var position: Int { Self.allCases.firstIndex(of: self)! % 20 + 1 }
    var requiredCount: Int { position * series.interval }
    var title: String {
        let names = ["竖纹马克杯", "棋盘格杯", "意式浓缩杯", "花边杯碟", "随行纸杯", "直筒随心杯", "雏菊马克杯", "方格马克杯", "双层玻璃杯", "复古搪瓷杯",
                     "城市随行杯", "卡布奇诺杯", "口袋保温杯", "枝叶陶杯", "波纹手捏杯", "吸管冰咖杯", "实验烧杯", "宽口陶碗杯", "户外运动杯", "花园大耳杯",
                     "手冲套装", "八角摩卡壶", "意式咖啡机", "手摇磨豆机", "电动磨豆机", "法式滤压壶", "虹吸咖啡壶", "爱乐压"]
        return names[Self.allCases.firstIndex(of: self)!]
    }
    var story: String { series == .together ? "把喜欢的杯子，留给值得慢下来的日常。" : "走进一间非连锁咖啡店，让好奇心带你认识另一种冲煮方式。" }
    var assetName: String { "Caffe\(series == .together ? "Together" : "Explore")_\(rawValue)" }
    func isUnlocked(drinkCount: Int) -> Bool { drinkCount >= requiredCount }
    func remaining(drinkCount: Int) -> Int { max(0, requiredCount - max(0, drinkCount)) }
    func progress(drinkCount: Int) -> Double { min(1, Double(max(0, drinkCount)) / Double(requiredCount)) }
    static func unlocked(drinkCount: Int, series: CaffeStampSeries = .together) -> [Self] {
        series.stamps.filter { $0.isUnlocked(drinkCount: drinkCount) }
    }
}

/// Internal exclusion list. UI intentionally only says “非连锁咖啡”.
/// Source: https://www.coffinance.com/detail/6676 (2025-04 mainland store-count top ten).
/// This is a fixed, documented list, not a claim to identify every chain in China.
enum CoffeeChainPolicy {
    static let brandAliases: [[String]] = [
        ["瑞幸", "瑞兴", "luckin"], ["库迪", "cotti"], ["星巴克", "starbucks"],
        ["幸运咖", "luckycup", "luckycupcoffee"], ["manner"], ["沪咖", "hcoffee"],
        ["挪瓦", "nowwa"], ["肯悦", "kcoffee"], ["天好", "tims", "timhortons"], ["mstand"]
    ]
    static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(String.init).joined()
    }
    static func isChain(shop: String) -> Bool {
        let name = normalized(shop)
        return brandAliases.joined().contains { name.contains($0) }
    }
    static func qualifies(_ record: DrinkRecord) -> Bool {
        // A named shop is required: an unspecified location cannot establish an independent cafe visit.
        // Drink records represent coffee by default; explicitly named non-coffee drinks are excluded.
        let shop = normalized(record.shop)
        let drink = normalized(record.name)
        guard !shop.isEmpty, !isChain(shop: record.shop), !drink.isEmpty else { return false }
        let nonCoffee = ["抹茶", "奶茶", "果茶", "红茶", "绿茶", "乌龙", "可可", "巧克力", "柠檬水", "气泡水", "果汁", "牛奶", "matcha", "chocolate", "cocoa", "milktea", "juice"]
        let coffee = ["咖啡", "美式", "拿铁", "浓缩", "澳白", "馥芮白", "卡布", "摩卡", "玛奇朵", "脏咖", "冷萃", "手冲", "冰滴", "阿芙佳朵", "dirty", "coffee", "espresso", "americano", "latte", "cappuccino", "flatwhite", "mocha", "macchiato", "coldbrew", "pourover", "affogato"]
        if nonCoffee.contains(where: { drink.contains($0) }) {
            return ["咖啡", "浓缩", "espresso", "coffee"].contains(where: { drink.contains($0) })
        }
        if coffee.contains(where: { drink.contains($0) }) { return true }
        return !nonCoffee.contains(where: { drink.contains($0) })
    }
}

enum StampRoute { case collection, catalogue, caffeTogether, caffeExplore }
