import SwiftUI

struct FolderFrameKey: PreferenceKey {
    static var defaultValue = CGRect.zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue(); if !next.isEmpty { value = next }
    }
}

private struct FolderPhotosHiddenKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var folderPhotosHidden: Bool {
        get { self[FolderPhotosHiddenKey.self] }
        set { self[FolderPhotosHiddenKey.self] = newValue }
    }
}

/// Keep the animation outside the replaced artwork so both home previews
/// crossfade in the same transaction, including calendar commits without animation.
private struct MonthArtwork<ID: Hashable, Content: View>: View {
    @Environment(\.brewLayout) private var layout
    var id: ID
    var alignment: Alignment = .center
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack(alignment: alignment) {
            content().id(id).transition(.opacity)
        }
        .animation(layout.reduceMotion ? nil : .easeInOut(duration: 0.18), value: id)
        .transaction {
            $0.disablesAnimations = layout.reduceMotion
            if layout.reduceMotion { $0.animation = nil }
        }
    }
}

struct HomePage: View {
    @EnvironmentObject private var store: BrewStore
    @Environment(\.brewLayout) private var layout
    @Binding var month: Date
    @Binding var selectedDate: Date
    @Binding var weekMode: Bool
    var onRecord: (DrinkRecord) -> Void
    var onDrinks: () -> Void
    var onCards: () -> Void
    var onToggleMode: () -> Void

    private var monthRecords: [DrinkRecord] { store.records(in: month) }
    private var contentWidth: CGFloat { layout.size.width - (layout.bottomNavigation ? 0 : layout.contentRailInset) }
    private var calendarWidth: CGFloat {
        layout.landscape ? min(432, (contentWidth - 64) * 0.54) : min(432, contentWidth - 32)
    }

    var body: some View {
        Group {
            if layout.landscape {
                HStack(spacing: 38) {
                    pager(viewport: calendarWidth)
                    VStack(spacing: 26) {
                        souvenirRow
                        summary
                    }
                    .frame(maxWidth: 356)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20)
            } else {
                ScrollView {
                    VStack(spacing: layout.expanded ? 18 : 20) {
                        pager(viewport: contentWidth)
                            .padding(.top, layout.nativeNavigation && layout.controlRailInset == 0 ? 24 : 0)
                        if layout.expanded {
                            souvenirRow.frame(width: calendarWidth)
                            summary.frame(width: calendarWidth)
                        } else {
                            HStack(spacing: 14) {
                                summary.frame(width: (contentWidth - 46) * 0.60)
                                folder
                            }.padding(.horizontal, 16)
                        }
                    }
                    .padding(.top, layout.expanded ? 36 : layout.titleTop)
                    .padding(.bottom, layout.bottomNavigation && !layout.nativeNavigation ? 110 : 16)
                }
                .scrollIndicators(.hidden)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.layout")
        .accessibilityValue(layout.landscape ? "expanded-landscape" : layout.bottomNavigation ? "expanded-portrait" : "compact")
    }

    private func pager(viewport: CGFloat) -> some View {
        CalendarPager(month: $month, selectedDate: $selectedDate, weekMode: $weekMode,
                      width: calendarWidth, viewportWidth: viewport, onRecord: onRecord, onToggleMode: onToggleMode)
    }

    private var souvenirRow: some View {
        HStack(spacing: 18) {
            RoundedRectangle(cornerRadius: 26).fill(BrewStyle.souvenirPanel)
                .overlay { Image("MugReference").resizable().scaledToFit().frame(width: 100, height: 100) }
                .frame(maxWidth: .infinity).frame(height: layout.bottomNavigation ? 137 : 145)
                .accessibilityLabel("咖啡纪念杯")
            folder.frame(width: 145)
        }
    }

    private var summary: some View {
        Button(action: onDrinks) {
            BrewPanel {
                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 9) {
                        Text("本月").font(.system(size: 14, weight: .semibold))
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text("\(monthRecords.count)").font(.system(size: 30, weight: .medium))
                            Text("杯").font(BrewFont.caption)
                        }
                        Text("\(Set(monthRecords.map(\.shop).filter { !$0.isEmpty }).count) 家店铺")
                            .font(BrewFont.caption).foregroundStyle(BrewStyle.muted)
                    }
                    Spacer(minLength: 0)
                    MonthArtwork(id: monthRecords.map(\.id)) {
                        if let record = monthRecords.first {
                            DrinkSticker(image: store.image(for: record), cutout: store.sticker(for: record),
                                         size: layout.expanded ? 72 : 54)
                        }
                    }.frame(width: layout.expanded ? 100 : 58)
                }
                .padding(18)
                .frame(maxWidth: .infinity, minHeight: layout.expanded ? 145 : 119, alignment: .leading)
            }
        }
        .accessibilityIdentifier("home.summary")
    }

    private var folder: some View {
        Button(action: onCards) {
            PhotoFolder(records: Array(monthRecords.filter { $0.photoFile != nil }.prefix(2)))
                .frame(maxWidth: .infinity, minHeight: 145)
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(key: FolderFrameKey.self, value: geometry.frame(in: .named("brewRoot")))
                    }
                }
                .padding(.horizontal, layout.expanded ? 0 : 8)
        }
        .accessibilityLabel("照片卡片").accessibilityIdentifier("nav.cards")
    }
}

struct DrinksPage: View {
    @EnvironmentObject private var store: BrewStore
    @Environment(\.brewLayout) private var layout
    @Binding var month: Date
    var onRecord: (DrinkRecord) -> Void
    var onClose: (() -> Void)? = nil
    var onDrag: ((CGFloat) -> Void)? = nil
    var onDragEnd: ((CGFloat, CGFloat) -> Void)? = nil
    var closeButtonX: CGFloat? = nil
    @State private var draggingBlank = false

    private var blankDrag: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .global)
            .onChanged { value in
                if onDrag != nil && value.translation.height > abs(value.translation.width) {
                    draggingBlank = true
                }
                guard draggingBlank else { return }
                onDrag?(max(0, value.translation.height))
            }
            .onEnded { value in
                guard draggingBlank else { return }
                draggingBlank = false
                onDragEnd?(value.translation.height, value.predictedEndTranslation.height)
            }
    }

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 12) {
                Text("本月").font(BrewFont.heading)
                Text("\(store.records(in: month).count) 杯 · \(Set(store.records(in: month).map(\.shop).filter { !$0.isEmpty }).count) 家店铺")
                    .font(BrewFont.caption).foregroundStyle(BrewStyle.muted)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, max(layout.titleTop, onClose == nil ? 0 : 58))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 12, coordinateSpace: .global)
                .onChanged { value in
                    if value.translation.height > abs(value.translation.width) {
                        onDrag?(max(0, value.translation.height))
                    }
                }
                .onEnded { onDragEnd?($0.translation.height, $0.predictedEndTranslation.height) })
            if store.records(in: month).isEmpty {
                EmptyPage(title: "还没有饮品记录", symbol: "cup.and.saucer", detail: "点 +，记录今天的一杯。")
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140, maximum: 210), spacing: 14)], spacing: 14) {
                        ForEach(store.records(in: month)) { record in
                            Button { onRecord(record) } label: {
                                BrewPanel {
                                    VStack(alignment: .leading, spacing: 10) {
                                        HStack {
                                            DrinkSticker(image: store.image(for: record), cutout: store.sticker(for: record), size: 76)
                                            Spacer(minLength: 0)
                                            Image(systemName: record.favorite ? "star.fill" : "star")
                                                .foregroundStyle(record.favorite ? BrewStyle.gold : BrewStyle.muted)
                                        }
                                        Text(record.name.isEmpty ? "未命名饮品" : record.name)
                                            .font(.system(size: 15, weight: .semibold)).lineLimit(1)
                                        Text(record.date.shortDate + " " + record.date.timeText)
                                            .font(BrewFont.caption).foregroundStyle(BrewStyle.muted)
                                    }
                                    .padding(17).frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .accessibilityIdentifier("drink.\(record.name)")
                        }
                    }
                    .padding(.top, 14)
                    .frame(maxWidth: .infinity, minHeight: max(0, layout.size.height - 180), alignment: .top)
                    .background {
                        // Cards receive their own touches; only the uncovered grid
                        // background can start an interactive page dismissal.
                        Color.clear.contentShape(Rectangle())
                            .highPriorityGesture(blankDrag)
                    }
                }
            }
        }
        .padding(layout.leftHanded ? .leading : .trailing, onClose == nil ? 0 : 56)
        .brewPagePadding()
        .overlay(alignment: layout.leftHanded ? .leading : .trailing) {
            if let onClose {
                let defaultX = layout.leftHanded ? CGFloat(33) : layout.size.width - 33
                BrewGlassButton(symbol: "xmark", label: "返回首页", identifier: "nav.home", action: onClose)
                    .padding(.horizontal, 10)
                    .offset(x: (closeButtonX ?? defaultX) - defaultX,
                            y: layout.utilityCenterY(preferred: layout.size.height / 2, height: 46) - layout.size.height / 2)
            }
        }
    }
}

struct CardsPage: View {
    @EnvironmentObject private var store: BrewStore
    @Environment(\.brewLayout) private var layout
    @Binding var month: Date
    @State private var grid = false
    @Namespace private var cards

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Spacer()
                Menu {
                    Button("上个月") { month = Calendar.current.date(byAdding: .month, value: -1, to: month) ?? month }
                    Button("下个月") { month = Calendar.current.date(byAdding: .month, value: 1, to: month) ?? month }
                } label: {
                    Label(month.monthTitle, systemImage: "chevron.down").font(BrewFont.heading)
                }
                Spacer()
                BrewGlassButton(symbol: grid ? "square" : "square.grid.2x2", size: 42,
                                label: "切换卡片布局", identifier: "cards.layout") {
                    withAnimation(layout.animation) { grid.toggle() }
                }
            }
            .padding(.top, layout.titleTop)
            if store.records(in: month).isEmpty {
                EmptyPage(title: "还没有照片卡片", symbol: "photo.on.rectangle.angled", detail: "为饮品添加照片，留下今天的回忆。")
            } else {
                ScrollView {
                    LazyVGrid(columns: grid ? [GridItem(.adaptive(minimum: 140, maximum: 230), spacing: 14)] : [GridItem(.flexible())], spacing: 20) {
                        ForEach(store.records(in: month)) { record in
                            polaroid(record)
                                .frame(maxWidth: grid ? 230 : 300)
                                .matchedGeometryEffect(id: record.id, in: cards)
                        }
                    }
                    .padding(.top, layout.landscape ? 14 : 50)
                }
            }
        }
        .brewPagePadding()
    }

    private func polaroid(_ record: DrinkRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Group {
                if let photo = store.image(for: record) {
                    Image(uiImage: photo).resizable().scaledToFill()
                } else {
                    Rectangle().fill(BrewStyle.panel)
                        .overlay(Image(systemName: "cup.and.saucer.fill").font(.system(size: 55)).foregroundStyle(BrewStyle.gold))
                }
            }
            .frame(height: grid ? 160 : 300).clipped()
            Text(record.shop.isEmpty ? record.name : record.shop)
                .font(.system(size: grid ? 10 : 13, weight: .semibold)).foregroundStyle(BrewStyle.photoInk)
            Text(record.date.shortDate + " " + record.date.timeText)
                .font(.system(size: grid ? 9 : 11)).foregroundStyle(BrewStyle.photoCaption)
        }
        .padding(grid ? 10 : 18).padding(.bottom, grid ? 5 : 12)
        .background(BrewStyle.photoFrame, in: RoundedRectangle(cornerRadius: 5))
        .shadow(color: .black.opacity(0.16), radius: 12, y: 6)
    }
}

/// The pocket transmits the actual cards behind it. The second, blurred copy is
/// clipped to the pocket so the exposed photographs keep their original detail.
private struct PhotoFolder: View {
    @Environment(\.brewLayout) private var layout
    @EnvironmentObject private var store: BrewStore
    var records: [DrinkRecord]
    @Environment(\.folderPhotosHidden) private var photosHidden
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private let pocketHeight: CGFloat = 85

    var body: some View {
        ZStack(alignment: .bottom) {
            cards
            if !reduceTransparency {
                cards
                    .blur(radius: 7)
                    .mask(alignment: .bottom) { FolderPocket().frame(height: pocketHeight) }
                    .allowsHitTesting(false)
            }
            FolderPocketSurface().frame(height: pocketHeight)
        }
        .frame(height: 145)
        .accessibilityHidden(true)
    }

    private var cards: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 12).fill(BrewStyle.folderBack)
                .frame(height: 91)
            MonthArtwork(id: records.map(\.id), alignment: .bottom) {
                if records.count > 1 {
                    PolaroidPhoto(record: records[1], image: store.image(for: records[1]), whiteFrame: false)
                        .frame(width: 82, height: 97)
                        .rotationEffect(.degrees(9)).offset(x: 13, y: -26)
                        .opacity(photosHidden ? 0 : 1)
                } else {
                    RoundedRectangle(cornerRadius: 2).fill(BrewStyle.photoWhite)
                        .frame(width: 82, height: 97)
                        .overlay(alignment: .top) {
                            Rectangle().fill(BrewStyle.panelLight).frame(width: 70, height: 72).padding(.top, 6)
                        }
                        .rotationEffect(.degrees(9)).offset(x: 13, y: -26)
                }
                if let record = records.first {
                    PolaroidPhoto(record: record, image: store.image(for: record), whiteFrame: records.count > 1)
                        .frame(width: 82, height: 97)
                        .rotationEffect(.degrees(-8)).offset(x: -8, y: -23)
                        .opacity(photosHidden ? 0 : 1)
                } else {
                    RoundedRectangle(cornerRadius: 2).fill(BrewStyle.photoFrame)
                        .frame(width: 82, height: 97)
                        .rotationEffect(.degrees(-8)).offset(x: -8, y: -23)
                }
            }
        }
        .frame(height: 145, alignment: .bottom)
    }
}

/// Shared by the resting pocket and its material over moving photographs.
struct FolderPocketSurface: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        FolderPocket()
            .fill(LinearGradient(stops: [
                .init(color: BrewStyle.folderLeft.opacity(reduceTransparency ? 1 : 0.76), location: 0),
                .init(color: BrewStyle.folderCenter.opacity(reduceTransparency ? 1 : 0.70), location: 0.42),
                .init(color: BrewStyle.folderRight.opacity(reduceTransparency ? 1 : 0.76), location: 0.76),
                .init(color: BrewStyle.folderBottom.opacity(reduceTransparency ? 1 : 0.84), location: 1)
            ], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay {
                FolderPocket().stroke(
                    LinearGradient(colors: [BrewStyle.photoWhite.opacity(0.18), BrewStyle.photoWhite.opacity(0.035)],
                                   startPoint: .topTrailing, endPoint: .bottomLeading), lineWidth: 0.7)
            }
            .shadow(color: .black.opacity(0.14), radius: 2, y: 2)
    }
}

/// One continuous lip, including the raised section on the right.
struct FolderPocket: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        let r = min(16.0, w * 0.14)
        let lip = h * 0.15
        p.move(to: CGPoint(x: r, y: lip))
        p.addLine(to: CGPoint(x: w * 0.44, y: lip))
        p.addCurve(to: CGPoint(x: w * 0.68, y: 0),
                   control1: CGPoint(x: w * 0.57, y: lip), control2: CGPoint(x: w * 0.56, y: 0))
        p.addLine(to: CGPoint(x: w - r, y: 0))
        p.addQuadCurve(to: CGPoint(x: w, y: r), control: CGPoint(x: w, y: 0))
        p.addLine(to: CGPoint(x: w, y: h - r))
        p.addQuadCurve(to: CGPoint(x: w - r, y: h), control: CGPoint(x: w, y: h))
        p.addLine(to: CGPoint(x: r, y: h))
        p.addQuadCurve(to: CGPoint(x: 0, y: h - r), control: CGPoint(x: 0, y: h))
        p.addLine(to: CGPoint(x: 0, y: lip + r))
        p.addQuadCurve(to: CGPoint(x: r, y: lip), control: CGPoint(x: 0, y: lip))
        p.closeSubpath()
        return p.applying(CGAffineTransform(translationX: rect.minX, y: rect.minY))
    }
}
