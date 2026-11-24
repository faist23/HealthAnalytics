//
//  TrainingWeekTests.swift
//  HealthAnalyticsTests
//
//  Weekly totals follow the rider's training-week setting, not the phone's locale.
//

import XCTest
@testable import HealthAnalytics

final class TrainingWeekTests: XCTestCase {

    private let base: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 1   // a US locale: weeks start Sunday
        return c
    }()

    private func day(_ d: Int) -> Date {   // November 2026; the 22nd is a Sunday
        base.date(from: DateComponents(year: 2026, month: 11, day: d, hour: 12))!
    }

    private func tss(_ d: Int, _ value: Double) -> DailyTSSData {
        DailyTSSData(date: base.startOfDay(for: day(d)), tss: value, hours: value / 50, ctl: 0, atl: 0)
    }

    // Value: protects=a Sunday ride counts in the week that started the Monday before when the
    //   rider picks Monday; fails_when=the locale's first weekday leaks back in; why_new=the
    //   setting is new; seam=none; no_claim=chart rendering
    func test_sundayBelongsToTheWeekItEnds_onAMondayWeek() {
        let monday = TrainingWeek.calendar(startDay: TrainingWeek.monday, base: base)
        let sunday = TrainingWeek.calendar(startDay: TrainingWeek.sunday, base: base)
        XCTAssertEqual(TrainingWeek.weekStart(of: day(22), calendar: monday), base.startOfDay(for: day(16)))
        XCTAssertEqual(TrainingWeek.weekStart(of: day(22), calendar: sunday), base.startOfDay(for: day(22)))
    }

    // Value: protects=the Load tab's weekly TSS and hours split at the chosen day;
    //   fails_when=weeklyTotals groups by the locale calendar; why_new=the setting is new;
    //   seam=none (static); no_claim=the 6-week average
    func test_weeklyTotals_splitAtTheChosenDay() {
        let days = [tss(21, 100), tss(22, 50), tss(23, 30)]   // Sat, Sun, Mon
        let mondayWeeks = TSSChartCard.weeklyTotals(days, calendar: TrainingWeek.calendar(startDay: TrainingWeek.monday, base: base))
        XCTAssertEqual(mondayWeeks.map(\.weeklyTSS), [150, 30])
        XCTAssertEqual(mondayWeeks.map(\.weekStart), [base.startOfDay(for: day(16)), base.startOfDay(for: day(23))])
        XCTAssertEqual(mondayWeeks[0].weeklyHours, 3, accuracy: 0.0001)

        let sundayWeeks = TSSChartCard.weeklyTotals(days, calendar: TrainingWeek.calendar(startDay: TrainingWeek.sunday, base: base))
        XCTAssertEqual(sundayWeeks.map(\.weeklyTSS), [100, 80])
    }

    func test_unsetOrInvalidSettingReadsAsMonday() {
        XCTAssertEqual(TrainingWeek.validated(0), TrainingWeek.monday)
        XCTAssertEqual(TrainingWeek.validated(5), TrainingWeek.monday)
        XCTAssertEqual(TrainingWeek.validated(TrainingWeek.sunday), TrainingWeek.sunday)
    }
}
