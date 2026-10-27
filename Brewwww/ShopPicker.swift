import SwiftUI

struct ShopPicker: View {
    @EnvironmentObject private var store: BrewStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var search = ShopSearchModel.make()
    @State private var selected: ShopPlace?
    @State private var confirming = false
    @State private var confirmationTask: Task<Void, Never>?
    @State private var addingShop = false
    @State private var customName = ""
    @State private var customCity = ""
    @FocusState private var searchFocused: Bool
    let onSelect: (ShopPlace) -> Void

    init(current: ShopPlace, onSelect: @escaping (ShopPlace) -> Void) {
        _selected = State(initialValue: current.name.isEmpty ? nil : current)
        self.onSelect = onSelect
    }

    private var term: String { search.query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var myShops: [ShopPlace] { store.myShopPlaces.filter(matches) }
    private var recent: [ShopPlace] { store.recentShopPlaces.filter(matches) }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                header
                    .padding(.top, 18).padding(.bottom, 25)
                searchField
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        HStack {
                            sectionTitle("我的店")
                            Spacer()
                            Button { addingShop = true } label: {
                                Image(systemName: "plus").font(.system(size: 23)).foregroundStyle(BrewStyle.gold)
                                    .frame(width: 40, height: 40)
                            }
                            .accessibilityLabel("添加我的店").accessibilityIdentifier("shops.addCustom")
                        }
                        .padding(.bottom, myShops.isEmpty ? -18 : -12)
                        if !myShops.isEmpty { placesPanel(myShops, prefix: "saved") }
                        if !term.isEmpty {
                            searchResults
                        } else {
                            if !recent.isEmpty {
                                sectionTitle("上次的店")
                                placesPanel(Array(recent.prefix(3)), prefix: "recent", counts: true)
                            }
                            HStack {
                                sectionTitle("附近")
                                Spacer()
                                locateButton
                            }
                            .padding(.bottom, -10)
                            nearbyResults
                        }
                    }
                    .padding(.top, 15).padding(.bottom, 28)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
            }
            .frame(maxWidth: geometry.size.width >= 700 ? 640 : .infinity)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background { BrewBackground() }
        .foregroundStyle(BrewStyle.text)
        .font(BrewFont.body)
        .tint(BrewStyle.gold)
        .buttonStyle(BrewPressStyle())
        .task { search.start() }
        .task(id: search.searchKey) { await search.search() }
        .onDisappear { confirmationTask?.cancel(); search.stop() }
        .onChange(of: search.query) { _, _ in selected = nil }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && search.locationState == .denied { search.locate() }
        }
        .alert("添加我的店", isPresented: $addingShop) {
            TextField("店铺名称", text: $customName)
            TextField("城市（选填）", text: $customCity)
            Button("添加") {
                let place = ShopPlace(name: customName.trimmingCharacters(in: .whitespacesAndNewlines),
                                      city: customCity.trimmingCharacters(in: .whitespacesAndNewlines))
                guard !place.name.isEmpty else { return }
                store.saveShop(place)
                selected = place
                customName = ""; customCity = ""
            }
            .disabled(customName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("取消", role: .cancel) { customName = ""; customCity = "" }
        } message: { Text("也可以在搜索结果中收藏有定位的店铺。") }
    }

    private var header: some View {
        HStack {
            Button { confirmationTask?.cancel(); dismiss() } label: { RoundIcon(symbol: "xmark", size: 42) }
                .accessibilityLabel("取消选择店铺").accessibilityIdentifier("shops.cancel")
            Spacer()
            Text("选择店铺").font(.system(size: 22, weight: .semibold))
            Spacer()
            Button { confirm() } label: {
                if confirming { ProgressView().frame(width: 42, height: 42) }
                else { RoundIcon(symbol: "checkmark", active: selected != nil, size: 42) }
            }
            .disabled(selected == nil || confirming)
            .opacity(selected == nil ? 0.45 : 1)
            .accessibilityLabel("确认店铺").accessibilityIdentifier("shops.confirm")
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(BrewStyle.icon)
            TextField("搜索或输入店铺名...", text: $search.query)
                .focused($searchFocused)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { searchFocused = false }
                .accessibilityIdentifier("shops.search")
            if !search.query.isEmpty {
                Button { search.query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(BrewStyle.muted)
                }.accessibilityLabel("清除搜索")
            }
        }
        .padding(.horizontal, 16).frame(height: 48)
        .background(BrewStyle.panel, in: Capsule())
        .overlay(Capsule().stroke(BrewStyle.border, lineWidth: 1))
    }

    @ViewBuilder private var searchResults: some View {
        if !recent.isEmpty {
            sectionTitle("历史店铺")
            placesPanel(Array(recent.prefix(3)), prefix: "recent")
        }
        HStack { sectionTitle("搜索结果"); Spacer(); locateButton }
        if search.searching {
            ProgressView("正在搜索店铺…").frame(maxWidth: .infinity).padding(24)
        } else if let error = search.searchError {
            status(error, symbol: "wifi.exclamationmark")
            Button("重新搜索") { Task { await search.search(debounce: false) } }
        } else if search.results.isEmpty {
            status("没有找到这家店，试试加上城市或街道名称。", symbol: "magnifyingglass")
        } else {
            placesPanel(search.results, prefix: "result")
        }
        Button {
            selected = ShopPlace(name: term)
            searchFocused = false
        } label: {
            HStack {
                Image(systemName: "pencil")
                VStack(alignment: .leading, spacing: 5) {
                    Text("使用“\(term)”")
                    Text("手动店铺，城市可返回后填写").font(BrewFont.caption).foregroundStyle(BrewStyle.muted)
                }
                Spacer()
                if selected?.name == term && selected?.coordinate == nil { Image(systemName: "checkmark") }
            }.padding(16)
        }
        .background(BrewStyle.panel, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityIdentifier("shops.manual")
    }

    @ViewBuilder private var nearbyResults: some View {
        if search.loadingNearby {
            ProgressView("正在查找附近店铺…").frame(maxWidth: .infinity).padding(28)
        } else if !search.nearby.isEmpty {
            placesPanel(search.nearby, prefix: "nearby")
        } else {
            switch search.locationState {
            case .idle, .locating:
                status("正在获取当前位置…", symbol: "location")
            case .denied:
                status("未开启定位，仍可搜索或手动输入店铺。", symbol: "location.slash")
                Button("去设置开启定位") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            case .failed:
                status("暂时无法获取位置，可重试定位或直接搜索。", symbol: "location.slash")
            case .ready:
                status(search.nearbyError ?? "附近暂未找到店铺，试试按名称搜索。", symbol: "storefront")
                if search.nearbyError != nil { Button("重新加载") { search.refreshNearby() } }
            }
        }
    }

    private var locateButton: some View {
        Button { search.locate() } label: {
            HStack(spacing: 5) {
                Image(systemName: "location")
                Text(search.locationState == .locating ? "定位中" : "重新定位")
            }.font(.system(size: 12)).foregroundStyle(BrewStyle.gold)
                .padding(.vertical, 8)
        }
        .disabled(search.locationState == .locating)
        .accessibilityIdentifier("shops.locate")
    }

    private func placesPanel(_ places: [ShopPlace], prefix: String, counts: Bool = false) -> some View {
        BrewPanel {
            LazyVStack(spacing: 0) {
                ForEach(Array(places.enumerated()), id: \.element.id) { index, place in
                    HStack(spacing: 6) {
                        Button {
                            selected = place
                            searchFocused = false
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 7) {
                                    Text(place.name).font(.system(size: 17, weight: .semibold)).lineLimit(2)
                                    if !place.subtitle.isEmpty {
                                        Text(place.subtitle).font(.system(size: 13)).foregroundStyle(BrewStyle.muted).lineLimit(2)
                                    }
                                }
                                Spacer(minLength: 2)
                                if selected?.id == place.id {
                                    Image(systemName: "checkmark").foregroundStyle(BrewStyle.gold)
                                } else if counts {
                                    Text("\(store.records.filter { $0.shopPlace.id == place.id }.count)×")
                                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(BrewStyle.gold)
                                } else if let distance = place.distance(from: search.location) {
                                    Text(ShopSearchModel.distanceText(distance))
                                        .font(.system(size: 12)).foregroundStyle(BrewStyle.muted).fixedSize()
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .accessibilityIdentifier("shops.\(prefix).\(index)")
                        if prefix == "result" || prefix == "nearby" {
                            Button { store.saveShop(place) } label: {
                                Image(systemName: store.myShopPlaces.contains(where: { $0.id == place.id }) ? "star.fill" : "star")
                                    .font(.system(size: 14)).foregroundStyle(BrewStyle.gold)
                                    .frame(width: 28, height: 44)
                            }
                            .accessibilityLabel("收藏\(place.name)")
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                }
            }
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text).font(.system(size: 14, weight: .semibold)).foregroundStyle(BrewStyle.muted).padding(.leading, 4)
    }
    private func status(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol).font(.system(size: 13)).foregroundStyle(BrewStyle.muted)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12)
    }
    private func matches(_ place: ShopPlace) -> Bool {
        term.isEmpty || (place.name + place.subtitle).localizedCaseInsensitiveContains(term)
    }
    private func confirm() {
        guard let selected, !confirming else { return }
        confirming = true
        searchFocused = false
        confirmationTask = Task {
            let place = await search.resolveCity(for: selected)
            guard !Task.isCancelled else { return }
            onSelect(place)
            dismiss()
        }
    }
}
