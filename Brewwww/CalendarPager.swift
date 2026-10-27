import SwiftUI

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

struct CalendarPager: View {
    @EnvironmentObject private var store: BrewStore
    @Environment(\.brewLayout) private var layout
    @AppStorage("mondayFirst") private var mondayFirst = false
    @Binding var month: Date
    @Binding var selectedDate: Date
    @Binding var weekMode: Bool
    var width: CGFloat
    var viewportWidth: CGFloat
    var onRecord: (DrinkRecord) -> Void
    @GestureState private var drag = CGSize.zero
    @State private var settling = CGSize.zero
    @State private var changingPage = false
    @State private var settleTask: Task<Void, Never>?

    private var anchor: Date { weekMode ? selectedDate : month }
    private var dates: [Date?] { BrewCalendarPaging.days(in: anchor, weekMode: weekMode, mondayFirst: mondayFirst) }
    private var expanded: Bool { layout.expanded }
    private var rowCount: Int { max(1, Int(ceil(Double(dates.count) / 7))) }
    private var cellWidth: CGFloat { (width - (expanded ? 36 : 30) - 6 * (expanded ? 8 : 6)) / 7 }
    private var cellHeight: CGFloat { cellWidth / (expanded ? 0.85 : 0.88) }
    private var panelHeight: CGFloat { CGFloat(rowCount) * cellHeight + CGFloat(rowCount - 1) * (expanded ? 12 : 8) + (expanded ? 72 : 58) }
    private var pageHeight: CGFloat { panelHeight + (expanded ? 80 : 72) }
    private var viewportHeight: CGFloat { layout.landscape ? layout.size.height : pageHeight }
    private var vertical: Bool {
        layout.landscape && (settling.height != 0 || (drag == .zero && settling == .zero) || abs(drag.height) > abs(drag.width))
    }

    var body: some View {
        ZStack {
            ForEach(-1...1, id: \.self) { offset in
                page(BrewCalendarPaging.shifted(anchor, by: offset, weekMode: weekMode), active: offset == 0)
                    .frame(width: width, height: pageHeight, alignment: .top)
                    .blur(radius: offset == 0 ? 0 : 1.5)
                    .opacity(offset == 0 ? 1 : 0.38)
                    .offset(x: vertical ? 0 : CGFloat(offset) * (width + (expanded ? 56 : 24)) + drag.width + settling.width,
                            y: vertical ? CGFloat(offset) * (pageHeight + 34) + drag.height + settling.height : 0)
                    .allowsHitTesting(offset == 0 && !changingPage)
                    .accessibilityElement(children: .contain)
                    .accessibilityHidden(offset != 0)
            }
        }
        .frame(width: viewportWidth, height: viewportHeight)
        .clipped()
        .contentShape(Rectangle())
        .simultaneousGesture(DragGesture(minimumDistance: 18)
            .updating($drag) { value, state, _ in
                guard !changingPage else { return }
                if abs(value.translation.width) > abs(value.translation.height) {
                    state = CGSize(width: value.translation.width, height: 0)
                } else if layout.landscape { state = CGSize(width: 0, height: value.translation.height) }
            }
            .onEnded { value in
                guard !changingPage else { return }
                let horizontal = abs(value.translation.width) >= abs(value.translation.height)
                let distance = horizontal ? value.translation.width : value.translation.height
                let predicted = horizontal ? value.predictedEndTranslation.width : value.predictedEndTranslation.height
                guard horizontal || layout.landscape, abs(distance) > 42 || abs(predicted) > 90 else { return }
                turn(distance < 0 ? 1 : -1, horizontal: horizontal, from: value.translation)
            })
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("calendar.pager")
        .accessibilityValue(weekMode ? "week:\(anchor.shortDate)" : month.monthTitle)
        .accessibilityAction(named: Text(weekMode ? "下一周" : "下个月")) { turn(1, horizontal: true) }
        .accessibilityAction(named: Text(weekMode ? "上一周" : "上个月")) { turn(-1, horizontal: true) }
        .onChange(of: weekMode) { _, _ in
            settleTask?.cancel()
            settling = .zero; changingPage = false
        }
        .onDisappear { settleTask?.cancel() }
    }

    private func page(_ date: Date, active: Bool) -> some View {
        VStack(spacing: 18) {
            Menu {
                Button(weekMode ? "上一周" : "上个月") { turn(-1, horizontal: true) }
                Button(weekMode ? "下一周" : "下个月") { turn(1, horizontal: true) }
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
            calendar(date, active: active)
        }
    }

    private func heading(_ date: Date) -> String {
        if weekMode {
            let days = BrewCalendarPaging.days(in: date, weekMode: true, mondayFirst: mondayFirst).compactMap { $0 }
            guard let first = days.first, let last = days.last else { return date.shortDate }
            return "\(first.shortDate)–\(last.shortDate)"
        }
        return Calendar.current.isDate(date, equalTo: Date(), toGranularity: .month) ? "今天" : date.monthTitle
    }

    private func calendar(_ date: Date, active: Bool) -> some View {
        let days = BrewCalendarPaging.days(in: date, weekMode: weekMode, mondayFirst: mondayFirst)
        let weekdays = mondayFirst ? ["周一", "周二", "周三", "周四", "周五", "周六", "周日"] : ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        return VStack(spacing: expanded ? 20 : 13) {
            HStack(spacing: expanded ? 8 : 6) {
                ForEach(weekdays, id: \.self) { day in
                    Text(day).font(.system(size: expanded ? 12 : 10, weight: .medium))
                        .foregroundStyle(BrewStyle.weekday).frame(maxWidth: .infinity)
                }
            }.frame(height: expanded ? 16 : 15)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: expanded ? 8 : 6), count: 7), spacing: expanded ? 12 : 8) {
                ForEach(days.indices, id: \.self) { index in
                    if let day = days[index] {
                        dayCell(day, index: index, active: active)
                    } else { Color.clear.frame(height: cellHeight) }
                }
            }
            .id("\(date.timeIntervalSinceReferenceDate)-\(weekMode)-\(mondayFirst)")
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(active ? "calendar.grid" : "calendar.preview.grid")
        }
        .padding(expanded ? 18 : 15)
        .background(BrewStyle.panel, in: RoundedRectangle(cornerRadius: expanded ? 27 : 19))
        // No cell-level clipping: incoming stickers can fall through the header.
    }

    private func dayCell(_ date: Date, index: Int, active: Bool) -> some View {
        let records = store.records.filter { Calendar.current.isDate($0.date, inSameDayAs: date) }
        return Button {
            selectedDate = date
            if let record = records.first { onRecord(record) }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: expanded ? 14 : 10)
                    .fill(Calendar.current.isDateInToday(date) ? BrewStyle.gold : BrewStyle.panelLight)
                if records.isEmpty {
                    Text("\(Calendar.current.component(.day, from: date))")
                        .font(.system(size: expanded ? 12 : 11, weight: .medium)).foregroundStyle(BrewStyle.calendarNumber)
                } else {
                    ForEach(Array(records.prefix(3).enumerated()), id: \.element.id) { offset, record in
                        FallingDrinkSticker(image: store.image(for: record), cutout: store.sticker(for: record),
                                            size: min(cellWidth + 2, expanded ? 49 : 38),
                                            delay: Double(index % 7) * 0.045 + Double(offset) * 0.06,
                                            travel: min(320, CGFloat(index / 7 + 1) * cellHeight),
                                            animate: active && !layout.reduceMotion)
                            .offset(x: CGFloat(offset) * 5, y: CGFloat(offset) * -2)
                    }
                }
            }.frame(height: cellHeight)
        }
        .accessibilityLabel(date.shortDate + (records.isEmpty ? "" : "，\(records.count)杯"))
        .accessibilityIdentifier("calendar.day.\(Calendar.current.component(.day, from: date))")
    }

    private func turn(_ offset: Int, horizontal: Bool, from translation: CGSize = .zero) {
        guard !changingPage else { return }
        let next = BrewCalendarPaging.shifted(anchor, by: offset, weekMode: weekMode)
        changingPage = true
        if layout.reduceMotion { commit(next); return }
        var transaction = Transaction(); transaction.disablesAnimations = true
        withTransaction(transaction) {
            settling = horizontal ? CGSize(width: translation.width, height: 0) : CGSize(width: 0, height: translation.height)
        }
        settleTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) {
                settling = horizontal ? CGSize(width: -CGFloat(offset) * (width + (expanded ? 56 : 24)), height: 0)
                                      : CGSize(width: 0, height: -CGFloat(offset) * (pageHeight + 34))
            }
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            commit(next)
        }
    }

    private func commit(_ next: Date) {
        var transaction = Transaction(); transaction.disablesAnimations = true
        withTransaction(transaction) {
            month = next; selectedDate = next
            settling = .zero; changingPage = false
        }
    }
}

private struct FallingDrinkSticker: View {
    var image: UIImage?
    var cutout: UIImage?
    var size: CGFloat
    var delay: Double
    var travel: CGFloat
    var animate: Bool
    @State private var drop = 0
    private struct Pose { var y = 0.0; var angle = 0.0 }

    var body: some View {
        DrinkSticker(image: image, cutout: cutout, size: size)
            .keyframeAnimator(initialValue: Pose(), trigger: drop) { view, pose in
                view.offset(y: pose.y).rotationEffect(.degrees(pose.angle))
            } keyframes: { _ in
                KeyframeTrack(\.y) {
                    MoveKeyframe(-Double(travel))
                    LinearKeyframe(-Double(travel), duration: delay + 0.05)
                    CubicKeyframe(0, duration: 0.30, startVelocity: 0, endVelocity: Double(travel) * 4)
                    SpringKeyframe(-5, duration: 0.09, spring: .snappy)
                    SpringKeyframe(0, duration: 0.22, spring: .bouncy)
                }
                KeyframeTrack(\.angle) {
                    MoveKeyframe(-14)
                    LinearKeyframe(-14, duration: delay + 0.05)
                    CubicKeyframe(5, duration: 0.30)
                    SpringKeyframe(0, duration: 0.31, spring: .bouncy)
                }
            }
            .onAppear { if animate { drop += 1 } }
    }
}
