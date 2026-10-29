import SwiftUI

private struct CalendarCornerCut: Shape {
    var hitSlop: CGFloat = 0
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            if hitSlop == 0 {
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            } else {
                path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                                  control: CGPoint(x: rect.midX - hitSlop, y: rect.midY - hitSlop))
            }
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}

private struct CalendarModeBadgeStyle: ButtonStyle {
    @Environment(\.brewLayout) private var layout
    @AppStorage("haptics") private var haptics = true
    @AppStorage(BrewHapticStrength.storageKey) private var strength = BrewHapticStrength.defaultValue

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 1.18 : 1, anchor: .bottomTrailing)
            .animation(layout.reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.65),
                       value: configuration.isPressed)
            .frame(width: 44, height: 44, alignment: .bottomTrailing)
            .clipShape(UnevenRoundedRectangle(bottomTrailingRadius: layout.expanded ? 27 : 19))
            .contentShape(CalendarCornerCut(hitSlop: 2))
            .sensoryFeedback(strength.pressFeedback, trigger: configuration.isPressed) { _, pressed in
                haptics && pressed
            }
    }
}

private struct CalendarEntranceReadyKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var calendarEntranceReady: Bool {
        get { self[CalendarEntranceReadyKey.self] }
        set { self[CalendarEntranceReadyKey.self] = newValue }
    }
}

/// Calendar arithmetic is shared by swipes, accessibility actions and month/week menus.
enum BrewCalendarPaging {
    static func shifted(_ date: Date, by offset: Int, weekMode: Bool, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: weekMode ? .weekOfYear : .month, value: offset, to: date) ?? date
    }
    static func days(in date: Date, weekMode: Bool, mondayFirst: Bool, calendar original: Calendar = .current) -> [Date?] {
        var calendar = original
        calendar.firstWeekday = mondayFirst ? 2 : 1
        if weekMode {
            guard let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start else { return [] }
            return (0..<7).map { calendar.date(byAdding: .day, value: $0, to: start) }
        }
        guard let start = calendar.dateInterval(of: .month, for: date)?.start,
              let range = calendar.range(of: .day, in: .month, for: date) else { return [] }
        let offset = (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7
        return Array(repeating: nil, count: offset) + range.map { calendar.date(byAdding: .day, value: $0 - 1, to: start) }
    }
}

enum BrewCalendarPageMotion {
    static func centerOffset(to offset: Int, spacing: CGFloat, height: (Int) -> CGFloat) -> CGFloat {
        guard offset != 0 else { return 0 }
        let direction = offset > 0 ? 1 : -1
        var distance: CGFloat = 0
        for step in 1...abs(offset) {
            distance += (height((step - 1) * direction) + height(step * direction)) / 2 + spacing
        }
        return CGFloat(direction) * distance
    }

    static func edgeAmount(distance: CGFloat, stride: CGFloat) -> CGFloat {
        let progress = min(1, abs(distance) / max(1, stride))
        return progress * progress * (3 - 2 * progress)
    }
}

private struct CalendarViewportClip: Shape {
    var topOverflow: CGFloat
    var bottomOverflow: CGFloat = 0
    func path(in rect: CGRect) -> Path {
        Path(CGRect(x: rect.minX, y: rect.minY - topOverflow,
                    width: rect.width, height: rect.height + topOverflow + bottomOverflow))
    }
}

/// Dragging changes the outer transform; rebuild dates and stickers only when
/// the period, records or layout actually changes.
private struct CalendarPageIdentity: Equatable {
    var date: Date
    var month: Date
    var selectedDate: Date
    var active: Bool
    var weekMode: Bool
    var mondayFirst: Bool
    var width: CGFloat
    var layout: BrewLayout
    var records: [DrinkRecord]
    var entranceReady: Bool
}

private struct RetainedCalendarPage<Content: View>: View, Equatable {
    var identity: CalendarPageIdentity
    @ViewBuilder var content: () -> Content
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.identity == rhs.identity }
    var body: some View { content() }
}

struct CalendarPager: View {
    @EnvironmentObject private var store: BrewStore
    @Environment(\.brewLayout) private var layout
    @Environment(\.calendarEntranceReady) private var entranceReady
    @AppStorage("mondayFirst") private var mondayFirst = false
    @Binding var month: Date
    @Binding var selectedDate: Date
    @Binding var weekMode: Bool
    var width: CGFloat
    var viewportWidth: CGFloat
    var onRecord: (DrinkRecord) -> Void
    var onToggleMode: () -> Void
    private let modeFooterHeight: CGFloat = 16
    private struct PageDrag {
        var translation = CGSize.zero
        var vertical: Bool?
    }
    private struct PageSlot: Identifiable {
        var date: Date
        var offset: Int
        var id: Date { date }
    }
    @GestureState private var drag = PageDrag()
    @State private var settlingVertically = false
    @State private var settling = CGSize.zero
    @State private var changingPage = false
    @State private var settleTask: Task<Void, Never>?
    @State private var pendingDate: Date?
    @State private var fadeProgress: CGFloat = 0
    @State private var fadeDirection = 1

    private var anchor: Date { weekMode ? selectedDate : month }
    private var expanded: Bool { layout.expanded }
    private var cellWidth: CGFloat { (width - (expanded ? 36 : 30) - 6 * (expanded ? 8 : 6)) / 7 }
    private var cellHeight: CGFloat { cellWidth / (expanded ? 0.85 : 0.88) }
    private var panelHeight: CGFloat { calendarHeight(anchor) }
    private var pageHeight: CGFloat { panelHeight + (expanded ? 80 : 72) }
    private var foldedPaging: Bool { layout.hinge == .closed || (layout.hinge == .unavailable && !expanded) }
    private var fadedPanelHeight: CGFloat {
        panelHeight + ((pendingDate.map { calendarHeight($0) } ?? panelHeight) - panelHeight) * fadeProgress
    }
    private var viewportHeight: CGFloat {
        if layout.landscape { return layout.size.height }
        if foldedPaging { return fadedPanelHeight + (expanded ? 80 : 72) }
        let offset = translation.width < 0 ? 1 : -1
        let progress = min(1, abs(translation.width) / horizontalStride)
        return pageHeight + (height(at: offset) - pageHeight) * progress
    }
    private var vertical: Bool { changingPage ? settlingVertically : (drag.vertical ?? layout.landscape) }
    private var translation: CGSize { changingPage ? settling : drag.translation }
    private var horizontalStride: CGFloat { width + (expanded ? 56 : 24) }
    private var previewRadius: Int {
        guard layout.landscape && weekMode else { return 2 }
        return max(2, Int(ceil(layout.size.height / (2 * (pageHeight + 34))))) + 1
    }
    private var pageSlots: [PageSlot] {
        (-previewRadius...previewRadius).map { offset in
            let date = BrewCalendarPaging.shifted(anchor, by: offset, weekMode: weekMode)
            let period = weekMode ? Calendar.current.startOfDay(for: date)
                : (Calendar.current.dateInterval(of: .month, for: date)?.start ?? date)
            return PageSlot(date: period, offset: offset)
        }
    }
    private func height(at offset: Int) -> CGFloat {
        calendarHeight(BrewCalendarPaging.shifted(anchor, by: offset, weekMode: weekMode)) + (expanded ? 80 : 72)
    }
    private func pageOffset(_ offset: Int) -> CGFloat {
        vertical ? BrewCalendarPageMotion.centerOffset(to: offset, spacing: 34, height: height(at:))
            : CGFloat(offset) * horizontalStride
    }
    private var pagingBottomOverflow: CGFloat {
        guard !foldedPaging, !vertical else { return 0 }
        return max(0, [-1, 0, 1].map { height(at: $0) }.max()! - viewportHeight)
    }

    var body: some View {
        Group {
            if foldedPaging {
                foldedPage
            } else {
                ZStack {
                    // The incoming page keeps its identity when it becomes
                    // current; its stickers and corner must not be recreated.
                    ForEach(pageSlots) { slot in
                        let date = slot.date
                        let offset = slot.offset
                        let position = pageOffset(offset) + (vertical ? translation.height : translation.width)
                        let stride = vertical ? (pageHeight + height(at: offset)) / 2 + 34 : horizontalStride
                        let edge = BrewCalendarPageMotion.edgeAmount(distance: position, stride: stride)
                        RetainedCalendarPage(identity: CalendarPageIdentity(
                            date: date, month: month, selectedDate: selectedDate, active: offset == 0,
                            weekMode: weekMode, mondayFirst: mondayFirst, width: width,
                            layout: layout, records: store.records, entranceReady: entranceReady)) {
                            page(date, active: offset == 0)
                        }
                            .equatable()
                            .frame(width: width, height: height(at: offset), alignment: .top)
                            .blur(radius: edge * 7)
                            .opacity(1 - edge * 0.62)
                            .position(x: viewportWidth / 2 + (vertical ? 0 : position),
                                      y: viewportHeight / 2 + (vertical ? position : 0))
                            .allowsHitTesting(offset == 0 && !changingPage)
                            .accessibilityElement(children: .contain)
                            .accessibilityHidden(offset != 0)
                    }
                }
            }
        }
        .frame(width: viewportWidth, height: viewportHeight)
        // Keep adjacent pages clipped horizontally while allowing stickers to
        // enter from above the screen instead of appearing at the calendar edge.
        .clipShape(CalendarViewportClip(topOverflow: layout.size.height, bottomOverflow: pagingBottomOverflow))
        .contentShape(Rectangle())
        .simultaneousGesture(DragGesture(minimumDistance: 3)
            .updating($drag) { value, state, transaction in
                guard !changingPage, !foldedPaging else { return }
                transaction.disablesAnimations = true
                if state.vertical == nil {
                    // Resting previews establish the paging axis. A gesture
                    // must not teleport them from above/below to left/right.
                    let primary = layout.landscape ? value.translation.height : value.translation.width
                    let secondary = layout.landscape ? value.translation.width : value.translation.height
                    guard abs(primary) >= abs(secondary) else { return }
                    state.vertical = layout.landscape
                }
                state.translation = state.vertical == true ? CGSize(width: 0, height: value.translation.height)
                    : CGSize(width: value.translation.width, height: 0)
            }
            .onEnded { value in
                guard !changingPage else { return }
                let horizontal = !layout.landscape
                let distance = horizontal ? value.translation.width : value.translation.height
                let crossAxis = horizontal ? value.translation.height : value.translation.width
                guard abs(distance) >= abs(crossAxis) else { return }
                let predicted = horizontal ? value.predictedEndTranslation.width : value.predictedEndTranslation.height
                guard horizontal || layout.landscape else { return }
                guard abs(distance) > 42 || abs(predicted) > 90 else {
                    if !foldedPaging { returnToCurrentPage(horizontal: horizontal, from: value.translation) }
                    return
                }
                turn(distance < 0 ? 1 : -1, horizontal: horizontal, from: value.translation)
            })
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("calendar.pager")
        .accessibilityValue(weekMode ? "week:\(anchor.shortDate)" : month.monthTitle)
        .accessibilityAction(named: Text(weekMode ? "下一周" : "下个月")) { turn(1, horizontal: !layout.landscape) }
        .accessibilityAction(named: Text(weekMode ? "上一周" : "上个月")) { turn(-1, horizontal: !layout.landscape) }
        .onChange(of: weekMode) { _, _ in
            resetPaging()
        }
        .onDisappear { resetPaging() }
    }

    private var foldedPage: some View {
        VStack(spacing: 18) {
            ZStack {
                dateHeader(anchor, active: true)
                    .opacity(1 - fadeProgress)
                    .offset(x: -CGFloat(fadeDirection) * 38 * fadeProgress)
                if let pendingDate {
                    dateHeader(pendingDate, active: false)
                        .opacity(fadeProgress)
                        .offset(x: CGFloat(fadeDirection) * 38 * (1 - fadeProgress))
                        .accessibilityHidden(true)
                }
            }
            .frame(height: expanded ? 62 : 54)
            ZStack(alignment: .top) {
                modeCalendar(anchor, active: true, showsCorner: false)
                    .frame(height: panelHeight, alignment: .top)
                    .opacity(1 - fadeProgress)
                if let pendingDate {
                    modeCalendar(pendingDate, active: true, showsCorner: false)
                        .frame(height: calendarHeight(pendingDate), alignment: .top)
                        .opacity(fadeProgress)
                        .accessibilityHidden(true)
                }
            }
            .frame(height: fadedPanelHeight, alignment: .top)
            // The folded calendar crossfades its dates, not its corner. Keep a
            // single opaque corner attached to the interpolated panel boundary.
            .overlay(alignment: .bottomTrailing) { modeCorner(active: true) }
            .environment(\.calendarEntranceReady, entranceReady && !changingPage)
        }
        .frame(width: width, height: fadedPanelHeight + (expanded ? 80 : 72), alignment: .top)
        .allowsHitTesting(!changingPage)
    }

    private func calendarHeight(_ date: Date, week: Bool? = nil) -> CGFloat {
        let days = BrewCalendarPaging.days(in: date, weekMode: week ?? weekMode, mondayFirst: mondayFirst)
        let rows = max(1, Int(ceil(Double(days.count) / 7)))
        return CGFloat(rows) * cellHeight + CGFloat(rows - 1) * (expanded ? 12 : 8) + (expanded ? 72 : 58) + modeFooterHeight
    }

    private func page(_ date: Date, active: Bool) -> some View {
        VStack(spacing: 18) {
            dateHeader(date, active: active)
            modeCalendar(date, active: active)
        }
    }

    /// Both modes keep their final cell geometry and identity. Only the opacity
    /// and outer panel height animate, rather than replacing a lazy grid while
    /// its viewport is resizing.
    private func modeCalendar(_ date: Date, active: Bool, showsCorner: Bool = true) -> some View {
        let monthDate = weekMode ? month : date
        let weekDate = weekMode ? date : selectedDate
        return ZStack(alignment: .top) {
            calendar(monthDate, active: active && !weekMode, week: false)
                .frame(height: calendarHeight(monthDate, week: false), alignment: .top)
                .animation(nil, value: weekMode)
                .opacity(weekMode ? 0 : 1)
                .allowsHitTesting(!weekMode)
                .accessibilityHidden(weekMode)
            calendar(weekDate, active: active && weekMode, week: true)
                .frame(height: calendarHeight(weekDate, week: true), alignment: .top)
                .animation(nil, value: weekMode)
                .opacity(weekMode ? 1 : 0)
                .allowsHitTesting(weekMode)
                .accessibilityHidden(!weekMode)
        }
        .frame(height: calendarHeight(date), alignment: .top)
        .overlay(alignment: .bottomTrailing) {
            // Every retained page owns its corner, including adjacent pages.
            // Active controls touch/accessibility only, never the artwork.
            if showsCorner { modeCorner(active: active) }
        }
    }

    private func modeCorner(active: Bool) -> some View {
        Button(action: onToggleMode) {
            let side: CGFloat = expanded ? 40 : 34
            CalendarCornerCut()
                .fill(BrewStyle.calendarCorner)
                .frame(width: side, height: side)
                .overlay {
                    Text(weekMode ? "W" : "M")
                        .font(.custom("SnellRoundhand-Bold", size: 14))
                        .foregroundStyle(BrewStyle.calendarCornerInk)
                        .position(x: side * 0.67, y: side * 0.67)
                }
        }
        .buttonStyle(CalendarModeBadgeStyle())
        // Page motion disables interaction on the outer wrapper. Retained page
        // content must not capture transient settling state and keep a stale
        // disabled corner after its dates become current.
        .allowsHitTesting(active)
        .accessibilityHidden(!active)
        .accessibilityLabel(weekMode ? "切换月视图" : "切换周视图")
        .accessibilityValue(weekMode ? "W" : "M")
        .accessibilityIdentifier(active ? "calendar.mode" : "calendar.preview.mode")
    }

    private func dateHeader(_ date: Date, active: Bool) -> some View {
            Menu {
                Button(weekMode ? "上一周" : "上个月") { turn(-1, horizontal: !layout.landscape) }
                Button(weekMode ? "下一周" : "下个月") { turn(1, horizontal: !layout.landscape) }
                Button("回到今天") { month = Date(); selectedDate = Date() }
            } label: {
                VStack(spacing: 4) {
                    Text(heading(date)).font(BrewFont.title)
                    if weekMode {
                        Text(date.formatted(.dateTime.year())).font(BrewFont.caption).foregroundStyle(BrewStyle.muted)
                    } else if Calendar.current.isDate(date, equalTo: Date(), toGranularity: .month) {
                        Text(Date().journalHeading).font(BrewFont.caption).foregroundStyle(BrewStyle.muted)
                    }
                }
                .frame(height: expanded ? 62 : 54)
                .frame(maxWidth: .infinity)
            }
            .accessibilityIdentifier(active ? "home.title" : "calendar.preview.title")
    }

    private func heading(_ date: Date) -> String {
        if weekMode {
            let days = BrewCalendarPaging.days(in: date, weekMode: true, mondayFirst: mondayFirst).compactMap { $0 }
            guard let first = days.first, let last = days.last else { return date.shortDate }
            return "\(first.shortDate)–\(last.shortDate)"
        }
        return Calendar.current.isDate(date, equalTo: Date(), toGranularity: .month) ? "今天" : date.monthTitle
    }

    private func calendar(_ date: Date, active: Bool, week: Bool) -> some View {
        let calendar = Calendar.current
        let days = BrewCalendarPaging.days(in: date, weekMode: week, mondayFirst: mondayFirst)
        let rows = (days.count + 6) / 7
        // Index once per period, instead of scanning the entire journal for
        // every day whenever the calendar's geometry is updated.
        let recordsByDay = Dictionary(grouping: store.records) { calendar.startOfDay(for: $0.date) }
        let weekdays = mondayFirst ? ["周一", "周二", "周三", "周四", "周五", "周六", "周日"] : ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        return VStack(spacing: expanded ? 20 : 13) {
            HStack(spacing: expanded ? 8 : 6) {
                ForEach(weekdays, id: \.self) { day in
                    Text(day).font(.system(size: expanded ? 12 : 10, weight: .medium))
                        .foregroundStyle(BrewStyle.weekday).frame(maxWidth: .infinity)
                }
            }.frame(height: expanded ? 16 : 15)
            VStack(spacing: expanded ? 12 : 8) {
                ForEach(0..<rows, id: \.self) { row in
                    HStack(spacing: expanded ? 8 : 6) {
                        ForEach(0..<7, id: \.self) { column in
                            let index = row * 7 + column
                            Group {
                                if index < days.count, let day = days[index] {
                                    dayCell(day, records: recordsByDay[calendar.startOfDay(for: day)] ?? [], active: active)
                                } else { Color.clear }
                            }
                            .frame(width: cellWidth, height: cellHeight)
                        }
                    }
                }
            }
            .id("\(date.timeIntervalSinceReferenceDate)-\(week)-\(mondayFirst)")
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(active ? "calendar.grid" : "calendar.preview.grid")
        }
        .padding(expanded ? 18 : 15)
        .padding(.bottom, modeFooterHeight)
        .background(BrewStyle.panel, in: RoundedRectangle(cornerRadius: expanded ? 27 : 19))
        // No cell-level clipping: incoming stickers can fall through the header.
    }

    private func dayCell(_ date: Date, records: [DrinkRecord], active: Bool) -> some View {
        return Button {
            selectedDate = date
            if let record = records.first { onRecord(record) }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: expanded ? 14 : 10)
                    .fill(Calendar.current.isDateInToday(date) ? BrewStyle.gold : BrewStyle.panelLight)
                if records.isEmpty {
                    dayNumber(date)
                } else {
                    FallingCalendarStickers(size: min(cellWidth + 2, expanded ? 49 : 38),
                                            animate: active && !layout.reduceMotion,
                                            dateLabel: { dayNumber(date) }) {
                        ZStack {
                            ForEach(Array(records.prefix(3).enumerated()), id: \.element.id) { offset, record in
                                DrinkSticker(image: store.image(for: record), cutout: store.sticker(for: record),
                                             size: min(cellWidth + 2, expanded ? 49 : 38))
                                    .offset(x: CGFloat(offset) * 5, y: CGFloat(offset) * -2)
                            }
                        }
                    }
                }
            }.frame(height: cellHeight)
        }
        .accessibilityLabel(date.shortDate + (records.isEmpty ? "" : "，\(records.count)杯"))
        .accessibilityIdentifier("calendar.day.\(Calendar.current.component(.day, from: date))")
    }

    private func dayNumber(_ date: Date) -> some View {
        Text("\(Calendar.current.component(.day, from: date))")
            .font(.system(size: expanded ? 12 : 11, weight: .medium))
            .foregroundStyle(Calendar.current.isDateInToday(date) ? BrewStyle.todayNumber : BrewStyle.calendarNumber)
    }

    private func turn(_ offset: Int, horizontal: Bool, from translation: CGSize = .zero) {
        guard !changingPage else { return }
        let next = BrewCalendarPaging.shifted(anchor, by: offset, weekMode: weekMode)
        let destination = horizontal ? -CGFloat(offset) * horizontalStride
            : -BrewCalendarPageMotion.centerOffset(to: offset, spacing: 34, height: height(at:))
        settlingVertically = !horizontal
        changingPage = true
        if layout.reduceMotion { commit(next); return }
        if foldedPaging {
            pendingDate = next
            fadeDirection = offset
            settleTask = Task { @MainActor in
                await Task.yield()
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.26)) { fadeProgress = 1 }
                try? await Task.sleep(for: .milliseconds(280))
                guard !Task.isCancelled else { return }
                commit(next)
            }
            return
        }
        var transaction = Transaction(); transaction.disablesAnimations = true
        withTransaction(transaction) {
            settling = horizontal ? CGSize(width: translation.width, height: 0) : CGSize(width: 0, height: translation.height)
        }
        settleTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) {
                settling = horizontal ? CGSize(width: destination, height: 0)
                                      : CGSize(width: 0, height: destination)
            }
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            commit(next)
        }
    }

    private func returnToCurrentPage(horizontal: Bool, from translation: CGSize) {
        settleTask?.cancel()
        var transaction = Transaction(); transaction.disablesAnimations = true
        withTransaction(transaction) {
            settlingVertically = !horizontal
            settling = horizontal ? CGSize(width: translation.width, height: 0) : CGSize(width: 0, height: translation.height)
            changingPage = true
        }
        settleTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }
            withAnimation(.smooth(duration: 0.24)) { settling = .zero }
            try? await Task.sleep(for: .milliseconds(260))
            guard !Task.isCancelled else { return }
            changingPage = false
        }
    }

    private func commit(_ next: Date) {
        var transaction = Transaction(); transaction.disablesAnimations = true
        withTransaction(transaction) {
            month = next; selectedDate = next
            settling = .zero; changingPage = false
            pendingDate = nil; fadeProgress = 0
        }
    }

    private func resetPaging() {
        settleTask?.cancel()
        var transaction = Transaction(); transaction.disablesAnimations = true
        withTransaction(transaction) {
            settling = .zero; changingPage = false
            pendingDate = nil; fadeProgress = 0
        }
    }
}

/// The impact keeps its incoming velocity: it compresses below the date, then
/// springs back into place. Feedback is emitted at the physical landing time.
private struct FallingCalendarStickers<DateLabel: View, Content: View>: View {
    @Environment(\.calendarEntranceReady) private var entranceReady
    private struct FallPose {
        var y: CGFloat
        var dateOpacity: Double
    }
    var size: CGFloat
    var animate: Bool
    @ViewBuilder var dateLabel: () -> DateLabel
    @ViewBuilder var content: () -> Content
    @AppStorage("haptics") private var haptics = true
    @AppStorage(BrewHapticStrength.storageKey) private var hapticStrength = BrewHapticStrength.defaultValue
    @State private var launch = 0
    @State private var entranceTravel: CGFloat?

    var body: some View {
        GeometryReader { geometry in
            // Global coordinates change every frame while the page is dragged.
            // Measure the entrance once; scrolling must not retime its keyframes.
            let travel = entranceTravel ?? max(size, geometry.frame(in: .global).minY + size + 20)
            let duration = Double(travel) / 2_800
            let number = dateLabel()
            let sticker = content().frame(width: size, height: size)
            KeyframeAnimator(initialValue: FallPose(y: animate ? -travel : 0,
                                                   dateOpacity: animate ? 1 : 0), trigger: launch) { pose in
                ZStack {
                    number.opacity(animate ? pose.dateOpacity : 0)
                    sticker.offset(y: animate ? pose.y : 0)
                }
            } keyframes: { _ in
                KeyframeTrack(\.y) {
                    MoveKeyframe(-travel)
                    LinearKeyframe(0, duration: duration)
                    SpringKeyframe(0, duration: 0.42, spring: .init(duration: 0.34, bounce: 0.40), startVelocity: size * 14)
                }
                KeyframeTrack(\.dateOpacity) {
                    MoveKeyframe(1)
                    LinearKeyframe(1, duration: duration)
                    LinearKeyframe(0, duration: 0.12)
                }
            }
            .onAppear { if entranceTravel == nil { entranceTravel = travel } }
            // Activating the retained month/week layer must not replay the fall.
            // A new date period creates new cells and still gets its entrance.
            .task(id: entranceReady) {
                guard animate && entranceReady else { return }
                if haptics { BrewHaptics.shared.prepare() }
                do {
                    try await Task.sleep(for: .seconds(Double.random(in: 0...0.3)))
                    try Task.checkCancellation()
                    launch += 1
                    try await Task.sleep(for: .seconds(duration))
                    try Task.checkCancellation()
                    if haptics && animate && entranceReady {
                        BrewHaptics.shared.landing(strength: hapticStrength)
                    }
                } catch { }
            }
        }
        .frame(width: size, height: size)
    }
}
