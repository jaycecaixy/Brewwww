import SwiftUI
import ImageIO

struct RecordEditor: View {
    @EnvironmentObject private var store: BrewStore
    @Environment(\.brewLayout) private var layout
    @State private var draft: DrinkRecord
    @State private var newPhoto: UIImage?
    @State private var showDeleteConfirmation = false
    @State private var showDatePicker = false
    @State private var showShopPicker = false
    @State private var cutoutState: CutoutState = .idle
    @State private var cutoutAttempt = 0
    @State private var generatedSticker: UIImage?
    @State private var generatedStickerData: Data?
    @State private var useOriginalSticker = false
    @State private var showSaveError = false
    @FocusState private var focusedField: String?
    var onCancel: () -> Void
    var onSave: (DrinkRecord, UIImage?, Data?) throws -> Void
    var onDelete: (() -> Void)?

    init(record: DrinkRecord, photo: UIImage?, onCancel: @escaping () -> Void,
         onSave: @escaping (DrinkRecord, UIImage?, Data?) throws -> Void, onDelete: (() -> Void)?) {
        _draft = State(initialValue: record)
        _newPhoto = State(initialValue: photo)
        self.onCancel = onCancel
        self.onSave = onSave
        self.onDelete = onDelete
    }

    var body: some View {
        Group {
            if layout.tabletop {
                VStack(spacing: 0) {
                    let availableHeight = max(180, layout.size.height - layout.keyboardInset)
                    let previewHeight = layout.keyboardInset > 0 ? min(70, availableHeight * 0.24) : layout.size.height * 0.36
                    Text(onDelete == nil ? "添加记录" : "饮品详情")
                        .font(BrewFont.heading).padding(.top, 8)
                    stickerPreview(size: min(140, previewHeight * 0.78), compact: true)
                        .frame(maxWidth: .infinity)
                        .frame(height: previewHeight)
                    Color.clear.frame(height: layout.keyboardInset > 0 ? 10 : 24)
                    HStack(spacing: 0) {
                        if layout.leftHanded { actions }
                        ScrollViewReader { reader in
                            ScrollView { fields.padding(.horizontal, 18).frame(maxWidth: 650) }
                                .scrollDismissesKeyboard(.interactively)
                                .onChange(of: focusedField) { _, field in
                                    if let field { withAnimation(layout.animation) { reader.scrollTo(field, anchor: .center) } }
                                }
                                .onChange(of: layout.keyboardInset) { _, height in
                                    if height > 0, let field = focusedField {
                                        withAnimation(layout.animation) { reader.scrollTo(field, anchor: .center) }
                                    }
                                }
                        }
                        .frame(maxWidth: .infinity)
                        if !layout.leftHanded { actions }
                    }
                }
            } else {
                standardEditor
            }
        }
        .padding(.bottom, layout.keyboardInset)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("editor.layout")
        .accessibilityValue(layout.tabletop ? "tabletop" : layout.twoColumns ? "columns" : "stack")
        .task(id: cutoutAttempt) { await generateSticker() }
        .alert("保存失败", isPresented: $showSaveError) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text("请检查设备的可用存储空间后重试，当前编辑内容仍保留在这里。")
        }
        .sheet(isPresented: $showShopPicker) {
            ShopPicker(current: draft.shopPlace) { place in draft.selectShop(place) }
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
                .presentationBackground(.clear)
                .presentationCornerRadius(30)
        }
        .sheet(isPresented: $showDatePicker) {
            VStack(spacing: 16) {
                HStack {
                    Text("日期与时间").font(BrewFont.heading)
                    Spacer()
                    Button("完成") { showDatePicker = false }
                }
                DatePicker("日期与时间", selection: $draft.date)
                    .datePickerStyle(.graphical)
                    .environment(\.locale, Locale(identifier: "zh_CN"))
            }
            .padding(22)
            .presentationDetents([.medium, .large])
            .presentationBackground(BrewStyle.ink)
        }
        .confirmationDialog("删除这条饮品记录？", isPresented: $showDeleteConfirmation) {
            Button("删除记录", role: .destructive) { onDelete?() }
        }
    }

    private var standardEditor: some View {
        HStack(spacing: 0) {
            if layout.leftHanded { actions }
            VStack(spacing: 12) {
                Text(onDelete == nil ? "添加记录" : "饮品详情")
                    .font(BrewFont.heading).padding(.top, layout.titleTop)
                let split = layout.twoColumns && !layout.tabletop
                let arrangement = split ? AnyLayout(HStackLayout(alignment: .top, spacing: layout.book ? 32 : 25))
                                        : AnyLayout(VStackLayout(spacing: 12))
                ScrollView {
                    arrangement {
                        stickerPreview(size: split ? 180 : 155)
                            .frame(maxWidth: .infinity)
                            .frame(width: split ? (layout.book ? layout.bookLeadingWidth : layout.pageWidth * 0.36) : nil,
                                   height: split ? 290 : 255)
                        fields.frame(maxWidth: 560)
                    }
                    .padding(.top, 12)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .brewPagePadding()
            .frame(maxWidth: .infinity)
            if !layout.leftHanded { actions }
        }
    }

    private var fields: some View {
        VStack(spacing: 15) {
                    if layout.tabletop { cutoutControls }
                    Button { showDatePicker = true } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "calendar").foregroundStyle(BrewStyle.gold)
                            Text(draft.date.recordDateTime)
                                .font(.system(size: 15, weight: .semibold))
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.down").foregroundStyle(BrewStyle.placeholder)
                        }
                        .brewRow()
                    }

                    Button {
                        focusedField = nil
                        showShopPicker = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "storefront").foregroundStyle(BrewStyle.gold).frame(width: 20)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(draft.shop.isEmpty ? "店铺名..." : draft.shop)
                                    .foregroundStyle(draft.shop.isEmpty ? BrewStyle.muted : BrewStyle.text)
                                if let address = draft.shopAddress, !address.isEmpty {
                                    Text(address).font(BrewFont.caption).foregroundStyle(BrewStyle.muted).lineLimit(1)
                                }
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").foregroundStyle(BrewStyle.placeholder)
                        }.brewRow()
                    }
                    .accessibilityIdentifier("field.storefront")
                    field("城市...", symbol: "mappin", text: Binding(get: { draft.city }, set: { city in
                        if city != draft.city {
                            draft.city = city
                            draft.latitude = nil; draft.longitude = nil; draft.shopAddress = nil
                        }
                    }))
                    HStack(spacing: 8) {
                        field("饮品名...", symbol: "cup.and.saucer", text: $draft.name)
                        Button { draft.favorite.toggle() } label: {
                            Image(systemName: draft.favorite ? "star.fill" : "star")
                                .font(.title3)
                                .foregroundStyle(draft.favorite ? BrewStyle.gold : BrewStyle.placeholder)
                                .frame(width: 52, height: 62)
                                .background(BrewStyle.panel, in: RoundedRectangle(cornerRadius: 18))
                        }
                    }
                    if !store.recentNames.isEmpty {
                        BrewPanel {
                            VStack(alignment: .leading, spacing: 9) {
                                Text("最近使用：").font(.caption).foregroundStyle(BrewStyle.muted)
                                ScrollView(.horizontal) {
                                    HStack {
                                        ForEach(store.recentNames.prefix(5), id: \.self) { name in
                                            Button(name) { draft.name = name }
                                                .font(.subheadline)
                                                .padding(.horizontal, 12).padding(.vertical, 7)
                                                .overlay(Capsule().stroke(BrewStyle.muted, lineWidth: 1))
                                        }
                                    }
                                }
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    BrewPanel {
                        HStack(alignment: .top) {
                            Image(systemName: "pencil").foregroundStyle(BrewStyle.gold)
                            TextField("备注（选填）...", text: $draft.note, axis: .vertical)
                                .lineLimit(3...6)
                                .accessibilityIdentifier("editor.note")
                                .focused($focusedField, equals: "note")
                        }
                        .padding(17)
                    }
                    .id("note")
                    if onDelete != nil {
                        Button(role: .destructive) { showDeleteConfirmation = true } label: {
                            Label("删除这条记录", systemImage: "trash")
                                .frame(maxWidth: .infinity).padding(.vertical, 17)
                        }
                    }

        }
        .padding(.bottom, 30)
    }

    private var actions: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 0)
            Button(action: onCancel) { RoundIcon(symbol: "xmark") }
                .accessibilityLabel("取消编辑").accessibilityIdentifier("editor.cancel")
            Button(action: saveRecord) {
                RoundIcon(symbol: "checkmark", active: true)
            }
            .accessibilityLabel("保存记录").accessibilityIdentifier("editor.save")
            .disabled(!canSave)
            .opacity(canSave ? 1 : 0.4)
            Spacer(minLength: 0)
        }
        .frame(width: 66)
    }

    private enum CutoutState: Equatable {
        case idle, processing, ready, failed(String)
    }

    private var canSave: Bool {
        !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            (cutoutState != .processing || useOriginalSticker)
    }

    private var displayedCutout: UIImage? {
        useOriginalSticker ? nil : (generatedSticker ?? store.sticker(for: draft))
    }

    private func stickerPreview(size: CGFloat, compact: Bool = false) -> some View {
        VStack(spacing: 13) {
            DrinkSticker(image: newPhoto ?? store.image(for: draft), cutout: displayedCutout, size: size)
                .overlay {
                    if cutoutState == .processing && !useOriginalSticker {
                        ProgressView().padding(10).background(.ultraThinMaterial, in: Circle())
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(displayedCutout == nil ? "原照片" : "主体贴纸")
                .accessibilityIdentifier(displayedCutout == nil ? "sticker.original" : "sticker.cutout")
            if !compact { cutoutControls }
        }
    }

    @ViewBuilder private var cutoutControls: some View {
        if cutoutState != .idle {
            VStack(spacing: 8) {
                Group {
                    if useOriginalSticker {
                        Text("已选择原图")
                    } else {
                        switch cutoutState {
                        case .processing: Text("正在提取主体…")
                        case .ready: Text("主体贴纸已生成")
                        case .failed(let message): Text(message)
                        case .idle: EmptyView()
                        }
                    }
                }
                .font(BrewFont.caption)
                .foregroundStyle(BrewStyle.muted)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("cutout.status")
                HStack(spacing: 18) {
                    if cutoutState == .ready {
                        Button(useOriginalSticker ? "使用主体贴纸" : "使用原图") {
                            withAnimation(layout.animation) { useOriginalSticker.toggle() }
                        }
                        .accessibilityIdentifier("cutout.toggle")
                    } else if cutoutState == .processing && !useOriginalSticker {
                        Button("使用原图") { useOriginalSticker = true }
                    } else if case .failed = cutoutState, !useOriginalSticker {
                        Button("使用原图") { useOriginalSticker = true }
                            .accessibilityIdentifier("cutout.useOriginal")
                    }
                    if cutoutState != .processing {
                        Button("重新抠图") {
                            useOriginalSticker = false
                            cutoutAttempt += 1
                        }
                        .accessibilityIdentifier("cutout.retry")
                    }
                }
                .font(BrewFont.caption)
                .foregroundStyle(BrewStyle.gold)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func generateSticker() async {
        if cutoutAttempt == 0, newPhoto == nil, store.sticker(for: draft) != nil {
            cutoutState = .ready
            return
        }
        guard let source = newPhoto ?? store.image(for: draft) else { return }
        guard let cgImage = source.cgImage else {
            cutoutState = .failed(SubjectCutoutError.invalidImage.localizedDescription)
            return
        }
        cutoutState = .processing
        do {
            let result = try await SubjectCutoutService.shared.makeSticker(from: cgImage,
                                                                           orientation: source.visionOrientation)
            try Task.checkCancellation()
            guard let image = UIImage(data: result.pngData) else { throw SubjectCutoutError.renderingFailed }
            generatedSticker = image
            generatedStickerData = result.pngData
            cutoutState = .ready
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            let message = (error as? SubjectCutoutError)?.localizedDescription
                ?? "这张照片暂时无法抠图，可重试或使用原图。"
            cutoutState = .failed(message)
        }
    }

    private func saveRecord() {
        var saved = draft
        if useOriginalSticker || displayedCutout == nil { saved.stickerFile = nil }
        do {
            try onSave(saved, newPhoto, useOriginalSticker ? nil : generatedStickerData)
        } catch {
            showSaveError = true
        }
    }

    private func field(_ placeholder: String, symbol: String, text: Binding<String>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).foregroundStyle(BrewStyle.gold).frame(width: 20)
            TextField(placeholder, text: text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("field.\(symbol)")
                .focused($focusedField, equals: symbol)
        }
        .brewRow()
        .id(symbol)
    }
}

extension UIImage {
    var visionOrientation: CGImagePropertyOrientation {
        switch imageOrientation {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}
