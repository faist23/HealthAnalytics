# Age-Based Hard-Day Rules (Part 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The 7-day plan limits Hard days per week and the spacing between them by the rider's age, and the day after a Hard day is at most Easy.

**Architecture:** A pure `HardDayRules` value (age in, two numbers out) is carried on `ForecastPlanInput`. `ForecastPlanner.caps` reads it for the weekly limit and the spacing floor. `ReadinessRepository.computeForecastPlan` builds it from the age Apple Health gives, falling back to the last age the app read.

**Tech Stack:** Swift, SwiftUI app, XCTest. No new dependencies. The Xcode project uses file-system-synchronized groups, so new files need no project edits.

**Spec:** `docs/superpowers/specs/2026-11-10-hard-days-cap-design.md`, Part 1 only. Part 2 (learning the rider's response) is not in this plan.

## Global Constraints

- Under 60: at most 3 Hard days in any 7, at least 1 day after a Hard day before the next. 60 and over: at most 2, at least 2.
- The first day after a hard day (planned, ridden today, or ridden yesterday) is at most Easy at every age. Further recovery days are at most Moderate.
- The rider's learned `recoveryDays` can lengthen the spacing, never shorten it below the age floor.
- Age unknown: use the last age read successfully; if none was ever read, the under-60 rules. A failed read never loosens a limit already applied.
- Every rule is a ceiling: `max` over `ForecastEffort`, never raises a day, never overrides a stricter cap.
- "Rode hard today" still caps today itself at Moderate. Unchanged.
- Reason strings are unchanged: "Enough hard days this week", "Still recovering from <weekday>".
- No UI change, no new stored model field, no change to `ForecastProfile.learn`.
- Tests run with: `xcodebuild test -project HealthAnalytics.xcodeproj -scheme HealthAnalytics -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -only-testing:HealthAnalyticsTests/<Class>`. SourceKit "cannot find in scope" errors are noise; trust only the build.
- Break each new test once on purpose (flip the constant it pins) before trusting a first-try pass.

## Review Focus

1. **Health gives an implausible age** (birth date in the future, year 1900 placeholder: age below 0 or above 110). Expected: treated as unknown, never remembered. Test in Task 1.
2. **The rider ignored the plan and rode hard two days running at 65.** Expected: today at most Easy, tomorrow at most Moderate, no crash, reason names the most recent hard day. Test in Task 2.
3. **More hard days already ridden this week than the limit** (three in the last 6 days at 65, e.g. the birthday that crosses 60). Expected: no Hard day until fewer than 2 remain in the trailing window. Test in Task 2.
4. **A hard ride today on top of one earlier in the week at 65.** Expected: today's ride counts toward the week, so no Hard on the next three days. Test in Task 2.
5. **Age read fails on one refresh after working on the last** (device locked, Health unavailable). Expected: the plan keeps the 60+ rules from the remembered age. Test in Task 1 (the resolver) and Task 3 (through the repository).

---

### Task 1: `HardDayRules`

**Files:**
- Create: `HealthAnalytics/Services/Analytics/HardDayRules.swift`
- Test: `HealthAnalyticsTests/HardDayRulesTests.swift`

**Interfaces:**
- Produces:

```swift
struct HardDayRules: Equatable {
    let hardDaysPerWeek: Int
    let minimumRecoveryDays: Int

    static let seniorAge = 60
    static let plausibleAges = 10...110
    static let under60 = HardDayRules(hardDaysPerWeek: 3, minimumRecoveryDays: 1)
    static let from60 = HardDayRules(hardDaysPerWeek: 2, minimumRecoveryDays: 2)
    static let lastKnownAgeKey = "forecastLastKnownAge"

    /// nil (unknown) gives `under60`.
    nonisolated static func forAge(_ age: Int?) -> HardDayRules
    /// A plausible `read` is stored and returned. Otherwise the stored age, or nil if none.
    nonisolated static func resolvedAge(read: Int?, defaults: UserDefaults) -> Int?
}
```

- [ ] **Step 1: Write the failing tests** in `HardDayRulesTests` (use a `UserDefaults(suiteName:)` unique per test, removed in `tearDown`):

```swift
func testForAge_bands() {
    XCTAssertEqual(HardDayRules.forAge(59), .under60)
    XCTAssertEqual(HardDayRules.forAge(60), .from60)
    XCTAssertEqual(HardDayRules.forAge(65), .from60)
    XCTAssertEqual(HardDayRules.forAge(nil), .under60)
    XCTAssertEqual(HardDayRules.from60, HardDayRules(hardDaysPerWeek: 2, minimumRecoveryDays: 2))
    XCTAssertEqual(HardDayRules.under60, HardDayRules(hardDaysPerWeek: 3, minimumRecoveryDays: 1))
}
func testResolvedAge_remembersTheLastGoodRead() {
    XCTAssertEqual(HardDayRules.resolvedAge(read: 65, defaults: defaults), 65)
    XCTAssertEqual(HardDayRules.resolvedAge(read: nil, defaults: defaults), 65)
    XCTAssertEqual(HardDayRules.resolvedAge(read: 66, defaults: defaults), 66)
    XCTAssertEqual(defaults.integer(forKey: HardDayRules.lastKnownAgeKey), 66)
}
func testResolvedAge_neverReadIsNil() {
    XCTAssertNil(HardDayRules.resolvedAge(read: nil, defaults: defaults))
}
func testResolvedAge_implausibleReadIsUnknownAndNotStored() {
    XCTAssertEqual(HardDayRules.resolvedAge(read: 65, defaults: defaults), 65)
    for bad in [-1, 0, 9, 111, 126] {
        XCTAssertEqual(HardDayRules.resolvedAge(read: bad, defaults: defaults), 65)
    }
    XCTAssertEqual(defaults.integer(forKey: HardDayRules.lastKnownAgeKey), 65)
}
func testResolvedAge_implausibleFirstReadIsNil() {
    XCTAssertNil(HardDayRules.resolvedAge(read: 0, defaults: defaults))
}
```

- [ ] **Step 2: Run** `-only-testing:HealthAnalyticsTests/HardDayRulesTests`. Expected: build fails, `HardDayRules` not found.
- [ ] **Step 3: Implement `HardDayRules`** per the interface. Read the stored age with `defaults.object(forKey:) as? Int` so a missing key is nil, not 0.
- [ ] **Step 4: Run** the same class. Expected: 5 tests pass.
- [ ] **Step 5: Commit** `feat: hard-day rules from the rider's age`.

### Task 2: The planner applies the rules

**Files:**
- Modify: `HealthAnalytics/Services/Analytics/ForecastPlanner.swift` (`ForecastPlanInput`, `ForecastPlanner.caps`)
- Test: `HealthAnalyticsTests/ForecastPlannerTests.swift`

**Interfaces:**
- Consumes: `HardDayRules` from Task 1.
- Produces: `ForecastPlanInput.hardDayRules: HardDayRules` (a `var`, default `.under60`), replacing `hardDaysPerWeekCap: Int?`, which is deleted.

- [ ] **Step 1: Write the failing tests.** Add `rules: HardDayRules = .under60` to the test file's `input(...)` helper, setting `hardDayRules` on the result, and a helper `inputWithHistory(z:rules:hardDaysAgo: [Int], rode: Double = 0)` that fills `recentLoads` with `ForecastHistoryDay(date: day(-n), score: 70, load: 5)` for each `n`. Then:

```swift
func testDayAfterHard_isAtMostEasy_atEveryAge() {
    for rules in [HardDayRules.under60, .from60] {
        let days = plan(input(z: 2, rules: rules))
        XCTAssertEqual(days[0].effort, .hard)
        XCTAssertGreaterThanOrEqual(days[1].effort, .easy, "\(days.map(\.effort))")
    }
}
func testFrom60_twoDaysBetweenHards_andTwoAWeek() {
    let days = plan(input(z: 2, rules: .from60))
    let hard = days.indices.filter { days[$0].effort == .hard }
    XCTAssertEqual(hard.count, 2, "\(days.map(\.effort))")
    XCTAssertGreaterThanOrEqual(hard[1] - hard[0], 3)
    XCTAssertGreaterThanOrEqual(days[hard[0] + 2].effort, .moderate)
}
func testUnder60_threeAWeek() {
    // A fast recoverer (dip 0.5), so recovery alone would allow Hard every other day: 0, 2, 4, 6.
    let days = plan(input(z: 2, profile: profile(recoveryDays: 1, dip: 0.5), rules: .under60))
    XCTAssertEqual(days.filter { $0.effort == .hard }.count, 3, "\(days.map(\.effort))")
}
func testLearnedRecoveryLongerThanTheAgeFloorWins() {
    let days = plan(input(z: 2, profile: profile(recoveryDays: 3, dip: 0.5), rules: .from60))
    let hard = days.indices.filter { days[$0].effort == .hard }
    for (a, b) in zip(hard, hard.dropFirst()) { XCTAssertGreaterThanOrEqual(b - a, 4) }
}
func testFrom60_twoHardRidesThisWeek_holdHardWithTheReason() {
    // Hard rides 5 and 3 days ago: day 0 and day 1 still see both in their trailing 6 days.
    let days = plan(inputWithHistory(z: 2, rules: .from60, hardDaysAgo: [5, 3]))
    XCTAssertEqual(days[0].effort, .moderate)
    XCTAssertEqual(days[0].reason, "Enough hard days this week")
    XCTAssertNotEqual(days[1].effort, .hard)
    XCTAssertEqual(days[2].effort, .hard)   // the ride 5 days ago is now 7 back
}
func testRodeHardYesterdayAndTheDayBefore_at65() {   // Review Focus 2
    let days = plan(inputWithHistory(z: 2, rules: .from60, hardDaysAgo: [2, 1]))
    XCTAssertGreaterThanOrEqual(days[0].effort, .easy)
    XCTAssertEqual(days[0].reason, "Still recovering from \(day(-1).formatted(.dateTime.weekday(.wide)))")
    XCTAssertGreaterThanOrEqual(days[1].effort, .moderate)
}
func testMoreHardDaysRiddenThanTheLimit_at60() {     // Review Focus 3
    let days = plan(inputWithHistory(z: 2, rules: .from60, hardDaysAgo: [5, 3, 1]))
    // Trailing 6 days hold fewer than 2 only from day 4 (the rides 5 and 3 days ago have left).
    XCTAssertFalse(days[0...3].contains { $0.effort == .hard }, "\(days.map(\.effort))")
}
func testHardRideTodayCountsTowardTheWeek_at65() {   // Review Focus 4
    let days = plan(inputWithHistory(z: 2, rules: .from60, hardDaysAgo: [3], rode: 5))
    XCTAssertFalse(days[1...3].contains { $0.effort == .hard }, "\(days.map(\.effort))")
}
func testStricterCapStillWins() {
    var i = input(z: 2, rules: .from60)
    i.illness = .sick
    XCTAssertTrue(plan(i).allSatisfy { $0.effort == .rest })
}
```

`ForecastEffort` orders least to most restrictive, so `>= .easy` means "Easy or Rest". If a count assertion fails only because recovery (not a cap) held a day down, raise the start `z`; do not loosen the assertion.

- [ ] **Step 2: Update the existing tests this change contradicts**, and only these:
  - `testYesterdaysHardRide_capsToday`: expect `.easy`.
  - `testHardDaysPerWeekCap_nilMeansNoCap_oneCapsTheWeek`: delete (the new tests replace it).
  - Any other failure after Step 4 is a real finding: stop and read it before touching the test.
- [ ] **Step 3: Run** `-only-testing:HealthAnalyticsTests/ForecastPlannerTests`. Expected: build fails on `hardDayRules`.
- [ ] **Step 4: Implement in `ForecastPlanner.swift`.**
  - `ForecastPlanInput`: replace `hardDaysPerWeekCap` with `var hardDayRules: HardDayRules = .under60` and a doc comment naming the spec.
  - `caps`: the recovery cap uses `max(input.profile.recoveryDays, input.hardDayRules.minimumRecoveryDays)`; when `gap == 1` the cap is `.easy`, otherwise `.moderate`; the reason is unchanged.
  - `caps`: the weekly cap is unconditional, reading `input.hardDayRules.hardDaysPerWeek`.
- [ ] **Step 5: Run** the class. Expected: all pass. Then break-check: set `from60.hardDaysPerWeek` to 3 and confirm `testFrom60_twoDaysBetweenHards_andTwoAWeek` fails; restore.
- [ ] **Step 6: Commit** `feat: the plan spaces and limits Hard days by age`.

### Task 3: The repository supplies the age; docs

**Files:**
- Modify: `HealthAnalytics/HealthAnalytics/Services/Analytics/ReadinessRepository.swift` (`computeForecastPlan` near line 1356 and its call near line 803)
- Modify: `HealthAnalyticsTests/ForecastPlanStoreTests.swift`
- Modify: `CLAUDE.md`, `TODOS.md`

**Interfaces:**
- Consumes: `HardDayRules.forAge`, `HardDayRules.resolvedAge`, `ForecastPlanInput.hardDayRules`.
- Produces: `computeForecastPlan(..., sleep:, age: Int?, now:)`. `age` is the already-resolved age, has no default, and the function sets `hardDayRules: .forAge(age)`.

- [ ] **Step 1: Write the failing tests** in `ForecastPlanStoreTests`. Add `age: Int? = nil` to its `plan(...)` helper and pass it through. Using the file's existing seeding for a well-recovered rider with 14+ scored days (reuse the fixture the existing Hard-day store test uses):

```swift
func testAge65_planHoldsToTwoHardDays() throws {
    let days = try XCTUnwrap(plan(start: 95, age: 65))
    XCTAssertLessThanOrEqual(days.filter { $0.effort == .hard }.count, 2)
    XCTAssertGreaterThanOrEqual(days.filter { $0.effort == .hard }.count, 1)
}
func testAge45_planAllowsThree() throws {
    let days = try XCTUnwrap(plan(start: 95, age: 45))
    let hard = days.indices.filter { days[$0].effort == .hard }
    XCTAssertLessThanOrEqual(hard.count, 3)
    // Two Hard days two apart: allowed under 60, forbidden from 60. This is what proves the age reached the planner.
    XCTAssertTrue(zip(hard, hard.dropFirst()).contains { $1 - $0 == 2 }, "\(days.map(\.effort))")
}
func testFailedAgeRead_keepsTheRememberedRules() throws {   // Review Focus 5
    let suite = UserDefaults(suiteName: #function)!
    defer { suite.removePersistentDomain(forName: #function) }
    _ = HardDayRules.resolvedAge(read: 65, defaults: suite)
    let remembered = HardDayRules.resolvedAge(read: nil, defaults: suite)
    let days = try XCTUnwrap(plan(start: 95, age: remembered))
    XCTAssertLessThanOrEqual(days.filter { $0.effort == .hard }.count, 2)
}
```

If `start: 95` is not clearly above the fixture's normal, pick the start score that gives a Hard day 0 in the existing tests of this file. If the fixture's learned recovery keeps the age-45 plan from placing Hard days two apart, seed a fast-recovering history for that test instead of weakening the assertion.

- [ ] **Step 2: Run** `-only-testing:HealthAnalyticsTests/ForecastPlanStoreTests`. Expected: build fails on `age:`.
- [ ] **Step 3: Implement.** Add the `age` parameter and set `hardDayRules`. At the call site pass `HardDayRules.resolvedAge(read: HealthKitManager.shared.getUserAge(), defaults: .standard)`, computed once before `buildForecast()`. No cache-key change: the snapshot is already refused after 15 minutes (`forecastLiveRefreshInterval`), and an age changes once a year.
- [ ] **Step 4: Run** the class. Expected: all pass.
- [ ] **Step 5: Update docs.**
  - `CLAUDE.md`, the "7-day forecast is a personal plan" bullet: replace "Recovery time never goes below 1 in this release, so nobody gets two Hard days in a row" and "a weekly Hard cap that release 2 fills (nil = no cap)" with the age rules (the table, Easy on the first day after a hard day, remembered age, `HardDayRules`, the spec path), and name `HardDayRulesTests`.
  - `TODOS.md`: replace "Forecast release 2: learned limit on hard days per week" with a P2 entry "Forecast: learn each rider's response to hard days" pointing at the spec's Part 2 (2a read-only screen, then 2b); add a Completed line for the age rules; move "Forecast: the same workout feeling harder is a stress signal" to Completed (built v0.1.26.0, replaced v0.1.28.0), keeping its open leftovers (the unsynced deleted rating, Effort Check's failure states) as a short P3 entry; in the P4 "Leftovers" entry, correct the `PredictionCache` line to say `PredictionCache.DataFingerprint` is live and only `store(models:)` and the predictor types are dead.
- [ ] **Step 6: Run the whole unit lane** (`-only-testing:HealthAnalyticsTests`). Expected: all pass, no new warnings.
- [ ] **Step 7: Commit** `feat: the forecast reads the rider's age for its hard-day rules`.
