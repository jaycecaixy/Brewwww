import SwiftUI
import ImageIO
import PhotosUI

private struct EditorPhotoAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? { nil }
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

enum PhotoTimestamp {
    /// Inspect the original bytes before UIImage decoding/re-encoding can strip
    /// the photo's capture timestamp and its UTC offset.
    static func captureDate(in data: Data) -> Date? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else { return nil }
        return captureDate(metadata: properties)
    }

    static func captureDate(metadata: [String: Any]) -> Date? {
        let exif = metadata[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
        let candidates = [
            (kCGImagePropertyExifDateTimeOriginal, kCGImagePropertyExifOffsetTimeOriginal),
            (kCGImagePropertyExifDateTimeDigitized, kCGImagePropertyExifOffsetTimeDigitized)
        ]
        for (dateKey, offsetKey) in candidates {
            if let value = exif[dateKey as String] as? String,
               let date = parse(value, offset: exif[offsetKey as String] as? String) { return date }
        }
        let tiff = metadata[kCGImagePropertyTIFFDictionary as String] as? [String: Any]
        if let value = tiff?[kCGImagePropertyTIFFDateTime as String] as? String {
            return parse(value, offset: nil)
        }
        return nil
    }

    private static func parse(_ value: String, offset: String?) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.isLenient = false
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
        if let offset, !offset.isEmpty {
            formatter.dateFormat = "yyyy:MM:dd HH:mm:ssXXXXX"
            return formatter.date(from: cleaned + offset)
        }
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.date(from: cleaned)
    }
}

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
    @State private var showPhotoOptions = false
    @State private var showPhotoPicker = false
    @State private var showCamera = false
    @State private var selectedPhoto: PhotosPickerItem?
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
        .ignoresSafeArea(.container, edges: layout.keyboardInset > 0 ? [] : .bottom)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("editor.layout")
        .accessibilityValue(layout.tabletop ? "tabletop" : layout.twoColumns ? "columns" : "stack")
        .overlayPreferenceValue(EditorPhotoAnchorKey.self) { anchor in
            GeometryReader { geometry in
                if let anchor {
                    photoOptions(anchor: geometry[anchor], in: geometry.size)
                }
            }
        }
        .task {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--fold-audit"),
               ProcessInfo.processInfo.arguments.contains("--audit-keyboard") {
                try? await Task.sleep(for: .milliseconds(300))
                focusedField = "cup.and.saucer"
            }
            #endif
        }
        .task(id: cutoutAttempt) { await generateSticker() }
        .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhoto, matching: .images,
                      preferredItemEncoding: .current)
        .task(id: selectedPhoto) {
            guard let item = selectedPhoto,
                  let data = try? await item.loadTransferable(type: Data.self), !Task.isCancelled,
                  let image = UIImage(data: data) else { return }
            replacePhoto(image, captureDate: PhotoTimestamp.captureDate(in: data))
            selectedPhoto = nil
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image, captureDate in
                showCamera = false
                if let image { replacePhoto(image, captureDate: captureDate) }
            }.ignoresSafeArea()
        }
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
                .contentMargins(.bottom, 24, for: .scrollContent)
                .accessibilityIdentifier("editor.scroll")
            }
            .padding(.leading, layout.pageInsets.leading)
            .padding(.trailing, layout.pageInsets.trailing)
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
                    .accessibilityIdentifier("editor.date")
                    .accessibilityValue(String(draft.date.timeIntervalSince1970))

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
                        .accessibilityIdentifier("editor.delete")
                    }

        }
        .padding(.bottom, 30)
    }

    private var actions: some View {
        GeometryReader { geometry in
            let frame = geometry.frame(in: .named("brewRoot"))
            let systemAxis = layout.sidebarAxis - frame.minX
            VStack(spacing: 12) {
                BrewGlassButton(symbol: "xmark", label: "取消编辑", identifier: "editor.cancel", action: onCancel)
                BrewGlassButton(symbol: "checkmark", label: "保存记录", identifier: "editor.save", action: saveRecord)
                    .disabled(!canSave).opacity(canSave ? 1 : 0.4)
            }
            .frame(width: 46, height: 104)
            .position(x: systemAxis >= 0 && systemAxis <= frame.width ? systemAxis : frame.width / 2,
                      y: layout.utilityCenterY(preferred: frame.midY, height: 104, within: frame) - frame.minY)
        }.frame(width: 66)
    }

    private enum CutoutState: Equatable {
        case idle, processing, ready, failed(String)
    }

    private var canSave: Bool {
        !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            (cutoutState != .processing || useOriginalSticker)
    }

    private var displayedCutout: UIImage? {
        useOriginalSticker ? nil : (generatedSticker ?? (newPhoto == nil ? store.sticker(for: draft) : nil))
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
                .overlay(alignment: .bottomTrailing) {
                    Button {
                        focusedField = nil
                        showPhotoOptions.toggle()
                    } label: {
                        Image(systemName: "camera.fill").font(.system(size: compact ? 12 : 16))
                            .foregroundStyle(BrewStyle.text).padding(compact ? 8 : 11)
                            .background(.regularMaterial, in: Circle())
                    }.accessibilityLabel("添加或更换饮品照片").accessibilityIdentifier("editor.photo")
                    .anchorPreference(key: EditorPhotoAnchorKey.self, value: .bounds) { $0 }
                }
            if !compact { cutoutControls }
        }
    }

    private func photoOptions(anchor: CGRect, in size: CGSize) -> some View {
        let hasCamera = UIImagePickerController.isSourceTypeAvailable(.camera)
        let width: CGFloat = 190
        let height: CGFloat = hasCamera ? 100 : 50
        let x = min(max(width / 2 + 12, anchor.midX), max(width / 2 + 12, size.width - width / 2 - 12))
        let below = anchor.maxY + 8 + height / 2
        let y = below + height / 2 <= size.height - 12 ? below : anchor.minY - 8 - height / 2
        return ZStack(alignment: .topLeading) {
            Color.clear.contentShape(Rectangle())
                .onTapGesture { showPhotoOptions = false }
                .accessibilityLabel("关闭照片选项")
                .accessibilityIdentifier("editor.photo.dismiss")
                .accessibilityAddTraits(.isButton)
            VStack(spacing: 0) {
                if hasCamera {
                    photoOption("拍照", symbol: "camera", identifier: "editor.photo.camera") {
                        showPhotoOptions = false
                        showCamera = true
                    }
                    Divider()
                }
                photoOption("从相册选择", symbol: "photo", identifier: "editor.photo.library") {
                    showPhotoOptions = false
                    showPhotoPicker = true
                }
            }
            .frame(width: width, height: height)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
            .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
            .position(x: x, y: y)
        }
        // Keep dismissal out of the modal presentation lifecycle. Hit testing
        // changes with the state, so there is no closing animation/cooldown
        // that can consume a subsequent tap on the photo button.
        .opacity(showPhotoOptions ? 1 : 0)
        .allowsHitTesting(showPhotoOptions)
        .accessibilityHidden(!showPhotoOptions)
        .transaction { $0.animation = nil }
        .accessibilityAction(.escape) { showPhotoOptions = false }
    }

    private func photoOption(_ title: String, symbol: String, identifier: String,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 16))
                .foregroundStyle(BrewStyle.text)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
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

    private func replacePhoto(_ image: UIImage, captureDate: Date?) {
        if onDelete == nil { draft.date = captureDate ?? Date() }
        newPhoto = image; generatedSticker = nil; generatedStickerData = nil
        useOriginalSticker = false; cutoutState = .idle; cutoutAttempt += 1
    }

    private func saveRecord() {
        guard canSave else { return }
        focusedField = nil
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
