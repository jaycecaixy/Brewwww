import SwiftUI

/// A retained home view supplies the real folder position; cards fly out of that
/// position, staying occluded by the pocket until they have been pulled free.
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
    private var buttonAxis: CGFloat {
        layout.sidebarAxis > 0 ? layout.sidebarAxis : (layout.leftHanded ? 33 : size.width - 33)
    }
    private var artworkBounds: CGRect {
        guard !layout.expanded else {
            return CGRect(x: 0, y: 0, width: size.width - (layout.bottomNavigation ? 0 : layout.contentRailInset), height: size.height)
        }
        // Reserve the actual button column plus a visible gap on folded screens.
        let leading: CGFloat = layout.leftHanded ? buttonAxis + 23 + 20 : 16
        let trailing: CGFloat = layout.leftHanded ? size.width - 16 : buttonAxis - 23 - 20
        return CGRect(x: leading, y: 0, width: max(1, trailing - leading), height: size.height)
    }
    private var cardGap: CGFloat { layout.expanded ? 20 : 16 }
    private var cardWidth: CGFloat {
        if layout.expanded { return grid ? min(204, (size.width - 90) / 2) : min(288, size.width - 110) }
        return grid ? min(148, max(1, (artworkBounds.width - cardGap) / 2)) : min(252, artworkBounds.width)
    }
    private var emptyWidth: CGFloat { min(270, artworkBounds.width) }
    private var cardHeight: CGFloat { cardWidth * 1.4 }
    private var columns: Int { grid ? 2 : 1 }
    private var top: CGFloat { layout.landscape ? 114 : layout.expanded ? 170 : 145 }

    var body: some View {
        ZStack(alignment: .top) {
            BrewStyle.albumTop.modifier(AlbumBackdropFade(progress: progress)).ignoresSafeArea()
                .contentShape(Rectangle()).onTapGesture { }
            if records.isEmpty {
                emptyCards
            } else {
                ScrollView {
                    ZStack(alignment: .topLeading) {
                        // The pocket material is behind all released photographs.
                        // Its mask follows the moving silhouettes in every frame.
                        ZStack(alignment: .topLeading) {
                            ZStack(alignment: .topLeading) {
                                BrewStyle.folderBack
                                flyingCards(layer: .frosted)
                            }.blur(radius: 7)
                            FolderPocketSurface()
                                .frame(width: pocketFrame.width, height: pocketFrame.height)
                                .position(x: pocketFrame.midX, y: pocketFrame.midY)
                        }
                        .mask {
                            ZStack(alignment: .topLeading) { flyingCards(layer: .silhouette) }
                                .blur(radius: 7)
                        }
                        .mask { FolderPocket().path(in: pocketFrame).fill(.white) }
                        .accessibilityHidden(true)
                        flyingCards(layer: .photo)
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

    private func flyingCards(layer: PolaroidFlightLayer) -> some View {
        ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
            PolaroidPhoto(record: record, image: store.image(for: record), whiteFrame: index % 2 == 0 && records.count > 1)
                .frame(width: cardWidth, height: cardHeight)
                .modifier(PolaroidFlight(progress: layout.reduceMotion ? 1 : progress,
                                        source: source(index), destination: destination(index),
                                        angle: index % 2 == 0 ? -8 : 9, pocket: pocketFrame, layer: layer))
                .zIndex(Double(records.count - index))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("album.photo.\(index)")
                .accessibilityHidden(layer != .photo)
        }
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
                    .frame(width: 42, height: 94)
                    .position(x: buttonAxis,
                              y: layout.utilityCenterY(preferred: (layout.landscape ? 176 : 223) + 47, height: 94))
            }
        }
    }
    private var gridButton: some View {
        BrewGlassButton(symbol: grid ? "square" : "square.grid.2x2", label: "切换卡片布局", identifier: "cards.layout") {
            withAnimation(layout.animation) { grid.toggle() }
        }
    }
    private var closeButton: some View {
        BrewGlassButton(symbol: "xmark", label: "收起照片", identifier: "album.close", action: onClose)
    }
    private var emptyCards: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.on.rectangle.angled").font(.system(size: 85, weight: .thin)).foregroundStyle(BrewStyle.icon)
            Text("这个月还没有照片\n为饮品添加照片，留下今天的回忆。")
                .font(BrewFont.caption).multilineTextAlignment(.center).foregroundStyle(BrewStyle.muted)
        }
        .frame(width: emptyWidth, height: 220)
        .modifier(PolaroidFlight(progress: layout.reduceMotion ? 1 : progress, source: source(0),
                                destination: CGRect(x: artworkBounds.midX - emptyWidth / 2, y: top + 25, width: emptyWidth, height: 220), angle: -8, pocket: pocketFrame))
    }
    private var pocketFrame: CGRect {
        let folder = resolvedFolderFrame
        return CGRect(x: folder.minX, y: folder.maxY - 85 + scrollOffset,
                      width: folder.width, height: 85)
    }
    private var resolvedFolderFrame: CGRect {
        folderFrame.isEmpty ? CGRect(x: size.width - 180, y: size.height - 190, width: 130, height: 145) : folderFrame
    }
    private func source(_ index: Int) -> CGRect {
        let folder = resolvedFolderFrame
        return CGRect(x: folder.midX - 41 + (index % 2 == 0 ? -8 : 13),
                      y: folder.maxY - (index % 2 == 0 ? 120 : 123) + scrollOffset, width: 82, height: 97)
    }
    private func destination(_ index: Int) -> CGRect {
        let count = min(columns, records.count)
        let rowWidth = CGFloat(count) * cardWidth + CGFloat(count - 1) * cardGap
        return CGRect(x: artworkBounds.midX - rowWidth / 2 + CGFloat(index % columns) * (cardWidth + cardGap),
                      y: top + CGFloat(index / columns) * (cardHeight + 25), width: cardWidth, height: cardHeight)
    }
}

/// Let the cards start moving before introducing the backdrop. Evaluate it in
/// animatable modifiers so it follows every animation frame in both directions.
private func albumExpansion(_ progress: CGFloat) -> CGFloat {
    let t = min(1, max(0, (progress - 0.12) / 0.88))
    return t * t * (3 - 2 * t)
}

struct AlbumBackgroundBlur: AnimatableModifier {
    var progress: CGFloat
    var animatableData: CGFloat { get { progress } set { progress = newValue } }
    func body(content: Content) -> some View {
        content.blur(radius: albumExpansion(progress) * 12)
    }
}

private struct AlbumBackdropFade: AnimatableModifier {
    var progress: CGFloat
    var animatableData: CGFloat { get { progress } set { progress = newValue } }
    func body(content: Content) -> some View {
        content.opacity(albumExpansion(progress) * 0.66)
    }
}

/// A single curve drives position, scale and rotation together. The point at
/// which a photo clears the lip is found from its actual rotated bounds, so
/// changing size, folder position or layout never introduces a timed layer jump.
private struct PolaroidTrajectory {
    var source: CGRect
    var destination: CGRect
    var angle: Double
    var pocket: CGRect

    private var control: CGPoint {
        let middleY = (source.midY + destination.midY) / 2
        let radians = angle * .pi / 360
        let halfHeight = (abs(sin(radians)) * (source.width + destination.width)
            + abs(cos(radians)) * (source.height + destination.height)) / 4
        // Even a lower grid row must leave the pocket before passing over it.
        let clearAtMiddle = 2 * (pocket.minY - halfHeight - 24) - (source.midY + destination.midY) / 2
        return CGPoint(x: (source.midX + destination.midX) / 2,
                       y: min(middleY - min(32, abs(source.midY - destination.midY) * 0.12), clearAtMiddle))
    }
    func pose(_ progress: CGFloat) -> PolaroidPose {
        let p = min(1, max(0, progress)), q = 1 - p
        return PolaroidPose(center: CGPoint(x: q*q*source.midX + 2*q*p*control.x + p*p*destination.midX,
                                           y: q*q*source.midY + 2*q*p*control.y + p*p*destination.midY),
                            size: CGSize(width: source.width + (destination.width - source.width) * p,
                                         height: source.height + (destination.height - source.height) * p),
                            angle: angle * Double(q))
    }
    var clearsPocketAt: CGFloat {
        var lower: CGFloat = 0, upper: CGFloat = 0.5
        for _ in 0..<12 {
            let middle = (lower + upper) / 2
            if pose(middle).bottom + 21 > pocket.minY { lower = middle } else { upper = middle }
        }
        return upper
    }
}

private struct PolaroidPose {
    var center: CGPoint
    var size: CGSize
    var angle: Double
    var bottom: CGFloat {
        let radians = angle * .pi / 180
        return center.y + (abs(sin(radians)) * size.width + abs(cos(radians)) * size.height) / 2
    }
}

private enum PolaroidFlightLayer { case photo, frosted, silhouette }

private struct PolaroidFlight: AnimatableModifier {
    var progress: CGFloat
    var source: CGRect
    var destination: CGRect
    var angle: Double
    var pocket: CGRect
    var layer: PolaroidFlightLayer = .photo
    var animatableData: CGFloat { get { progress } set { progress = newValue } }

    @ViewBuilder func body(content: Content) -> some View {
        let p = min(1, max(0, progress))
        let trajectory = PolaroidTrajectory(source: source, destination: destination, angle: angle, pocket: pocket)
        let pose = trajectory.pose(p)
        let behindPocket = p < trajectory.clearsPocketAt
        switch layer {
        case .photo:
            content
                .scaleEffect(x: pose.size.width / destination.width, y: pose.size.height / destination.height)
                .rotationEffect(.degrees(pose.angle)).position(pose.center)
                .shadow(color: .black.opacity(0.18 * p), radius: 9 * p, y: 5 * p)
                .mask {
                    GeometryReader { geometry in
                        Path { path in
                            path.addRect(CGRect(origin: .zero, size: geometry.size))
                            if behindPocket { path.addPath(FolderPocket().path(in: pocket)) }
                        }.fill(style: FillStyle(eoFill: true))
                    }
                }
        case .frosted:
            if behindPocket {
                content
                    .scaleEffect(x: pose.size.width / destination.width, y: pose.size.height / destination.height)
                    .rotationEffect(.degrees(pose.angle)).position(pose.center)
            }
        case .silhouette:
            if behindPocket {
                RoundedRectangle(cornerRadius: 3)
                    .fill(.white).frame(width: pose.size.width, height: pose.size.height)
                    .rotationEffect(.degrees(pose.angle)).position(pose.center)
            }
        }
    }
}

/// One design canvas is used by both the resting miniature and the flying card,
/// avoiding a change of photo crop, frame or text at the first animation frame.
struct PolaroidPhoto: View {
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
                .frame(width: 174, height: 218.4).clipped()
                Text(record.shop.isEmpty ? record.name : record.shop)
                    .font(.system(size: 9.4, weight: .semibold)).lineLimit(1)
                    .foregroundStyle(BrewStyle.photoInk)
                Text(record.date.shortDate + " " + record.date.timeText)
                    .font(.system(size: 8)).foregroundStyle(BrewStyle.photoCaption)
                Spacer(minLength: 0)
            }
            .padding(13)
            .frame(width: 200, height: 280)
            .background(whiteFrame ? BrewStyle.photoWhite : BrewStyle.photoFrame, in: RoundedRectangle(cornerRadius: 3))
            .scaleEffect(x: geometry.size.width / 200, y: geometry.size.height / 280, anchor: .topLeading)
        }
    }
}

private struct AlbumScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
