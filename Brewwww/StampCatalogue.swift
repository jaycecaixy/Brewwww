import SwiftUI

struct CaffeStampArt: View {
    var stamp: CaffeTogetherStamp
    var unlocked = true
    var body: some View {
        Image(stamp.assetName).resizable().scaledToFit()
            .saturation(unlocked ? 1 : 0)
            .opacity(unlocked ? 1 : 0.23)
            .accessibilityHidden(true)
    }
}

struct StampCatalogue: View {
    @EnvironmentObject private var store: BrewStore
    @Environment(\.brewLayout) private var layout
    @Binding var route: StampRoute
    @State private var selected: CaffeTogetherStamp?
    private var count: Int { store.records.count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                Text(route == .catalogue ? "印章图鉴" : "caffe together")
                    .font(BrewFont.title).frame(maxWidth: .infinity)
                    .padding(.top, layout.bottomNavigation ? 76 : layout.titleTop)
                if route == .catalogue { catalogue }
                else { theme }
            }
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
            .padding(.bottom, layout.bottomNavigation ? 120 : 28)
        }
        .scrollIndicators(.hidden)
        .brewPagePadding()
        .sheet(item: $selected) { stamp in detail(stamp) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(route == .catalogue ? "stamps.cataloguePage" : "stamps.themePage")
    }

    private var catalogue: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("系统印章").font(BrewFont.caption).foregroundStyle(BrewStyle.muted)
            Button { withAnimation(layout.animation) { route = .caffeTogether } } label: {
                BrewPanel {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("caffe together").font(.system(size: 23, weight: .semibold, design: .serif))
                                Text("让每一杯，成为相聚的理由。")
                                    .font(BrewFont.caption).foregroundStyle(BrewStyle.muted)
                            }
                            Spacer(minLength: 5)
                            Image(systemName: "chevron.right").foregroundStyle(BrewStyle.icon).padding(.top, 5)
                        }
                        HStack(spacing: 8) {
                            ForEach(CaffeTogetherStamp.allCases) { stamp in
                                CaffeStampArt(stamp: stamp, unlocked: stamp.isUnlocked(drinkCount: count))
                                    .frame(maxWidth: .infinity).frame(height: layout.expanded ? 110 : 78)
                            }
                        }
                        HStack {
                            permanent
                            Spacer()
                            Text("\(store.unlockedCaffeStamps.count) / 4 枚已收集")
                                .font(BrewFont.caption).foregroundStyle(BrewStyle.muted)
                        }
                    }.padding(20)
                }
            }
            .accessibilityLabel("caffe together，永久，\(store.unlockedCaffeStamps.count)枚已收集，共4枚")
            .accessibilityIdentifier("stamps.openTheme")
            Text("记录饮品，慢慢收集属于你的咖啡日常。")
                .font(BrewFont.caption).foregroundStyle(BrewStyle.muted).padding(.horizontal, 4)
        }
    }

    private var theme: some View {
        VStack(alignment: .leading, spacing: 20) {
            BrewPanel {
                VStack(alignment: .leading, spacing: 17) {
                    HStack { Text("咖啡相聚系列").font(.system(size: 16, weight: .semibold)); Spacer(); permanent }
                    Text("把日常的一杯，变成可以珍藏的相聚。")
                        .font(BrewFont.caption).foregroundStyle(BrewStyle.muted)
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text("\(store.unlockedCaffeStamps.count)").font(.system(size: 32, weight: .medium, design: .serif))
                        Text("/ 4 枚已收集").font(BrewFont.caption).foregroundStyle(BrewStyle.muted)
                        Spacer()
                        Text("累计 \(count) 杯").font(BrewFont.caption).foregroundStyle(BrewStyle.gold)
                    }
                    ProgressView(value: Double(store.unlockedCaffeStamps.count), total: 4).tint(BrewStyle.gold)
                        .accessibilityLabel("系列收集进度")
                }.padding(20)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: layout.size.width > 850 ? 4 : 2), spacing: 18) {
                ForEach(CaffeTogetherStamp.allCases) { stamp in
                    Button { selected = stamp } label: { stampTile(stamp) }
                        .accessibilityLabel("\(stamp.title)，累计\(stamp.requiredCount)杯，\(stamp.isUnlocked(drinkCount: count) ? "已收集" : "尚未解锁")")
                        .accessibilityIdentifier("stamps.milestone.\(stamp.rawValue)")
                }
            }
            Text("累计记录 1 / 10 / 20 / 40 杯饮品，依次解锁四枚印章。系列永久开放，已有记录也会计入。")
                .font(BrewFont.caption).foregroundStyle(BrewStyle.muted).lineSpacing(5).padding(.horizontal, 4)
        }
    }

    private func stampTile(_ stamp: CaffeTogetherStamp) -> some View {
        let unlocked = stamp.isUnlocked(drinkCount: count)
        return VStack(spacing: 9) {
            ZStack(alignment: .bottomTrailing) {
                CaffeStampArt(stamp: stamp, unlocked: unlocked).frame(height: layout.expanded ? 142 : 118)
                Image(systemName: unlocked ? "checkmark.circle.fill" : "lock.circle.fill")
                    .font(.system(size: 20)).foregroundStyle(unlocked ? BrewStyle.gold : BrewStyle.icon)
                    .background(BrewStyle.ink, in: Circle())
            }
            Text(stamp.title).font(.system(size: 15, weight: .semibold))
                .foregroundStyle(unlocked ? BrewStyle.text : BrewStyle.muted)
            Text(stamp.caption).font(.system(size: 8, weight: .medium, design: .monospaced))
                .tracking(1).foregroundStyle(BrewStyle.muted).lineLimit(1).minimumScaleFactor(0.7)
            Text("\(stamp.requiredCount) 杯")
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(unlocked ? BrewStyle.gold : BrewStyle.icon)
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background((unlocked ? BrewStyle.gold : BrewStyle.icon).opacity(0.10), in: Capsule())
        }
        .frame(maxWidth: .infinity).padding(.vertical, 16).padding(.horizontal, 10)
        .background(BrewStyle.panel.opacity(0.72), in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(BrewStyle.border.opacity(unlocked ? 0.8 : 0.35), lineWidth: 0.8))
    }

    private var permanent: some View {
        Label("永久", systemImage: "infinity")
            .font(.system(size: 12, weight: .semibold)).foregroundStyle(BrewStyle.gold)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(BrewStyle.gold.opacity(0.10), in: Capsule())
    }

    private func detail(_ stamp: CaffeTogetherStamp) -> some View {
        VStack(spacing: 18) {
            Capsule().fill(BrewStyle.muted.opacity(0.5)).frame(width: 34, height: 4).padding(.top, 12)
            HStack {
                Text("caffe together").font(.system(size: 16, weight: .medium, design: .serif))
                Spacer(); permanent
                Button { selected = nil } label: { Image(systemName: "xmark").padding(10) }
                    .accessibilityLabel("关闭印章详情").accessibilityIdentifier("stamps.closeDetail")
            }
            CaffeStampArt(stamp: stamp).frame(height: 210)
            Text(stamp.title).font(.system(size: 24, weight: .semibold))
            Text(stamp.story).font(.subheadline).foregroundStyle(BrewStyle.muted).multilineTextAlignment(.center)
            if stamp.isUnlocked(drinkCount: count) {
                Label("已收集 · 累计 \(stamp.requiredCount) 杯", systemImage: "checkmark.seal.fill").foregroundStyle(BrewStyle.gold)
            } else {
                Text("再记录 \(stamp.remaining(drinkCount: count)) 杯，即可收集这枚印章。")
                    .font(.subheadline).foregroundStyle(BrewStyle.gold)
                ProgressView(value: stamp.progress(drinkCount: count)).tint(BrewStyle.gold)
            }
            Spacer(minLength: 10)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .foregroundStyle(BrewStyle.text)
        .background { BrewBackground() }
        .presentationDetents([.height(530), .large])
        .presentationDragIndicator(.hidden)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("stamps.detail")
    }
}
