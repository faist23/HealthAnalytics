//
//  IllnessLogTests.swift
//  HealthAnalyticsTests
//
//  Phase 2b: logged illnesses join the HRV precursor's sick windows. A logged onset is a
//  window on its own; a step-proxy window inside a logged illness (or the day before it)
//  is that illness, not a second one.
//

import XCTest
import SwiftData
@testable import HealthAnalytics

final class IllnessLogTests: XCTestCase {
    private let cal = Calendar.current
    private let today = Calendar.current.startOfDay(for: Date())
    private func day(_ offset: Int) -> Date { cal.date(byAdding: .day, value: offset, to: today)! }
    private var from: Date { day(-180) }

    // Value: protects=a logged illness is a sick window even with no low-step days;
    //   fails_when=logged onsets are ignored; why_new=Phase 2b; seam=none (pure); no_claim=detector wiring
    func test_loggedOnsets_areWindows() {
        let starts = IllnessLog.sickWindowStarts(proxy: [], logged: [(day(-40), day(-38)), (day(-10), nil)],
                                                 from: from, to: Date())
        XCTAssertEqual(starts, [day(-40), day(-10)])
    }

    // Value: protects=a proxy window inside a logged illness, or starting the day before it,
    //   counts once; a proxy window elsewhere still counts; fails_when=the same illness is
    //   counted twice or the overlap rule swallows unrelated windows; why_new=Phase 2b;
    //   seam=none (pure); no_claim=none
    func test_proxyWindowsInsideALoggedIllness_countOnce() {
        let proxy = [day(-41), day(-39), day(-35), day(-20)]
        let starts = IllnessLog.sickWindowStarts(proxy: proxy, logged: [(day(-40), day(-38))],
                                                 from: from, to: Date())
        // -41: the day before onset; -39: inside; -35: three days after it ended; -20: unrelated.
        XCTAssertEqual(starts, [day(-40), day(-35), day(-20)])
    }

    // Value: protects=an ongoing illness covers every day up to now, and a logged onset
    //   outside the window is ignored; fails_when=an open spell is treated as one day, or old
    //   illnesses leak in; why_new=Phase 2b; seam=none (pure); no_claim=none
    func test_ongoingIllnessCoversUpToNow_andOldOnsetsAreIgnored() {
        let starts = IllnessLog.sickWindowStarts(proxy: [day(-2)], logged: [(day(-5), nil), (day(-200), day(-198))],
                                                 from: from, to: Date())
        XCTAssertEqual(starts, [day(-5)])
    }

    // Value: protects=both IllnessEvent predicates (ongoing, onset after a cutoff) translate to
    //   SQL; fails_when=a predicate that only works in memory ships (the v0.1.17.0 crash);
    //   why_new=new model; seam=none (in-memory store); no_claim=none
    @MainActor
    func test_predicates_runThroughAStore() throws {
        let container = try ModelContainer(for: Schema([IllnessEvent.self]),
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        context.insert(IllnessEvent(startDate: day(-30), endDate: day(-28)))
        context.insert(IllnessEvent(startDate: day(-3)))
        context.insert(IllnessEvent(startDate: day(-200), endDate: day(-199)))
        try context.save()
        let ongoing = try context.fetch(FetchDescriptor<IllnessEvent>(predicate: IllnessEvent.ongoing))
        XCTAssertEqual(ongoing.map(\.startDate), [day(-3)])
        let cutoff = day(-180)
        let recent = try context.fetch(FetchDescriptor<IllnessEvent>(
            predicate: #Predicate<IllnessEvent> { $0.startDate >= cutoff }, sortBy: [SortDescriptor(\.startDate)]))
        XCTAssertEqual(recent.map(\.startDate), [day(-30), day(-3)])
    }
}
