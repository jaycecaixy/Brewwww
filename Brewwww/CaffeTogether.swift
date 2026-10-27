import Foundation

/// A permanent system collection. All saved drink records count, including
/// records created before this collection was added; there is no date window.
enum CaffeTogetherStamp: String, CaseIterable, Identifiable {
    case firstSip, sameTable, slowRitual, alwaysTogether

    var id: String { rawValue }
    var requiredCount: Int {
        switch self {
        case .firstSip: 1
        case .sameTable: 10
        case .slowRitual: 20
        case .alwaysTogether: 40
        }
    }
    var title: String {
        switch self {
        case .firstSip: "初次碰杯"
        case .sameTable: "老地方见"
        case .slowRitual: "慢慢冲煮"
        case .alwaysTogether: "总有一席"
        }
    }
    var caption: String {
        switch self {
        case .firstSip: "FIRST SIP"
        case .sameTable: "SAME TABLE"
        case .slowRitual: "SLOW RITUAL"
        case .alwaysTogether: "ALWAYS TOGETHER"
        }
    }
    var story: String {
        switch self {
        case .firstSip: "从这一杯开始，把相聚的片刻收进口袋。"
        case .sameTable: "第十杯，熟悉的香气，也有了熟悉的位置。"
        case .slowRitual: "冲煮慢一点，让二十次日常都有余味。"
        case .alwaysTogether: "四十杯之后，咖啡桌旁总有属于你的一席。"
        }
    }
    var assetName: String { "CaffeTogether_" + rawValue }
    func isUnlocked(drinkCount: Int) -> Bool { drinkCount >= requiredCount }
    func remaining(drinkCount: Int) -> Int { max(0, requiredCount - max(0, drinkCount)) }
    func progress(drinkCount: Int) -> Double { min(1, Double(max(0, drinkCount)) / Double(requiredCount)) }
    static func unlocked(drinkCount: Int) -> [Self] { allCases.filter { $0.isUnlocked(drinkCount: drinkCount) } }
}

enum StampRoute { case collection, catalogue, caffeTogether }
