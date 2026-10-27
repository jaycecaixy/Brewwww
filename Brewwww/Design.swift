import SwiftUI

// Measured from native 3× frames, CoreMedia709 converted to sRGB.
// Provenance and sample rectangles: 设计取色/reference-colors.json.
enum BrewStyle {
    static func rgb(_ hex: UInt32) -> Color {
        Color(.sRGB, red: Double((hex >> 16) & 255) / 255,
              green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: 1)
    }
    static let ink = rgb(0x2B2A23)
    static let text = rgb(0xD3D0CB)
    static let panel = rgb(0x463E36)
    static let panelLight = rgb(0x655A54)
    static let muted = rgb(0xA19B96)
    static let gold = rgb(0xDCAB70)
    static let orange = rgb(0xB84D07)
    static let weekday = rgb(0x867F77)
    static let calendarNumber = rgb(0xD3D0C9)
    static let control = rgb(0x383734)
    static let icon = rgb(0xA39A96)
    static let selection = rgb(0x666561)
    static let border = rgb(0x635B53)
    static let placeholder = rgb(0x776D67)
    static let confirmation = rgb(0xFAF9F4)
    static let photoFrame = rgb(0xDFB16F)
    static let photoInk = rgb(0x321500)
    static let photoCaption = rgb(0x795521)
    static let photoWhite = rgb(0xFEFEFE)
    static let toggleOff = rgb(0xE7E5DE)
    static let folderBack = rgb(0x443D36)
    static let folderLeft = rgb(0x726550)
    static let folderCenter = rgb(0x7A6C54)
    static let folderRight = rgb(0x70685D)
    static let folderBottom = rgb(0x6E6353)
    static let folderTab = rgb(0x746A5A)
    static let albumTop = rgb(0x3F3A39)
    static let albumMiddle = rgb(0x47433F)
    static let albumBottom = rgb(0x3F3B3A)
    static let albumControl = rgb(0x403F3D)
    static let stampPink = rgb(0xD97F69)
    static let stampGold = rgb(0xC59A65)
    static let mapPanel = rgb(0x32363D)
    static let mapPin = rgb(0xD25400)
    static let mapControl = rgb(0x32394A)
    static let mapNavigation = rgb(0x363D46)
    static let mapSelection = rgb(0x65686D)
}

struct BrewBackground: View {
    @AppStorage("passportStyle") private var passportStyle = 0

    var body: some View {
        ZStack {
            BrewStyle.ink
            Image(passportStyle == 1 ? "PaperPreview2" : passportStyle == 2 ? "PaperPreview3" : "PaperReference")
                .resizable(resizingMode: .tile)
                .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }
}

struct BrewPanel<Content: View>: View {
    let content: Content
    var mapSurface: Bool

    init(mapSurface: Bool = false, @ViewBuilder content: () -> Content) {
        self.mapSurface = mapSurface
        self.content = content()
    }

    var body: some View {
        content
            .background {
                if mapSurface { Image("MapCardReference").resizable(resizingMode: .tile) }
                else { BrewStyle.panel }
            }
            .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 19, style: .continuous)
                .stroke(BrewStyle.border, lineWidth: 1))
    }
}

struct RoundIcon: View {
    var symbol: String
    var active = false
    var size: CGFloat = 46
    var accent = false
    @Environment(\.brewControlSurface) private var surface

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 20, weight: .regular))
            .foregroundStyle(active ? BrewStyle.confirmation : accent ? BrewStyle.gold : BrewStyle.icon)
            .frame(width: size, height: size)
            .background(active ? BrewStyle.gold : surface)
            .clipShape(Circle())
            .overlay(Circle().stroke(BrewStyle.border, lineWidth: 1))
    }
}

struct TakeawayCup: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let t = CGAffineTransform(scaleX: rect.width / 24, y: rect.height / 28)
        p.addRoundedRect(in: CGRect(x: 3, y: 6, width: 18, height: 4), cornerSize: CGSize(width: 1, height: 1))
        p.move(to: CGPoint(x: 5, y: 6)); p.addLine(to: CGPoint(x: 6, y: 3))
        p.addLine(to: CGPoint(x: 18, y: 3)); p.addLine(to: CGPoint(x: 19, y: 6))
        p.move(to: CGPoint(x: 5, y: 10)); p.addLine(to: CGPoint(x: 7, y: 25))
        p.addLine(to: CGPoint(x: 17, y: 25)); p.addLine(to: CGPoint(x: 19, y: 10))
        p.move(to: CGPoint(x: 6, y: 14)); p.addLine(to: CGPoint(x: 18, y: 14))
        return p.applying(t)
    }
}

struct RubberStamp: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let t = CGAffineTransform(scaleX: rect.width / 24, y: rect.height / 28)
        p.move(to: CGPoint(x: 8, y: 17))
        p.addCurve(to: CGPoint(x: 8, y: 7), control1: CGPoint(x: 10, y: 14), control2: CGPoint(x: 8, y: 11))
        p.addCurve(to: CGPoint(x: 16, y: 7), control1: CGPoint(x: 5, y: 0), control2: CGPoint(x: 19, y: 0))
        p.addCurve(to: CGPoint(x: 16, y: 17), control1: CGPoint(x: 16, y: 11), control2: CGPoint(x: 14, y: 14))
        p.addRoundedRect(in: CGRect(x: 4, y: 17, width: 16, height: 5), cornerSize: CGSize(width: 1.5, height: 1.5))
        p.addRoundedRect(in: CGRect(x: 6, y: 22, width: 12, height: 3), cornerSize: CGSize(width: 1, height: 1))
        return p.applying(t)
    }
}

struct DrinkSticker: View {
    var image: UIImage?
    var cutout: UIImage? = nil
    var size: CGFloat = 70

    var body: some View {
        Group {
            if let cutout {
                Image(uiImage: cutout)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
            } else if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.25))
                    .overlay(RoundedRectangle(cornerRadius: size * 0.25)
                        .stroke(.white, lineWidth: max(3, size * 0.06)))
            } else {
                Image(systemName: "cup.and.saucer.fill")
                    .font(.system(size: size * 0.50, weight: .light))
                    .foregroundStyle(BrewStyle.gold)
                    .frame(width: size, height: size)
                    .background(BrewStyle.panelLight)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.25))
                    .overlay(RoundedRectangle(cornerRadius: size * 0.25)
                        .stroke(.white, lineWidth: max(3, size * 0.06)))
            }
        }
        .rotationEffect(.degrees(-7))
        .shadow(color: .black.opacity(0.3), radius: 5, y: 3)
    }
}

struct EmptyPage: View {
    var title: String
    var symbol: String
    var detail: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 66, weight: .ultraLight))
                .foregroundStyle(BrewStyle.gold)
            Text(title).font(.title3.bold())
            Text(detail).font(.subheadline).foregroundStyle(BrewStyle.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }
}

extension View {
    func brewRow() -> some View {
        self.frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .frame(minHeight: 64)
            .background(BrewStyle.panel)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18)
                .stroke(BrewStyle.border, lineWidth: 1))
    }
}

private struct BrewControlSurfaceKey: EnvironmentKey {
    static let defaultValue = BrewStyle.control
}
extension EnvironmentValues {
    var brewControlSurface: Color {
        get { self[BrewControlSurfaceKey.self] }
        set { self[BrewControlSurfaceKey.self] = newValue }
    }
}

struct BrewToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label.foregroundStyle(configuration.isOn ? BrewStyle.text : BrewStyle.icon)
            Spacer()
            Button { withAnimation(.easeInOut(duration: 0.18)) { configuration.isOn.toggle() } } label: {
                Capsule().fill(configuration.isOn ? BrewStyle.gold : BrewStyle.toggleOff)
                    .frame(width: 38, height: 24)
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                        Circle().fill(BrewStyle.photoWhite).frame(width: 20, height: 20).padding(2)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(configuration.isOn ? "关闭" : "开启"))
        }
        .accessibilityRepresentation {
            Toggle(isOn: Binding(get: { configuration.isOn }, set: { configuration.isOn = $0 })) {
                configuration.label
            }.toggleStyle(.switch)
        }
    }
}
