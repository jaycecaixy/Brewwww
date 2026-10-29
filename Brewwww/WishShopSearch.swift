import SwiftUI

struct WishShopSearch: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var search = ShopSearchModel.make()
    @State private var selected: ShopPlace?
    @State private var saving = false
    @State private var error: String?
    @State private var task: Task<Void, Never>?
    @FocusState private var focused: Bool
    var onSave: (ShopPlace) throws -> Void
    private var emptyQuery: Bool { search.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var places: [ShopPlace] { emptyQuery ? search.nearby : search.results }

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                BrewGlassButton(symbol: "xmark", size: 38, label: "取消添加想喝店铺", identifier: "wish.cancel") {
                    task?.cancel(); dismiss()
                }
                Spacer()
                Text("添加想喝的店").font(BrewFont.heading)
                Spacer()
                BrewGlassButton(symbol: "checkmark", size: 38, loading: saving, prominent: selected != nil,
                                label: "保存想喝店铺", identifier: "wish.confirm") {
                    confirm()
                }
                .disabled(selected?.coordinate == nil || saving)
            }
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass").foregroundStyle(BrewStyle.icon)
                TextField("搜索咖啡店或地址…", text: $search.query)
                    .focused($focused).autocorrectionDisabled().textInputAutocapitalization(.never)
                    .submitLabel(.search).onSubmit { focused = false }
                    .accessibilityIdentifier("wish.search")
                if !search.query.isEmpty {
                    Button { search.query = "" } label: { Image(systemName: "xmark.circle.fill") }
                }
            }
            .padding(.horizontal, 14).frame(height: 46)
            .background(.thinMaterial, in: Capsule())
            .overlay(Capsule().stroke(BrewStyle.border, lineWidth: 1))
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(emptyQuery ? "附近咖啡店" : "搜索结果").font(BrewFont.caption).foregroundStyle(BrewStyle.muted)
                        Spacer()
                        if emptyQuery {
                            Button { search.locate() } label: { Label("定位", systemImage: "location") }.font(BrewFont.caption)
                        }
                    }.padding(.bottom, 3)
                    if search.searching || (emptyQuery && search.loadingNearby) {
                        ProgressView("正在查找店铺…").padding(20).frame(maxWidth: .infinity)
                    } else if places.isEmpty {
                        Text(emptyQuery ? "可直接输入咖啡店名或地址搜索。" : search.searchError ?? "没有找到店铺，试试加上城市或街道。")
                            .font(BrewFont.caption).foregroundStyle(BrewStyle.muted).padding(.vertical, 14)
                    }
                    ForEach(Array(places.enumerated()), id: \.element.id) { index, place in
                        Button { selected = place; focused = false } label: {
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(place.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(BrewStyle.text)
                                    Text(place.subtitle).font(BrewFont.caption).foregroundStyle(BrewStyle.muted).lineLimit(2)
                                }
                                Spacer()
                                Image(systemName: selected?.id == place.id ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selected?.id == place.id ? BrewStyle.gold : BrewStyle.icon)
                            }.padding(13).contentShape(Rectangle())
                        }
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 17))
                        .accessibilityIdentifier("wish.result.\(index)")
                        .accessibilityValue(selected?.id == place.id ? "selected" : "unselected")
                    }
                    if let error { Text(error).font(BrewFont.caption).foregroundStyle(BrewStyle.orange) }
                }
            }.scrollDismissesKeyboard(.interactively)
        }
        .padding(.horizontal, 18).padding(.top, 22).padding(.bottom, 14)
        .foregroundStyle(BrewStyle.text).tint(BrewStyle.gold)
        .task { search.start() }
        .task(id: search.searchKey) { await search.search() }
        .onChange(of: search.query) { _, _ in selected = nil; error = nil }
        .onDisappear { task?.cancel(); search.stop() }
        .interactiveDismissDisabled(saving)
        .accessibilityElement(children: .contain).accessibilityIdentifier("wish.sheet")
    }
    private func confirm() {
        guard let selected, selected.coordinate != nil, !saving else { return }
        saving = true; focused = false
        task = Task { @MainActor in
            let resolved = await search.resolveCity(for: selected)
            guard !Task.isCancelled else { return }
            do { try onSave(resolved); dismiss() }
            catch { self.error = "保存失败，请检查设备可用空间后重试。"; saving = false }
        }
    }
}
