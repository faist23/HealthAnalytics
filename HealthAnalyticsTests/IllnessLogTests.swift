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

    // Value: protects=logged spells that overlap or touch are one illness (one HRV window, not
    //   two), while a spell starting two days after another ends is separate; fails_when=
    //   duplicate or adjacent spells each count toward the 3-window gate; why_new=red-team
    //   review; seam=none (pure); no_claim=none
    func test_overlappingLoggedSpells_areOneIllness() {
        let starts = IllnessLog.sickWindowStarts(
            proxy: [], logged: [(day(-30), day(-28)), (day(-29), nil), (day(-27), day(-26)), (day(-24), day(-24))],
            from: from, to: Date())
        XCTAssertEqual(starts, [day(-30)], "the open spell from day -29 runs to now, so day -24 is inside it too")
        let separate = IllnessLog.sickWindowStarts(proxy: [], logged: [(day(-30), day(-28)), (day(-26), day(-25))],
                                                   from: from, to: Date())
        XCTAssertEqual(separate, [day(-30), day(-26)])
    }

    // Value: protects=a low-step stretch up to 2 days before a logged first sick day is that
    //   illness (people log the day they felt sick after low-activity days), and a spell that
    //   started before the 180-day window still absorbs proxy windows inside it without adding
    //   an onset; fails_when=the lead goes back to 1 day, or old spells are dropped before the
    //   dedupe; why_new=v0.1.21.0 adversarial follow-ups; seam=none (pure); no_claim=none
    func test_proxyLeadAndOldSpells() {
        let lead = IllnessLog.sickWindowStarts(proxy: [day(-42), day(-43)], logged: [(day(-40), day(-38))],
                                               from: from, to: Date())
        XCTAssertEqual(lead, [day(-43), day(-40)], "2 days before onset is the same illness; 3 days is not")
        let old = IllnessLog.sickWindowStarts(proxy: [day(-178), day(-150)], logged: [(day(-190), day(-175))],
                                              from: from, to: Date())
        XCTAssertEqual(old, [day(-150)], "the old spell's onset is out of the window, but it still covers day -178")
    }

    // Value: protects=an ongoing illness covers every day up to now, and a logged onset
    //   outside the window is ignored; fails_when=an open spell is treated as one day, or old
    //   illnesses leak in; why_new=Phase 2b; seam=none (pure); no_claim=none
    func test_ongoingIllnessCoversUpToNow_andOldOnsetsAreIgnored() {
        let starts = IllnessLog.sickWindowStarts(proxy: [day(-2)], logged: [(day(-5), nil), (day(-200), day(-198))],
                                                 from: from, to: Date())
        XCTAssertEqual(starts, [day(-5)])
    }

    // Value: protects=the Coach tab's Sick chip starts an illness today on one tap, ends it on
    //   the next (yesterday as the last sick day, today if it only started today), and a third
    //   tap reopens that illness instead of logging a second one; fails_when=a tap opens a
    //   second illness, or "I'm better" marks today sick; why_new=Sick chip, red-team review;
    //   seam=none (in-memory store); no_claim=the chip view itself
    @MainActor
    func test_sickChip_startsThenEndsAnIllness() throws {
        let container = try ModelContainer(for: Schema([IllnessEvent.self]),
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let noon = today.addingTimeInterval(12 * 3600)
        IllnessLog.toggleToday(in: context, now: noon)
        let open = try context.fetch(FetchDescriptor<IllnessEvent>(predicate: IllnessEvent.ongoing))
        XCTAssertEqual(open.map(\.startDate), [today])
        IllnessLog.toggleToday(in: context, now: noon)
        var all = try context.fetch(FetchDescriptor<IllnessEvent>())
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.endDate, today, "started today, better today: today was the only sick day")
        IllnessLog.toggleToday(in: context, now: noon)
        all = try context.fetch(FetchDescriptor<IllnessEvent>())
        XCTAssertEqual(all.count, 1, "a mis-tapped I'm better is undone, not a second illness")
        XCTAssertNil(all.first?.endDate)
        XCTAssertEqual(IllnessLog.lastSickDay(start: day(-3), betterOn: noon), day(-1))
    }

    // Value: protects=the IllnessEvent.ongoing predicate translates to
    //   SQL; fails_when=a predicate that only works in memory ships (the v0.1.17.0 crash);
    //   why_new=new model; seam=none (in-memory store); no_claim=none
    @MainActor
    func test_ongoingPredicate_runsThroughAStore() throws {
        let container = try ModelContainer(for: Schema([IllnessEvent.self]),
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        context.insert(IllnessEvent(startDate: day(-30), endDate: day(-28)))
        context.insert(IllnessEvent(startDate: day(-3)))
        context.insert(IllnessEvent(startDate: day(-200), endDate: day(-199)))
        try context.save()
        let ongoing = try context.fetch(FetchDescriptor<IllnessEvent>(predicate: IllnessEvent.ongoing))
        XCTAssertEqual(ongoing.map(\.startDate), [day(-3)])
    }
}

/// Logging an illness changes the Coach paragraph: sick means rest, whatever else the data says.
final class CoachIllnessTests: XCTestCase {
    private let cal = Calendar.current
    private let today = Calendar.current.startOfDay(for: Date())
    private func day(_ offset: Int) -> Date { cal.date(byAdding: .day, value: offset, to: today)! }
    private let noon = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date())!

    // Value: protects=an open illness is "sick" from its first day; an ended one is
    //   "recovering" through 2 days after its last sick day (including ended today), then
    //   over; fails_when=the windows drift or an ended illness still reads sick;
    //   why_new=Coach illness state; seam=none (pure); no_claim=none
    func test_illnessState_fromTheLog() {
        typealias S = MasterCoachEngine.IllnessState
        XCTAssertEqual(S.from([(day(-3), nil), (day(-1), nil)], now: noon), .sick(since: day(-3)))
        XCTAssertEqual(S.from([(today, today)], now: noon), .recovering, "\"I'm better\" on day one")
        XCTAssertEqual(S.from([(day(-6), day(-2))], now: noon), .recovering)
        XCTAssertEqual(S.from([(day(-6), day(-3))], now: noon), MasterCoachEngine.IllnessState.none)
        XCTAssertEqual(S.from([(day(2), nil)], now: noon), MasterCoachEngine.IllnessState.none, "a future onset isn't today")
        XCTAssertEqual(S.from([], now: noon), MasterCoachEngine.IllnessState.none)
    }

    private func state(_ illness: MasterCoachEngine.IllnessState) -> MasterCoachEngine.StateVector {
        MasterCoachEngine.StateVector(morningScore: 92, currentScore: 92, nextDayForecast: "Hard effort OK", acwr: 1.0,
                                      injuryRisk: .low, activePatterns: ["hrvPrecursor", "performancePeak"], illness: illness)
    }

    // Value: protects=while sick, Coach says rest and nothing else: no intensity, no race
    //   window, no "hard effort tomorrow", even at 92% with peak form active; fails_when=the
    //   illness branch is dropped or ordered after another branch, in either message path;
    //   why_new=Coach illness state; seam=none; no_claim=wording beyond these phrases
    func test_sick_overridesEverySignal_inBothPaths() async {
        let heuristic = MasterCoachEngine.generateHeuristicMessage(state: state(.sick(since: day(-1))))
        let llm = await MasterCoachEngine.generateMessage(state: state(.sick(since: day(-1))))
        for message in [heuristic, llm] {
            XCTAssertTrue(message.hasPrefix("You logged that you're sick"), message)
            for banned in ["intensity", "peak form", "hard effort", "race"] {
                XCTAssertFalse(message.lowercased().contains(banned), "\(banned) in: \(message)")
            }
        }
    }

    // Value: protects=just after an illness, Coach says keep it easy instead of "ready for
    //   intensity"; with no illness the normal paragraph is unchanged; fails_when=recovering
    //   falls through to the score branches, or .none changes existing advice;
    //   why_new=Coach illness state; seam=none; no_claim=wording beyond these phrases
    // Value: protects=the sick paragraph names a weekday only within the last 6 days, then a
    //   date; fails_when="since Tuesday" is shown for an illness that began weeks ago;
    //   why_new=red-team review; seam=none; no_claim=locale formatting
    func test_sickSinceLabel_usesADateBeyondAWeek() {
        let recent = MasterCoachEngine.illnessMessage(.sick(since: day(-2)), memoryNote: "") ?? ""
        XCTAssertTrue(recent.contains("since \(day(-2).formatted(.dateTime.weekday(.wide)))"), recent)
        let old = MasterCoachEngine.illnessMessage(.sick(since: day(-10)), memoryNote: "") ?? ""
        XCTAssertTrue(old.contains("since \(day(-10).formatted(.dateTime.month(.wide).day()))"), old)
    }

    func test_recovering_keepsItEasy_andNoIllnessIsUnchanged() {
        let recovering = MasterCoachEngine.generateHeuristicMessage(state: state(.recovering))
        XCTAssertTrue(recovering.hasPrefix("You're just back from being sick"), recovering)
        XCTAssertFalse(recovering.lowercased().contains("hard effort"))
        let healthy = MasterCoachEngine.generateHeuristicMessage(state: state(.none))
        XCTAssertFalse(healthy.contains("sick"), healthy)
    }

    // Value: protects=logging or ending an illness re-runs the Coach paragraph the same day;
    //   fails_when=the illness state is left out of the cache key (the paragraph would keep
    //   advising training until the next sync); why_new=Coach illness state; seam=none (pure
    //   static); no_claim=refreshIfNecessary wiring from the views
    @MainActor
    func test_illnessChange_invalidatesTheCoachCache() {
        let fingerprint = PredictionCache.fingerprint(workoutCount: 1, sleepCount: 1, hrvCount: 1, rhrCount: 1)
        func reuse(_ now: MasterCoachEngine.IllnessState, _ last: MasterCoachEngine.IllnessState?) -> Bool {
            ReadinessRepository.canReuseCachedAnalysis(lastAnalysisDate: Date(), fingerprint: fingerprint,
                                                       lastFingerprint: fingerprint, activePatternTypes: [],
                                                       lastActivePatternTypes: [], illnessState: now, lastIllnessState: last)
        }
        XCTAssertFalse(reuse(.sick(since: today), MasterCoachEngine.IllnessState.none))
        XCTAssertFalse(reuse(.recovering, .sick(since: today)))
        XCTAssertTrue(reuse(.sick(since: today), .sick(since: today)))
    }

    // Value: protects=adding, resolving or expiring an Injury/Stress/Travel note re-runs the
    //   Coach paragraph even when a tap's refresh is replayed through refreshIfNecessary;
    //   fails_when=the active note set is left out of the cache key (the pre-existing lost-tap
    //   bug); why_new=v0.1.21.0 adversarial follow-ups; seam=none (pure static); no_claim=the
    //   repository's fetch of the notes
    @MainActor
    func test_coachNoteChange_invalidatesTheCoachCache() {
        let fingerprint = PredictionCache.fingerprint(workoutCount: 1, sleepCount: 1, hrvCount: 1, rhrCount: 1)
        let injury = UUID()
        func reuse(_ now: Set<UUID>, _ last: Set<UUID>?) -> Bool {
            ReadinessRepository.canReuseCachedAnalysis(lastAnalysisDate: Date(), fingerprint: fingerprint,
                                                       lastFingerprint: fingerprint, activePatternTypes: [],
                                                       lastActivePatternTypes: [], activeMemoryIDs: now,
                                                       lastActiveMemoryIDs: last)
        }
        XCTAssertFalse(reuse([injury], []), "a new note re-runs Coach")
        XCTAssertFalse(reuse([], [injury]), "an expired or resolved note re-runs Coach")
        XCTAssertTrue(reuse([injury], [injury]))
    }
}
