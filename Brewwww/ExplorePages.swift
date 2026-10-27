import SwiftUI
import MapKit

struct StampsPage: View {
    @EnvironmentObject private var store: BrewStore
    @Environment(\.brewLayout) private var layout
    @AppStorage("stampStyle") private var stampStyle = 1
    @Binding var route: StampRoute
    @Binding var filter: String?

    var body: some View {
        Group {
            if route == .collection { collection }
            else { StampCatalogue(route: $route) }
        }
    }

    private var collection: some View {
        VStack(spacing: 15) {
            Menu {
                Button("所有印章") { filter = nil }
                ForEach(store.cities, id: \.self) { city in
                    Button(city) { filter = city }
                }
            } label: {
                Label(filter ?? "所有印章", systemImage: "chevron.down")
                    .font(.title3.bold()).foregroundStyle(BrewStyle.text)
            }
            .padding(.top, layout.bottomNavigation ? 76 : layout.titleTop)
            Text("\(store.stampCount) 枚印章 · \(store.shops.count) 家店铺 · \(store.cities.count) 座城市")
                .font(.subheadline).foregroundStyle(BrewStyle.muted)
                .accessibilityIdentifier("stamps.collectionCount")
            if store.records.isEmpty {
                VStack {
                    EmptyPage(title: "印章册还是空的", symbol: "seal",
                              detail: "记录第一杯饮品，开始收集印章。")
                    Button("查看印章图鉴") { route = .catalogue }
                        .foregroundStyle(BrewStyle.gold).padding(.bottom, 40)
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140, maximum: 190), spacing: 20)], spacing: 28) {
                        ForEach(store.shops, id: \.self) { shop in
                            let record = store.records.first { $0.shop == shop && (filter == nil || $0.city == filter) }
                            if record != nil { shopStamp(shop, record: record) }
                        }
                        if filter == nil {
                            ForEach(store.unlockedCaffeStamps) { stamp in
                                Button { route = .caffeTogether } label: {
                                    VStack(spacing: 5) {
                                        CaffeStampArt(stamp: stamp).frame(width: 135, height: 135)
                                        Text(stamp.title).font(BrewFont.caption).foregroundStyle(BrewStyle.muted)
                                    }.frame(maxWidth: .infinity)
                                }
                                .accessibilityLabel("\(stamp.title)，caffe together，已收集")
                                .accessibilityIdentifier("stamps.collected.\(stamp.rawValue)")
                            }
                        }
                    }
                    .padding(.top, 25)
                    .padding(.bottom, layout.bottomNavigation ? 120 : 25)
                }
            }
        }
        .brewPagePadding()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("stamps.collection")
    }

    private func shopStamp(_ shop: String, record: DrinkRecord?) -> some View {
        let latestDrink = store.latestDrink(atShop: shop)
        return VStack(spacing: 5) {
            Text(shop.uppercased()).font(.system(size: 12, weight: .bold, design: .rounded)).lineLimit(1)
            DrinkSticker(image: latestDrink.flatMap { store.image(for: $0) },
                         cutout: latestDrink.flatMap { store.sticker(for: $0) }, size: 50)
                .accessibilityLabel(latestDrink.map { "最近一次饮品：\($0.name)" } ?? "暂无饮品")
            Text(record?.date.formatted(.dateTime.month().day().year()) ?? "")
                .font(.system(size: 9, weight: .bold, design: .rounded))
        }
        .foregroundStyle(stampStyle == 0 ? BrewStyle.gold : BrewStyle.orange)
        .frame(width: 125, height: 125)
        .overlay(Circle().stroke(stampStyle == 0 ? BrewStyle.gold : BrewStyle.orange, lineWidth: 3))
        .rotationEffect(.degrees(11))
    }
}

struct BrewMapPage: View {
    @EnvironmentObject private var store: BrewStore
    @Environment(\.brewLayout) private var layout
    @Binding var selectedShop: String?
    @State private var position: MapCameraPosition = .automatic
    @State private var cityFilter: String? = nil

    private var mappedRecords: [DrinkRecord] {
        store.records.filter { $0.latitude != nil && $0.longitude != nil &&
            (cityFilter == nil || $0.city == cityFilter) }
    }

    var body: some View {
        ZStack(alignment: .top) {
            Map(position: $position) {
                ForEach(mappedRecords) { record in
                    if let lat = record.latitude, let lon = record.longitude {
                        Annotation(record.shop, coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon)) {
                            Button { selectedShop = record.shop } label: {
                                Image(systemName: "cup.and.saucer.fill")
                                    .foregroundStyle(BrewStyle.text)
                                    .frame(width: 35, height: 35)
                                    .background(BrewStyle.mapPin, in: Circle())
                                    .overlay(Circle().stroke(.white, lineWidth: 2))
                            }
                        }
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat))
            .ignoresSafeArea()
            VStack {
                Text("\(store.cities.count) 座城市 · \(store.shops.count) 家店铺 · \(store.records.count) 次打卡")
                    .font(.subheadline).foregroundStyle(BrewStyle.text)
                    .padding(.top, 28)
                Spacer()
                if let selectedShop {
                    BrewPanel(mapSurface: true) {
                        HStack {
                            VStack(alignment: .leading, spacing: 7) {
                                Text(selectedShop).font(.headline)
                                Text("\(store.records.filter { $0.shop == selectedShop }.count) 次打卡")
                                    .foregroundStyle(BrewStyle.muted)
                                if let record = store.records.first(where: { $0.shop == selectedShop }) {
                                    DrinkSticker(image: store.image(for: record), cutout: store.sticker(for: record), size: 45)
                                }
                            }
                            Spacer()
                            Button { self.selectedShop = nil } label: { Image(systemName: "xmark.circle.fill") }
                        }
                        .padding(17)
                    }
                    .padding(.bottom, 20)
                }
            }
            .padding(.horizontal, 16)
            Menu {
                Button("全球") { cityFilter = nil; position = .automatic }
                ForEach(store.cities, id: \.self) { city in
                    Button(city) {
                        cityFilter = city
                        if let record = mappedRecords.first,
                           let lat = record.latitude, let lon = record.longitude {
                            position = .region(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                                                                  span: MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.12)))
                        }
                    }
                }
            } label: {
                RoundIcon(symbol: "line.3.horizontal")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(.top, 125)
            .padding(.trailing, 13)
            if mappedRecords.isEmpty {
                EmptyPage(title: "地图上还没有打卡", symbol: "map",
                          detail: "添加店铺和城市后，打卡地点会显示在这里。定位新店铺可能需要稍等片刻。")
                    .background(BrewStyle.ink.opacity(0.75))
            }
        }
    }
}
