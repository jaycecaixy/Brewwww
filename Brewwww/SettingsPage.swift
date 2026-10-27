import SwiftUI
import UIKit

struct SettingsPage: View {
    @EnvironmentObject private var store: BrewStore
    @Environment(\.brewLayout) private var layout
    @AppStorage("profileName") private var profileName = ""
    @AppStorage("mondayFirst") private var mondayFirst = false
    @AppStorage("haptics") private var haptics = true
    @AppStorage("reduceMotion") private var reduceMotion = false
    @AppStorage("autoTheme") private var autoTheme = true
    @AppStorage("stampStyle") private var stampStyle = 1
    @AppStorage("passportStyle") private var passportStyle = 0
    @AppStorage("handedness") private var handedness = "right"
    @AppStorage("joinedAt") private var joinedAt = Date().timeIntervalSince1970
    @State private var page: Page = .root
    @State private var shopName = ""
    @State private var shopCity = ""
    @State private var showAddShop = false
    @State private var showDelete = false
    @State private var showCloudInfo = false
    @State private var unavailableFeature: String? = nil

    private enum Page { case root, profile, general, preferences, appearance, faq }

    var body: some View {
        VStack(spacing: 12) {
            Text(title).font(BrewFont.heading).padding(.top, layout.titleTop)
            ScrollView {
                VStack(spacing: 11) {
                    switch page {
                    case .root: rootContent
                    case .profile: profileContent
                    case .general: generalContent
                    case .preferences: preferencesContent
                    case .appearance: appearanceContent
                    case .faq: faqContent
                    }
                }
                .id(page)
                .transition(.move(edge: .trailing).combined(with: .opacity))
                .padding(.top, 32)
                .padding(.bottom, 30)
            }
            if page == .root { Text("版本 1.0").font(.caption).foregroundStyle(BrewStyle.muted) }
        }
        .brewPagePadding()
        .animation(layout.animation, value: page)
        .overlay(alignment: .topTrailing) {
            if page != .root {
                Button { page = .root } label: { RoundIcon(symbol: "chevron.left") }
                    .padding(.top, 70).padding(.trailing, 14)
            }
        }
        .alert("iCloud 同步尚未配置", isPresented: $showCloudInfo) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text("当前版本把照片与记录保存在这台设备。连接 Apple 开发者团队并配置 CloudKit 后才能启用跨设备同步。")
        }
        .alert("删除全部记录？", isPresented: $showDelete) {
            Button("删除", role: .destructive) { store.deleteAll() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("这会从当前设备删除所有饮品记录和照片。")
        }
        .alert("添加自定义店铺", isPresented: $showAddShop) {
            TextField("店铺昵称", text: $shopName)
            TextField("城市名称", text: $shopCity)
            Button("完成") {
                let name = shopName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty { store.customShops[name] = shopCity }
                shopName = ""; shopCity = ""
            }
            Button("取消", role: .cancel) {}
        }
        .alert("暂未提供", isPresented: Binding(get: { unavailableFeature != nil },
                                              set: { if !$0 { unavailableFeature = nil } })) {
            Button("知道了", role: .cancel) { unavailableFeature = nil }
        } message: {
            Text(unavailableFeature ?? "")
        }
    }

    private var title: String {
        switch page {
        case .root: "设置"
        case .profile: "个人信息"
        case .general: "通用"
        case .preferences: "偏好设置"
        case .appearance: "外观"
        case .faq: "常见问题"
        }
    }

    private var rootContent: some View {
        Group {
            row("个人信息", "person.crop.rectangle") { page = .profile }
            row("通用", "wrench.adjustable") { page = .general }
            row("外观", "paintpalette") { page = .appearance }
            row("请我们喝杯咖啡", "heart") {
                unavailableFeature = "这项支持入口需要原应用的购买服务，复刻版没有接入支付。"
            }
            row("常见问题", "questionmark.circle") { page = .faq }
            row("联系我们", "hand.thumbsup") {
                unavailableFeature = "还没有配置开发者的联系邮箱。"
            }
        }
    }

    private var profileContent: some View {
        Group {
            BrewPanel {
                VStack(alignment: .leading, spacing: 15) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("姓名 ✎").font(.caption).foregroundStyle(BrewStyle.muted)
                            TextField("设置姓名", text: $profileName).font(.title3.bold())
                            Text("加入时间").font(.caption).foregroundStyle(BrewStyle.muted).padding(.top, 16)
                            Text(Date(timeIntervalSince1970: joinedAt).formatted(.dateTime.year().month().day()))
                                .font(.headline)
                        }
                        Spacer(minLength: 2)
                        VStack {
                            Text("ISSUED DATE").font(.system(size: 11, weight: .bold))
                            Text(Date(timeIntervalSince1970: joinedAt).formatted(.dateTime.month().day().year()))
                                .font(.system(size: 11, weight: .bold))
                            Text("BREWWWW!").font(.system(size: 11, weight: .bold))
                        }
                        .foregroundStyle(BrewStyle.gold)
                        .frame(width: 112, height: 112)
                        .overlay(Circle().stroke(BrewStyle.gold, lineWidth: 2))
                        .rotationEffect(.degrees(-12))
                    }
                    HStack {
                        metric("印章", store.stampCount)
                        metric("杯", store.records.count)
                        metric("店铺", store.shops.count)
                        metric("城市", store.cities.count)
                    }
                    Text("BREWPORT<<<<<<<<<<<<<<<<<<<<<<<<<<")
                        .font(.system(size: 9, design: .monospaced)).foregroundStyle(BrewStyle.muted)
                }
                .padding(20)
            }
            Button { showCloudInfo = true } label: {
                VStack(alignment: .leading, spacing: 5) {
                    HStack { Text("iCloud"); Spacer(); Image(systemName: "circle") }
                    Text("当前记录保存在此设备中。点此了解同步配置。")
                        .font(.caption).foregroundStyle(BrewStyle.muted)
                }
                .brewRow()
            }
            Button(role: .destructive) { showDelete = true } label: {
                Text("删除账户").font(.caption).frame(maxWidth: .infinity).padding(.top, 20)
            }
        }
    }

    private func metric(_ title: String, _ count: Int) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(BrewStyle.muted)
            Text("\(count)").font(.title3.bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var generalContent: some View {
        Group {
            row("偏好设置", "slider.horizontal.3") { page = .preferences }
            row("添加自定义店铺", "storefront") { showAddShop = true }
            row("通知设置", "bell") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            row("语言 · 简体中文", "character.bubble") {
                unavailableFeature = "当前版本仅提供简体中文。"
            }
            row("隐私政策", "hand.raised") {
                unavailableFeature = "发布前需要为这个新应用编写自己的隐私政策。记录与照片目前只保存在本机。"
            }
            row("使用条款", "doc.text") {
                unavailableFeature = "发布前需要为这个新应用编写自己的使用条款。"
            }
        }
    }

    private var preferencesContent: some View {
        Group {
            toggle("每周从周一开始", $mondayFirst)
            toggle("触觉反馈", $haptics)
            toggle("减弱动态效果", $reduceMotion)
            toggle("自动主题", $autoTheme)
            Picker("持握方式", selection: $handedness) {
                Text("右手").tag("right")
                Text("左手").tag("left")
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("settings.handedness")
            Text("展开时并排显示内容；半折叠横放时，上方看照片，下方填写记录。")
                .font(BrewFont.caption).foregroundStyle(BrewStyle.muted)
        }
    }

    private var appearanceContent: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("5 种印章样式").font(.subheadline).foregroundStyle(BrewStyle.muted)
            HStack {
                ForEach(0..<5) { index in
                    Button { stampStyle = index } label: {
                        Image(systemName: ["seal", "seal.fill", "star.circle", "heart.circle", "cup.and.saucer"][index])
                            .font(.system(size: 25))
                            .frame(maxWidth: .infinity).frame(height: 65)
                            .background(stampStyle == index ? BrewStyle.gold : BrewStyle.panel)
                            .foregroundStyle(stampStyle == index ? BrewStyle.confirmation : BrewStyle.gold)
                            .clipShape(RoundedRectangle(cornerRadius: 15))
                    }
                }
            }
            Text("6 种护照页纹理").font(.subheadline).foregroundStyle(BrewStyle.muted)
                .padding(.top, 20)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3)) {
                ForEach(0..<6) { index in
                    Button { passportStyle = index } label: {
                        Image(index < 3 ? "PaperPreview\(index + 1)" : "PaperReference")
                            .resizable(resizingMode: .tile)
                            .clipShape(RoundedRectangle(cornerRadius: 15))
                            .frame(height: 95)
                            .overlay(RoundedRectangle(cornerRadius: 15)
                                .stroke(passportStyle == index ? BrewStyle.gold : BrewStyle.panelLight, lineWidth: 4))
                    }
                }
            }
        }
    }

    private var faqContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("如何添加记录？").font(.headline)
            Text("点页面右下角的 +，拍照或选择照片，再填写饮品名称、店铺和城市。")
            Text("记录保存在哪里？").font(.headline)
            Text("目前保存在此设备的 App 数据目录。")
        }
        .foregroundStyle(BrewStyle.text)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 15) {
                Image(systemName: symbol).foregroundStyle(BrewStyle.gold).frame(width: 22)
                Text(title).foregroundStyle(BrewStyle.text)
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(BrewStyle.muted)
            }
            .brewRow()
        }
        .accessibilityIdentifier("settings.\(title)")
    }

    private func toggle(_ title: String, _ binding: Binding<Bool>) -> some View {
        Toggle(title, isOn: binding)
            .toggleStyle(BrewToggleStyle())
            .brewRow()
    }
}
