import SwiftUI
import MapKit

struct StampsPage: View {
    @EnvironmentObject private var store: BrewStore
    @Environment(\.brewLayout) private var layout
    @AppStorage("stampStyle") private var stampStyle = 1
    @Binding var route: StampRoute
    @Binding var filter: String?

    var body: some View {
        ZStack {
            collection
                .opacity(route == .collection ? 1 : 0)
                .allowsHitTesting(route == .collection)
                .accessibilityHidden(route != .collection)
            if route != .collection {
                StampCatalogue(route: $route, showsTheme: false)
                    .opacity(route == .catalogue ? 1 : 0)
                    .allowsHitTesting(route == .catalogue)
                    .accessibilityHidden(route != .catalogue)
                    .transition(layout.reduceMotion ? .opacity : .move(edge: .trailing))
                    .zIndex(1)
            }
            if route == .caffeTogether || route == .caffeExplore {
                StampCatalogue(route: $route, showsTheme: true, series: route == .caffeExplore ? .explore : .together)
                    .transition(layout.reduceMotion ? .opacity : .move(edge: .trailing))
                    .zIndex(2)
            }
        }
        .clipped()
        .animation(layout.animation, value: route)
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
                                Button { route = stamp.series.route } label: {
                                    VStack(spacing: 5) {
                                        CaffeStampArt(stamp: stamp).frame(width: 135, height: 135)
                                        Text(stamp.title).font(BrewFont.caption).foregroundStyle(BrewStyle.muted)
                                    }.frame(maxWidth: .infinity)
                                }
                                .accessibilityLabel("\(stamp.title)，\(stamp.series.title)，已收集")
                                .accessibilityIdentifier("stamps.collected.\(stamp.rawValue)")
                            }
                        }
                    }
                    .padding(.top, 25)
                    .padding(.bottom, layout.bottomNavigation && !layout.nativeNavigation ? 120 : 25)
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
