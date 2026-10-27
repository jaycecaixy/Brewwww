import XCTest
@testable import Brewwww

final class CalendarPagingTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    func testMonthPagingClampsEndOfMonthToLastValidDay() {
        let january31 = date(2026, 1, 31)
        XCTAssertEqual(shift(january31, by: 1), date(2026, 2, 28))
        XCTAssertEqual(shift(date(2026, 3, 31), by: -1), date(2026, 2, 28))
        XCTAssertEqual(shift(date(2024, 1, 31), by: 1), date(2024, 2, 29))
        XCTAssertEqual(shift(january31, by: 2), date(2026, 3, 31),
                       "跨两个月不能因为二月没有31日而溢出到错误月份")
    }

    func testMonthPagingCrossesYearInBothDirections() {
        XCTAssertEqual(shift(date(2026, 12, 15), by: 1), date(2027, 1, 15))
        XCTAssertEqual(shift(date(2027, 1, 15), by: -1), date(2026, 12, 15))
        XCTAssertEqual(shift(date(2026, 12, 31), by: 1), date(2027, 1, 31))
    }

    func testWeekPagingMovesExactlySevenDaysAcrossYearBoundary() {
        let anchor = date(2026, 12, 29, hour: 16)
        let next = shift(anchor, by: 1, weekMode: true)
        let previous = shift(anchor, by: -1, weekMode: true)
        XCTAssertEqual(next, date(2027, 1, 5, hour: 16))
        XCTAssertEqual(previous, date(2026, 12, 22, hour: 16))
        XCTAssertEqual(next.timeIntervalSince(anchor), 7 * 24 * 60 * 60)
        XCTAssertEqual(anchor.timeIntervalSince(previous), 7 * 24 * 60 * 60)
        XCTAssertEqual(shift(anchor, by: 0, weekMode: true), anchor)
    }

    func testWeekStartPreferenceHandlesSundayAsFirstOrLastDay() {
        let sunday = date(2026, 11, 1, hour: 19)
        let sundayFirst = days(sunday, weekMode: true, mondayFirst: false)
        let mondayFirst = days(sunday, weekMode: true, mondayFirst: true)
        XCTAssertEqual(sundayFirst, (1...7).map { Optional(date(2026, 11, $0)) })
        XCTAssertEqual(mondayFirst, (26...31).map { Optional(date(2026, 10, $0)) }
                       + [date(2026, 11, 1)])
        XCTAssertEqual(sundayFirst.first!, date(2026, 11, 1), "周视图以本地日零点开始，不沿用输入时刻")
    }

    func testMonthGridOffsetsAlignDatesToWeekdayColumns() {
        // October 1, 2026 is Thursday: column 4 on Sunday-first, column 3 on Monday-first.
        let anchor = date(2026, 10, 15)
        let sundayFirst = days(anchor, mondayFirst: false)
        let mondayFirst = days(anchor, mondayFirst: true)
        XCTAssertEqual(sundayFirst.count, 35)
        XCTAssertEqual(mondayFirst.count, 34)
        XCTAssertTrue(sundayFirst.prefix(4).allSatisfy { $0 == nil })
        XCTAssertTrue(mondayFirst.prefix(3).allSatisfy { $0 == nil })
        XCTAssertEqual(sundayFirst[4], date(2026, 10, 1))
        XCTAssertEqual(mondayFirst[3], date(2026, 10, 1))
        let expected = (1...31).map { date(2026, 10, $0) }
        XCTAssertEqual(sundayFirst.compactMap { $0 }, expected)
        XCTAssertEqual(mondayFirst.compactMap { $0 }, expected)
    }

    func testSundayMonthStartNeedsZeroOrSixLeadingBlanks() {
        let anchor = date(2026, 11, 20)
        let sundayFirst = days(anchor, mondayFirst: false)
        let mondayFirst = days(anchor, mondayFirst: true)
        XCTAssertEqual(sundayFirst.count, 30)
        XCTAssertEqual(sundayFirst.first!, date(2026, 11, 1))
        XCTAssertEqual(mondayFirst.count, 36)
        XCTAssertTrue(mondayFirst.prefix(6).allSatisfy { $0 == nil })
        XCTAssertEqual(mondayFirst[6], date(2026, 11, 1))
        XCTAssertEqual(mondayFirst.compactMap { $0 }.last, date(2026, 11, 30))
    }

    func testFebruaryIncludesLeapDayOnlyInLeapYear() {
        let leapDays = days(date(2024, 2, 15), mondayFirst: false).compactMap { $0 }
        let ordinaryDays = days(date(2023, 2, 15), mondayFirst: false).compactMap { $0 }
        XCTAssertEqual(leapDays, (1...29).map { date(2024, 2, $0) })
        XCTAssertEqual(ordinaryDays, (1...28).map { date(2023, 2, $0) })
        XCTAssertEqual(leapDays.last, date(2024, 2, 29))
        XCTAssertEqual(ordinaryDays.last, date(2023, 2, 28))
    }

    func testWeekRemainsSevenContinuousDatesAcrossMonthAndYear() {
        let values = days(date(2026, 12, 31), weekMode: true, mondayFirst: true)
        let expected = (28...31).map { date(2026, 12, $0) } + (1...3).map { date(2027, 1, $0) }
        XCTAssertEqual(values.count, 7)
        XCTAssertEqual(values.compactMap { $0 }, expected)
        XCTAssertFalse(values.contains(where: { $0 == nil }), "周视图跨月仍应保留七个实际日期，不插入占位格")
        let nextWeek = days(shift(date(2026, 12, 31), by: 1, weekMode: true),
                            weekMode: true, mondayFirst: true).compactMap { $0 }
        XCTAssertEqual(nextWeek, (4...10).map { date(2027, 1, $0) })
        XCTAssertTrue(Set(expected).isDisjoint(with: nextWeek))
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }
    private func shift(_ date: Date, by offset: Int, weekMode: Bool = false) -> Date {
        BrewCalendarPaging.shifted(date, by: offset, weekMode: weekMode, calendar: calendar)
    }
    private func days(_ date: Date, weekMode: Bool = false, mondayFirst: Bool) -> [Date?] {
        BrewCalendarPaging.days(in: date, weekMode: weekMode, mondayFirst: mondayFirst, calendar: calendar)
    }
}
