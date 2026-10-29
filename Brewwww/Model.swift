import Foundation
import SwiftUI
import UIKit
import CoreLocation

struct DrinkRecord: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var date: Date = Date()
    var shop: String = ""
    var city: String = ""
    var shopAddress: String? = nil
    var name: String = ""
    var note: String = ""
    var favorite: Bool = false
    var photoFile: String? = nil
    var stickerFile: String? = nil
    var latitude: Double? = nil
    var longitude: Double? = nil
}

@MainActor
final class BrewStore: ObservableObject {
    @Published var records: [DrinkRecord] = [] {
        didSet { save() }
    }
    @Published var customShops: [String: String] = [:] {
        didSet { save() }
    }

    @Published var savedShopPlaces: [ShopPlace] = [] {
        didSet { save() }
    }
    @Published private(set) var wishlistPlaces: [ShopPlace] = []

    @Published var allStampsUnlocked = false {
        didSet { save() }
    }

    private let folder: URL
    private let dataFile: URL
    private let imageCache = NSCache<NSString, UIImage>()
    private var loading = true

    private struct Snapshot: Codable {
        var records: [DrinkRecord]
        var customShops: [String: String]
        var savedShopPlaces: [ShopPlace]? = nil
        var wishlistPlaces: [ShopPlace]? = nil
        var allStampsUnlocked: Bool? = nil
    }

    init(directory: URL? = nil) {
        var directoryName = "Brewwww"
        #if DEBUG
        let uiTesting = ProcessInfo.processInfo.arguments.contains("--ui-testing")
        if uiTesting { directoryName = "BrewwwwUITesting" }
        #endif
        if UserDefaults.standard.object(forKey: "joinedAt") == nil {
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "joinedAt")
        }
        folder = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(directoryName, isDirectory: true)
        imageCache.totalCostLimit = 40 * 1024 * 1024
        dataFile = folder.appendingPathComponent("records.json")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: dataFile),
           let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) {
            allStampsUnlocked = snapshot.allStampsUnlocked ?? false
            records = snapshot.records
            customShops = snapshot.customShops
            savedShopPlaces = snapshot.savedShopPlaces ?? []
            wishlistPlaces = snapshot.wishlistPlaces ?? []
        }
        loading = false
        #if DEBUG
        if uiTesting {
            allStampsUnlocked = false
            wishlistPlaces = []
            UserDefaults.standard.set("right", forKey: "handedness")
            let appearance = ProcessInfo.processInfo.arguments.first { $0.hasPrefix("--appearance=") }?
                .split(separator: "=").last.map(String.init) ?? BrewAppearance.dark.rawValue
            UserDefaults.standard.set(appearance, forKey: "appearanceMode")
            records = [DrinkRecord(shop: "MIND BALANCE", city: "上海市", name: "古罗马美式",
                                   latitude: 31.2304, longitude: 121.4737)]
        }
        #endif
    }

    private func save() {
        guard !loading else { return }
        try? persist(records)
    }

    private func persist(_ updatedRecords: [DrinkRecord], wishes: [ShopPlace]? = nil) throws {
        let snapshot = Snapshot(records: updatedRecords, customShops: customShops,
                                savedShopPlaces: savedShopPlaces, wishlistPlaces: wishes ?? wishlistPlaces,
                                allStampsUnlocked: allStampsUnlocked)
        try JSONEncoder().encode(snapshot).write(to: dataFile, options: .atomic)
    }

    private func commit(_ updatedRecords: [DrinkRecord]) throws {
        try persist(updatedRecords)
        loading = true
        records = updatedRecords
        loading = false
    }

    func add(_ record: DrinkRecord, photo: UIImage?, stickerData: Data? = nil) throws {
        let updated = try preparingMedia(for: record, photo: photo, stickerData: stickerData)
        do {
            try commit(records + [updated])
        } catch {
            removeMedia(of: updated, keeping: record)
            throw error
        }
        geocode(recordID: updated.id)
    }

    func update(_ record: DrinkRecord, photo: UIImage? = nil, stickerData: Data? = nil) throws {
        guard let index = records.firstIndex(where: { $0.id == record.id }) else { return }
        let old = records[index]
        let updated = try preparingMedia(for: record, photo: photo, stickerData: stickerData)
        var next = records
        next[index] = updated
        do {
            try commit(next)
        } catch {
            removeMedia(of: updated, keeping: old)
            throw error
        }
        removeMedia(of: old, keeping: updated)
        geocode(recordID: updated.id)
    }

    private func preparingMedia(for record: DrinkRecord, photo: UIImage?, stickerData: Data?) throws -> DrinkRecord {
        var updated = record
        var created: [String] = []
        do {
            if let photo {
                guard let data = photo.jpegData(compressionQuality: 0.88) else {
                    throw SubjectCutoutError.invalidImage
                }
                let name = "\(record.id.uuidString)-\(UUID().uuidString).jpg"
                try data.write(to: folder.appendingPathComponent(name), options: .atomic)
                created.append(name)
                updated.photoFile = name
                updated.stickerFile = nil
            }
            if let stickerData {
                let name = "\(record.id.uuidString)-\(UUID().uuidString)-sticker.png"
                try stickerData.write(to: folder.appendingPathComponent(name), options: .atomic)
                created.append(name)
                updated.stickerFile = name
            }
            return updated
        } catch {
            for filename in created { try? FileManager.default.removeItem(at: folder.appendingPathComponent(filename)) }
            throw error
        }
    }

    private func removeMedia(of record: DrinkRecord, keeping other: DrinkRecord? = nil) {
        let retained = Set([other?.photoFile, other?.stickerFile].compactMap { $0 })
        for name in [record.photoFile, record.stickerFile].compactMap({ $0 }) where !retained.contains(name) {
            imageCache.removeObject(forKey: name as NSString)
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
        }
    }

    func delete(_ record: DrinkRecord) {
        removeMedia(of: record)
        records.removeAll { $0.id == record.id }
    }

    func deleteAll() {
        for record in records {
            removeMedia(of: record)
        }
        records = []
        customShops = [:]
        savedShopPlaces = []
        wishlistPlaces = []
        save()
    }

    func addWish(_ place: ShopPlace) throws {
        guard place.coordinate != nil, !place.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MapWishError.missingLocation
        }
        guard !wishlistPlaces.contains(where: { $0.isSameBranch(as: place) }) else { return }
        let next = wishlistPlaces + [place]
        try persist(records, wishes: next)
        wishlistPlaces = next
    }

    func removeWish(_ place: ShopPlace) throws {
        let next = wishlistPlaces.filter { !$0.isSameBranch(as: place) }
        try persist(records, wishes: next)
        wishlistPlaces = next
    }

    func image(for record: DrinkRecord) -> UIImage? {
        cachedImage(named: record.photoFile)
    }

    func sticker(for record: DrinkRecord) -> UIImage? {
        cachedImage(named: record.stickerFile)
    }

    private func cachedImage(named filename: String?) -> UIImage? {
        guard let filename else { return nil }
        if let cached = imageCache.object(forKey: filename as NSString) { return cached }
        guard let image = UIImage(contentsOfFile: folder.appendingPathComponent(filename).path) else { return nil }
        let cost = (image.cgImage?.bytesPerRow ?? 0) * (image.cgImage?.height ?? 0)
        imageCache.setObject(image, forKey: filename as NSString, cost: cost)
        return image
    }

    private func geocode(recordID: UUID) {
        guard let record = records.first(where: { $0.id == recordID }),
              !record.city.isEmpty, record.latitude == nil else { return }
        let query = [record.city, record.shop].filter { !$0.isEmpty }.joined(separator: " ")
        CLGeocoder().geocodeAddressString(query) { [weak self] placemarks, _ in
            if let coordinate = placemarks?.first?.location?.coordinate {
                Task { @MainActor in self?.setCoordinate(coordinate, for: recordID, shop: record.shop, city: record.city) }
            } else {
                CLGeocoder().geocodeAddressString(record.city) { [weak self] cityMarks, _ in
                    guard let coordinate = cityMarks?.first?.location?.coordinate else { return }
                    Task { @MainActor in self?.setCoordinate(coordinate, for: recordID, shop: record.shop, city: record.city) }
                }
            }
        }
    }

    private func setCoordinate(_ coordinate: CLLocationCoordinate2D, for id: UUID, shop: String, city: String) {
        guard let index = records.firstIndex(where: { $0.id == id }),
              records[index].shop == shop, records[index].city == city,
              records[index].latitude == nil, records[index].longitude == nil else { return }
        records[index].latitude = coordinate.latitude
        records[index].longitude = coordinate.longitude
    }

    func records(in month: Date) -> [DrinkRecord] {
        records.filter { Calendar.current.isDate($0.date, equalTo: month, toGranularity: .month) }
            .sorted { $0.date > $1.date }
    }

    var unlockedCaffeStamps: [CaffeTogetherStamp] {
        CaffeStampSeries.allCases.flatMap { series in
            CaffeTogetherStamp.unlocked(drinkCount: stampProgress(for: series), series: series)
        }
    }

    var independentCoffeeCount: Int { records.filter(CoffeeChainPolicy.qualifies).count }

    func stampProgress(for series: CaffeStampSeries) -> Int {
        if allStampsUnlocked { return series.stamps.map(\.requiredCount).max() ?? 0 }
        return series == .together ? records.count : independentCoffeeCount
    }

    var stampCount: Int { shops.count + unlockedCaffeStamps.count }

    var shops: [String] {
        Array(Set(records.map(\.shop).filter { !$0.isEmpty })).sorted()
    }

    /// Use the drink's date, not insertion order: backfilled visits must not
    /// replace the latest coffee on a shop stamp. Later entries win date ties.
    func latestDrink(atShop shop: String) -> DrinkRecord? {
        guard !shop.isEmpty else { return nil }
        var latest: DrinkRecord?
        for record in records where record.shop == shop {
            if let current = latest, current.date > record.date { continue }
            latest = record
        }
        return latest
    }

    var recentShopPlaces: [ShopPlace] {
        var seen = Set<String>()
        return records.sorted { $0.date > $1.date }.filter { !$0.shop.isEmpty }
            .map(\.shopPlace).filter { seen.insert($0.id).inserted }
    }

    var myShopPlaces: [ShopPlace] {
        savedShopPlaces + customShops.sorted { $0.key < $1.key }.compactMap { name, city in
            guard !savedShopPlaces.contains(where: { $0.name == name && $0.city == city }) else { return nil }
            return ShopPlace(name: name, city: city)
        }
    }

    func saveShop(_ place: ShopPlace) {
        guard !savedShopPlaces.contains(where: { $0.id == place.id }) else { return }
        savedShopPlaces.append(place)
    }

    var knownShops: [String] {
        Array(Set(shops + customShops.keys + savedShopPlaces.map(\.name))).sorted()
    }

    var cities: [String] {
        Array(Set(records.map(\.city).filter { !$0.isEmpty })).sorted()
    }

    var recentNames: [String] {
        Array(NSOrderedSet(array: records.sorted { $0.date > $1.date }.map(\.name).filter { !$0.isEmpty })) as? [String] ?? []
    }
}

extension Date {
    var monthTitle: String { BrewDateFormat.month.string(from: self) }
    var shortDate: String { BrewDateFormat.day.string(from: self) }
    var timeText: String { BrewDateFormat.time.string(from: self) }
    var journalHeading: String { BrewDateFormat.heading.string(from: self) }
    var recordDateTime: String { BrewDateFormat.record.string(from: self) }
}

private enum BrewDateFormat {
    static let month = make("yyyy年M月")
    static let day = make("M月d日")
    static let time = make("HH:mm")
    static let heading = make("yyyy年M月d日, EEE")
    static let record = make("yyyy年M月d日 HH:mm")
    private static func make(_ pattern: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = pattern
        return formatter
    }
}
