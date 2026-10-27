import SwiftUI

/// A retained home view supplies the real folder position; cards fly out of that
/// position with translation, scale and rotation. Their opacity never animates.
struct PhotoAlbumOverlay: View {
    @EnvironmentObject private var store: BrewStore
    @Environment(\.brewLayout) private var layout
    @Binding var month: Date
    var folderFrame: CGRect
    var progress: CGFloat
    var onClose: () -> Void
    @State private var grid = true
    @State private var scrollOffset: CGFloat = 0

    private var records: [DrinkRecord] { store.records(in: month).filter { $0.photoFile != nil } }
    private var size: CGSize { layout.size }
    private var cardWidth: CGFloat { grid ? min(layout.expanded ? 204 : 185, (size.width - 90) / 2) : min(288, size.width - 110) }
    private var cardHeight: CGFloat { cardWidth * 1.4 }
    private var columns: Int { grid ? 2 : 1 }
    private var top: CGFloat { layout.landscape ? 114 : layout.expanded ? 170 : 145 }

    var body: some View {
        ZStack(alignment: .top) {
            BrewStyle.albumTop.opacity(progress * 0.66).ignoresSafeArea()
                .contentShape(Rectangle()).onTapGesture { }
            if records.isEmpty {
                emptyCards
            } else {
                ScrollView {
                    ZStack(alignment: .topLeading) {
                        ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                            PolaroidPhoto(record: record, image: store.image(for: record), whiteFrame: index % 2 == 0 && records.count > 1)
                                .frame(width: cardWidth, height: cardHeight)
                                .modifier(PolaroidFlight(progress: layout.reduceMotion ? 1 : progress,
                                                        source: source(index), destination: destination(index),
                                                        angle: index % 2 == 0 ? -8 : 9, canvasHeight: size.height))
                                .accessibilityElement(children: .combine)
                                .accessibilityIdentifier("album.photo.\(index)")
                        }
                    }
                    .frame(width: size.width, height: max(size.height, top + CGFloat((records.count + columns - 1) / columns) * (cardHeight + 25) + 40))
                    .background {
                        GeometryReader { geometry in
                            Color.clear.preference(key: AlbumScrollOffsetKey.self,
                                                   value: max(0, -geometry.frame(in: .named("albumScroll")).minY))
                        }
                    }
                }
                .coordinateSpace(name: "albumScroll")
                .onPreferenceChange(AlbumScrollOffsetKey.self) { scrollOffset = $0 }
                .scrollIndicators(.hidden)
                .scrollDisabled(progress < 0.99)
            }
            header.opacity(progress)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("album.overlay")
        .accessibilityValue(progress >= 0.99 ? "open" : "flying")
    }

    private var header: some View {
        ZStack(alignment: .top) {
            Menu {
                Button("上个月") { month = BrewCalendarPaging.shifted(month, by: -1, weekMode: false) }
                Button("下个月") { month = BrewCalendarPaging.shifted(month, by: 1, weekMode: false) }
            } label: { Label(month.monthTitle, systemImage: "chevron.down").font(BrewFont.heading) }
                .padding(.top, layout.landscape ? 52 : layout.expanded ? 90 : 38)
            if layout.bottomNavigation {
                HStack(spacing: 12) { gridButton; closeButton; Spacer() }.padding(16)
            } else {
                VStack(spacing: 10) { gridButton; closeButton }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 10).padding(.top, layout.landscape ? 176 : 223)
            }
        }
    }
    private var gridButton: some View {
        Button { withAnimation(layout.animation) { grid.toggle() } } label: {
            RoundIcon(symbol: grid ? "square" : "square.grid.2x2", size: 42)
        }.accessibilityLabel("切换卡片布局").accessibilityIdentifier("cards.layout")
    }
    private var closeButton: some View {
        Button(action: onClose) { RoundIcon(symbol: "xmark", size: 42) }
            .accessibilityLabel("收起照片").accessibilityIdentifier("album.close")
    }
    private var emptyCards: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.on.rectangle.angled").font(.system(size: 85, weight: .thin)).foregroundStyle(BrewStyle.photoWhite)
            Text("这个月还没有照片\n为饮品添加照片，留下今天的回忆。")
                .font(BrewFont.caption).multilineTextAlignment(.center).foregroundStyle(BrewStyle.muted)
        }
        .frame(width: 270, height: 220)
        .modifier(PolaroidFlight(progress: layout.reduceMotion ? 1 : progress, source: source(0),
                                destination: CGRect(x: (size.width - 270) / 2, y: top + 25, width: 270, height: 220), angle: -8, canvasHeight: size.height))
    }
    private func source(_ index: Int) -> CGRect {
        let folder = folderFrame.isEmpty ? CGRect(x: size.width - 180, y: size.height - 190, width: 130, height: 145) : folderFrame
        return CGRect(x: folder.midX - 41 + (index % 2 == 0 ? -8 : 13),
                      y: folder.maxY - (index % 2 == 0 ? 120 : 123) + scrollOffset, width: 82, height: 97)
    }
    private func destination(_ index: Int) -> CGRect {
        let count = min(columns, records.count)
        let rowWidth = CGFloat(count) * cardWidth + CGFloat(count - 1) * 20
        let availableWidth = size.width - (layout.bottomNavigation ? 0 : 66)
        return CGRect(x: (availableWidth - rowWidth) / 2 + CGFloat(index % columns) * (cardWidth + 20),
                      y: top + CGFloat(index / columns) * (cardHeight + 25), width: cardWidth, height: cardHeight)
    }
}

private struct PolaroidFlight: AnimatableModifier {
    var progress: CGFloat
    var source: CGRect
    var destination: CGRect
    var angle: Double
    var canvasHeight: CGFloat
    var animatableData: CGFloat { get { progress } set { progress = newValue } }

    func body(content: Content) -> some View {
        let p = progress
        let arc = sin(min(1, max(0, p)) * .pi) * min(80, canvasHeight * 0.10)
        content
            .scaleEffect(x: source.width / destination.width + (1 - source.width / destination.width) * p,
                         y: source.height / destination.height + (1 - source.height / destination.height) * p)
            .rotationEffect(.degrees(angle * (1 - p)))
            .position(x: source.midX + (destination.midX - source.midX) * p,
                      y: source.midY + (destination.midY - source.midY) * p - arc)
    }
}

private struct PolaroidPhoto: View {
    var record: DrinkRecord
    var image: UIImage?
    var whiteFrame: Bool
    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 4) {
                Group {
                    if let image { Image(uiImage: image).resizable().scaledToFill() }
                    else { BrewStyle.panel }
                }
                .frame(height: geometry.size.height * 0.78).clipped()
                Text(record.shop.isEmpty ? record.name : record.shop)
                    .font(.system(size: max(9, geometry.size.width * 0.047), weight: .semibold)).lineLimit(1)
                    .foregroundStyle(BrewStyle.photoInk)
                Text(record.date.shortDate + " " + record.date.timeText)
                    .font(.system(size: max(8, geometry.size.width * 0.04))).foregroundStyle(BrewStyle.photoCaption)
                Spacer(minLength: 0)
            }
            .padding(geometry.size.width * 0.065)
            .frame(width: geometry.size.width, height: geometry.size.height)
            .background(whiteFrame ? BrewStyle.photoWhite : BrewStyle.photoFrame, in: RoundedRectangle(cornerRadius: 3))
            .shadow(color: .black.opacity(0.18), radius: 9, y: 5)
        }
    }
}

private struct AlbumScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
