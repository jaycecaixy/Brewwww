import SwiftUI

struct CaffeStampArt: View {
    var stamp: CaffeTogetherStamp
    var unlocked = true
    var body: some View {
        GeometryReader { geometry in
            Image(stamp.assetName).resizable().interpolation(.high).scaledToFit()
                .frame(width: geometry.size.width, height: geometry.size.height)
                .saturation(unlocked ? 1 : 0)
                .opacity(unlocked ? 1 : 0.23)
        }
        .accessibilityHidden(true)
    }
}

struct StampCatalogue: View {
    @EnvironmentObject private var store: BrewStore
    @Environment(\.brewLayout) private var layout
    @Binding var route: StampRoute
    var showsTheme: Bool = false
    var series: CaffeStampSeries = .together
    @State private var selected: CaffeTogetherStamp?

    private func count(_ series: CaffeStampSeries) -> Int { store.stampProgress(for: series) }
    private func collected(_ series: CaffeStampSeries) -> Int {
        CaffeTogetherStamp.unlocked(drinkCount: count(series), series: series).count
    }
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: layout.expanded ? 16 : 6), count: 4)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                Text(showsTheme ? series.title : "印章图鉴")
                    .font(BrewFont.title).frame(maxWidth: .infinity)
                    .padding(.top, layout.bottomNavigation ? 76 : layout.titleTop)
                if showsTheme { theme(series) }
                else {
                    ForEach(CaffeStampSeries.allCases) { collection in catalogueCard(collection) }
                    Text("慢慢记录，收藏属于你的咖啡日常。")
                        .font(BrewFont.caption).foregroundStyle(BrewStyle.muted).padding(.horizontal, 6)
                }
            }
            .frame(maxWidth: 720).frame(maxWidth: .infinity)
            .padding(.bottom, layout.bottomNavigation && !layout.nativeNavigation ? 120 : 28)
        }
        .scrollIndicators(.hidden).brewPagePadding()
        .sheet(item: $selected) { stamp in detail(stamp) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(showsTheme ? "stamps.themePage" : "stamps.cataloguePage")
    }

    private func catalogueCard(_ collection: CaffeStampSeries) -> some View {
        BrewPanel {
            VStack(alignment: .leading, spacing: 21) {
                Button { withAnimation(layout.animation) { route = collection.route } } label: {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(collection.title).font(.system(size: 23, weight: .semibold, design: .serif))
                                .foregroundStyle(BrewStyle.text)
                            Text(collection.subtitle).font(BrewFont.caption).foregroundStyle(BrewStyle.muted)
                        }
                        Spacer(minLength: 4)
                        permanent
                        Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(BrewStyle.muted)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(collection.title)，永久，\(collected(collection))枚已收集，共\(collection.stamps.count)枚")
                .accessibilityIdentifier(collection == .together ? "stamps.openTheme" : "stamps.openExplore")
                stampGrid(collection, compact: true)
                VStack(alignment: .leading, spacing: 8) {
                    Text(collection.rule).font(BrewFont.caption).foregroundStyle(BrewStyle.muted)
                    HStack {
                        Text("\(collected(collection)) / \(collection.stamps.count) 枚已收集")
                        Spacer(minLength: 4)
                        Text("累计 \(count(collection)) 杯")
                    }.font(.system(size: 11, weight: .medium)).foregroundStyle(BrewStyle.gold)
                }
            }.padding(layout.expanded ? 26 : 18)
        }
    }

    private func theme(_ collection: CaffeStampSeries) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            BrewPanel {
                VStack(alignment: .leading, spacing: 14) {
                    HStack { Text(collection.subtitle).font(BrewFont.caption); Spacer(); permanent }
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text("\(collected(collection))").font(.system(size: 32, weight: .medium, design: .serif))
                        Text("/ \(collection.stamps.count) 枚已收集").font(BrewFont.caption).foregroundStyle(BrewStyle.muted)
                        Spacer()
                        Text("累计 \(count(collection)) 杯").font(BrewFont.caption).foregroundStyle(BrewStyle.gold)
                    }
                    ProgressView(value: Double(collected(collection)), total: Double(collection.stamps.count)).tint(BrewStyle.gold)
                        .accessibilityLabel("系列收集进度")
                    Text(collection.rule).font(BrewFont.caption).foregroundStyle(BrewStyle.muted)
                }.padding(20)
            }
            BrewPanel { stampGrid(collection, compact: false).padding(layout.expanded ? 24 : 14) }
            Text("系列永久开放，已有记录也会计入。")
                .font(BrewFont.caption).foregroundStyle(BrewStyle.muted).padding(.horizontal, 4)
        }
    }

    private func stampGrid(_ collection: CaffeStampSeries, compact: Bool) -> some View {
        LazyVGrid(columns: columns, spacing: compact ? 16 : 22) {
            ForEach(collection.stamps) { stamp in
                let unlocked = stamp.isUnlocked(drinkCount: count(collection))
                Button { selected = stamp } label: {
                    VStack(spacing: compact ? 3 : 6) {
                        CaffeStampArt(stamp: stamp, unlocked: unlocked)
                            .frame(height: layout.expanded ? (compact ? 100 : 120) : (compact ? 76 : 86))
                        if !compact {
                            Text(stamp.title).font(.system(size: 10, weight: .medium))
                                .foregroundStyle(unlocked ? BrewStyle.text : BrewStyle.muted)
                                .lineLimit(1).minimumScaleFactor(0.7)
                        }
                        Text("\(stamp.requiredCount)")
                            .font(.system(size: compact ? 15 : 16, weight: .medium, design: .rounded))
                            .foregroundStyle(BrewStyle.gold)
                    }.frame(maxWidth: .infinity).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(stamp.title)，累计\(stamp.requiredCount)杯\(collection == .explore ? "非连锁咖啡" : "")，\(unlocked ? "已收集" : "尚未解锁")")
                .accessibilityIdentifier("stamps.\(compact ? "preview" : "milestone").\(stamp.rawValue)")
            }
        }
    }

    private var permanent: some View {
        Text("永久").font(.system(size: 13, weight: .semibold)).foregroundStyle(BrewStyle.gold)
    }

    private func detail(_ stamp: CaffeTogetherStamp) -> some View {
        let progress = count(stamp.series)
        let unlocked = stamp.isUnlocked(drinkCount: progress)
        return VStack(spacing: 18) {
            Capsule().fill(BrewStyle.muted.opacity(0.5)).frame(width: 34, height: 4).padding(.top, 12)
            HStack {
                Text(stamp.series.title).font(.system(size: 16, weight: .medium, design: .serif))
                Spacer(); permanent
                Button { selected = nil } label: { Image(systemName: "xmark").padding(10) }
                    .accessibilityLabel("关闭印章详情").accessibilityIdentifier("stamps.closeDetail")
            }
            CaffeStampArt(stamp: stamp, unlocked: unlocked).frame(height: 200)
            Text(stamp.title).font(.system(size: 24, weight: .semibold))
            Text(stamp.story).font(.subheadline).foregroundStyle(BrewStyle.muted).multilineTextAlignment(.center)
            if unlocked {
                Label("已收集 · 累计 \(stamp.requiredCount) 杯\(stamp.series == .explore ? "非连锁咖啡" : "")", systemImage: "checkmark.seal.fill")
                    .font(.subheadline).foregroundStyle(BrewStyle.gold)
            } else {
                Text("再记录 \(stamp.remaining(drinkCount: progress)) 杯\(stamp.series == .explore ? "非连锁咖啡" : "")，即可收集这枚印章。")
                    .font(.subheadline).foregroundStyle(BrewStyle.gold)
                ProgressView(value: stamp.progress(drinkCount: progress)).tint(BrewStyle.gold)
            }
            Text(stamp.series.rule).font(BrewFont.caption).foregroundStyle(BrewStyle.muted)
            Spacer(minLength: 10)
        }
        .padding(.horizontal, 24).frame(maxWidth: .infinity)
        .foregroundStyle(BrewStyle.text).background { BrewBackground() }
        .presentationDetents([.height(560), .large]).presentationDragIndicator(.hidden)
        .accessibilityElement(children: .contain).accessibilityIdentifier("stamps.detail")
    }
}
