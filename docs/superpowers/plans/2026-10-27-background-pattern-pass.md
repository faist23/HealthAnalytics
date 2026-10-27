# Background Pattern Pass Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Pattern alerts (above all the HRV precursor illness warning) arrive within minutes of the first unlock after new Health data, without opening the app, and never from stale or half-synced stores.

**Architecture:**
- **Triggers.** HealthKit background delivery (HRV + workouts) is the primary trigger. The existing app-refresh task is a backup. Both call one `BackgroundPatternPass` through the repository's shared `patternAnalysisFlight`.
- **The pass does five things, in order:**
  1. A HealthKit-only workout refresh.
  2. Recompute stale score rows ("finalization").
  3. Run detection behind a commit gate. The gate discards a run that spanned a suspension.
  4. Stamp the run with its start time.
  5. Refresh Coach, but only when the app is in the foreground.
- **Store-based detector checks read complete days ending yesterday,** in both the foreground and the background.

**Tech Stack:** Swift 6 / SwiftUI, SwiftData (`@ModelActor`), HealthKit (`HKObserverQuery`, `enableBackgroundDelivery`), BackgroundTasks, XCTest.

**Spec:** `docs/superpowers/specs/2026-10-27-background-pattern-pass-design.md` (approved 2026-10-27)

## Global Constraints

- **Branch:** `feat/background-pattern-pass`, cut from `main` at v0.1.15.0 (`15a1f2c`).
- **The background must never run the Coach analysis.** That means no `performFullAnalysis` or `MasterCoachEngine` from the pass, except through `refreshIfNecessary` when `isAppInForeground()` is true at completion.
- **The background must never post `DataSyncCompleted`.** Its observer calls `refreshIfNecessary`.
- **The background must never move `SyncManager.lastSyncDate`.** The next foreground sync must still pull Strava for that window.
- **No Strava calls in the background.** All rides reach Apple Health.
- **Do not change the foreground paths** (`.appear`, `.staleCheck`, `.userRetry`, Coach). The one exception is complete-days anchoring (Task 1).
- `maxBackgroundPassDuration` = 2 minutes (`2 * 60`).
- The `.background` throttle stays `forcedPatternAnalysisMinInterval` (5 minutes).
- The background stamp `lastPatternAnalysisDate` is set to the pass's **start** time.
- **Notifications stay once ever per pattern** through `TrainingPattern.notificationSent`. Never reset it.
- **Test lane:** `xcodebuild test -project HealthAnalytics.xcodeproj -scheme HealthAnalytics -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -only-testing:HealthAnalyticsTests`.
  - For a single class, append `/<ClassName>`.
  - Rerun once on "failed to launch … Busy".
  - Always read the full log for every `failed (` line.
- **New files need no `project.pbxproj` edits.** The project uses `PBXFileSystemSynchronizedRootGroup`.
- **SourceKit "Cannot find X in scope" diagnostics are noise.** Only trust `xcodebuild`.
- **Colors and fonts:** use design tokens from `DESIGN.md` (`Color.textTertiary`, etc.). No hardcoded colors or inline font sizes.
- **Every commit ends with the session's two attribution trailers** (the `Co-Authored-By` line and the session-link line from the session's attribution instructions). `<trailers>` in a task's commit command stands for them.

## Review Focus

1. **A ride the foreground already saved as its Strava copy must not get a second row from the HealthKit-only refresh.** A double row means double load, which means a false taper or a false back-to-back crash. Covered by a Task 4 test.
2. **A burst of HealthKit deliveries must not re-run analysis or notify twice.** HRV samples can arrive minutes apart. Every wake after the first, within 5 minutes of a completed pass, must end `throttled` with no steps run. Covered by a Task 5 test.
3. **The clock moving backwards between start and commit** (manual time change, time-zone travel) must abandon the run, not commit it, and must leave no stamp. Covered by a Task 5 test.
4. **HealthKit refusing or failing** (not authorized, database inaccessible) must end `failed`, silently and with no stamp. The observer completion must still be called. Covered by Task 5 and Task 6 tests.
5. **Finalization after a long absence or a clock moved backwards** must recompute a bounded range: at most 90 days, and nothing when `scoresFinalizedThrough` is in the future. Covered by a Task 3 test.

---

## File Structure

| File | Responsibility |
|---|---|
| `HealthAnalytics/Services/Analytics/TrainingDNAAnalyzer.swift` (modify) | complete-days anchoring; commit gate on `analyze` |
| `HealthAnalytics/Services/Analytics/ScoreRowFinalization.swift` (create) | pure rule: which stored days to recompute |
| `HealthAnalytics/HealthAnalytics/Services/Analytics/ReadinessRepository.swift` (modify) | backfill `recomputeFrom:`; `finalizeScoreRows`; `runBackgroundPass`; `analyzePatternsForBackgroundPass`; shared `hrvSourcePreference` |
| `HealthAnalytics/Utilities/SyncManager.swift` (modify) | `refreshWorkoutsFromHealthKit`; `DataPersistenceActor.upsertHealthKitWorkoutsOnly` + pure filter |
| `HealthAnalytics/Services/Analytics/BackgroundPatternPass.swift` (create) | `BackgroundPassWake`, `BackgroundPassOutcome`, `BackgroundPassSteps`, `BackgroundPatternPass`, `BackgroundPassLog`, `LiveBackgroundPassSteps` |
| `HealthAnalytics/Services/HealthKit/HealthDataObserver.swift` (create) | `HKObserverQuery` + background delivery registration; always-complete handler |
| `HealthAnalytics/HealthAnalyticsApp.swift` (modify) | `AppDelegate` adaptor registers the observer at launch; app-refresh handler runs the pass |
| `HealthAnalytics/HealthAnalytics.entitlements` (modify) | `com.apple.developer.healthkit.background-delivery` |
| `HealthAnalytics/Views/BackgroundPassStatsView.swift` (create) + `HealthAnalytics/Views/SettingsView.swift` (modify) | debug counters screen |
| Tests: `PredictiveIntelligenceTests.swift`, `TrainingDNAAnalyzerTests.swift` (modify); `ScoreRowFinalizationTests.swift`, `HealthKitWorkoutRefreshTests.swift`, `BackgroundPatternPassTests.swift`, `HealthDataObserverTests.swift` (create) | |
| `CLAUDE.md`, `TODOS.md`, `CHANGELOG.md` (modify) | docs |

**Note: spec deviation, same semantics.** The spec describes `detect()` and `commit()` as two calls. `TrainingPattern` is a SwiftData `@Model`, so detected patterns can't leave the `@ModelActor` without Sendable violations. Task 2 instead adds a `commitGate` closure to `analyze`. The actor calls it at the existing commit point, immediately before `upsertPatterns`. Nothing is written before the gate, and `analyze()` with the default gate behaves exactly as today.

---

### Task 1: Complete-days anchoring for store-based checks

**Files:**
- Modify: `HealthAnalytics/Services/Analytics/TrainingDNAAnalyzer.swift`. The edits are in the HRV precursor sick-day proxy (~line 399), back-to-back (~544), performance peak (~671), taper (~784, ~831) and `taperIsCorroborated` (~893).
- Modify: `HealthAnalyticsTests/PredictiveIntelligenceTests.swift`
- Modify: `HealthAnalyticsTests/TrainingDNAAnalyzerTests.swift` (~641, ~675)

**Interfaces:**
- Produces: `private var completeDaysEnd: Date` and `private func completeDayStart(daysBack: Int) -> Date` on `TrainingDNAAnalyzer`, and `taperIsCorroborated(endingBefore:)`. The old `taperIsCorroborated(referenceDate:)` is removed.

- [ ] **Step 1: Write the failing tests** in `PredictiveIntelligenceTests.swift`, beside the other taper tests:

```swift
    /// The background pass never writes today's row, and the foreground's is partial.
    /// 28 complete days ending yesterday must be enough on their own.
    func testTaperUnderway_noRowForToday_stillFires() async throws {
        let container = try makeFullContainer()
        let analyzer = TrainingDNAAnalyzer(modelContainer: container)

        var mock = MockPatternDataProvider()
        mock.historyDays = 180
        mock.hrvData = makeTaperHRVData(positive: true)
        await analyzer.setDataProvider(mock)

        let scores = makeTaperScores(last7Load: 0.65, prev21Load: 1.0)
            .filter { !Calendar.current.isDate($0.date, inSameDayAs: ref) }
        try await analyzer.insertDailyScores(scores)
        try await seedIntensityHeldWorkouts(analyzer)

        _ = try await analyzer.analyze()

        let patterns = try await analyzer.fetchAllPatterns()
        XCTAssertTrue(patterns.contains { $0.patternType == .tapering },
                      "Store-based checks read complete days; today's missing row must not block the taper")
    }

    /// Today's row is partial and must not count as a day of the recent week. Here a
    /// big day-in-progress row (3.0) would lift the old recent mean to ~0.94 (a 6% drop,
    /// no taper); over the 7 complete days the drop is a real 40%.
    func testTaperUnderway_todaysPartialRowCannotHideATaper() async throws {
        let container = try makeFullContainer()
        let analyzer = TrainingDNAAnalyzer(modelContainer: container)

        var mock = MockPatternDataProvider()
        mock.historyDays = 180
        mock.hrvData = makeTaperHRVData(positive: true)
        await analyzer.setDataProvider(mock)

        var scores = makeTaperScores(last7Load: 0.6, prev21Load: 1.0)
            .filter { !Calendar.current.isDate($0.date, inSameDayAs: ref) }
        scores.append(StoredDailyScore(date: ref, readinessScore: 70, dailyStrain: 1.0,
                                       workoutCount: 2, dailyLoad: 3.0))
        try await analyzer.insertDailyScores(scores)
        try await seedIntensityHeldWorkouts(analyzer)

        _ = try await analyzer.analyze()

        let patterns = try await analyzer.fetchAllPatterns()
        XCTAssertTrue(patterns.contains { $0.patternType == .tapering },
                      "Only complete days count; today's partial row must not mask the drop")
    }

    /// Today's ride counts from tomorrow. With no ride in the 7 complete days, a ride
    /// this morning must not rescue session presence.
    func testTaperUnderway_rideTodayDoesNotCountAsRecent() async throws {
        let container = try makeFullContainer()
        let analyzer = TrainingDNAAnalyzer(modelContainer: container)

        var mock = MockPatternDataProvider()
        mock.historyDays = 180
        mock.hrvData = makeTaperHRVData(positive: true)
        await analyzer.setDataProvider(mock)

        try await analyzer.insertDailyScores(makeTaperScores(last7Load: 0.0, prev21Load: 1.0))
        var workouts = baselineDays.map { taperWorkout(daysAgo: $0, hr: 150) }
        workouts.append(taperWorkout(daysAgo: 0, hr: 150, minutes: 35))
        try await analyzer.insertWorkouts(workouts)

        _ = try await analyzer.analyze()

        let patterns = try await analyzer.fetchAllPatterns()
        XCTAssertFalse(patterns.contains { $0.patternType == .tapering },
                       "Only complete days count; today's ride must not count as this week's session")
    }
```

- [ ] **Step 2: Add the window constants and update the fixtures in `PredictiveIntelligenceTests.swift`.**

Under `private func day(_:)`, add:

```swift
    /// Store-based taper checks read complete days ending yesterday:
    /// recent week = days 1–7 ago, baseline = days 8–28 ago.
    private let recentWeek = 1...7
    private let baselineDays = 8...28
```

In `makeTaperScores` (~line 1109), replace `dailyLoad: daysAgo < 7 ? last7Load : prev21Load` with:

```swift
                dailyLoad: recentWeek.contains(daysAgo) ? last7Load : prev21Load
```

Replace the old range literals throughout the file. They are at ~562–563, 595–596, 621–622, 647, 749–750 and 777:
- `(7..<28).map` becomes `baselineDays.map`
- `(0..<7).map` becomes `recentWeek.map`

Leave unrelated ranges alone (for example `(0..<10).map` in the day-28 test, which Step 3 replaces). Also leave the `[1, 4].map` casual-rider list alone: days 1 and 4 are already inside 1…7.

- [ ] **Step 3: Rewrite the three boundary tests in `PredictiveIntelligenceTests.swift` for the new edges.** Replace the bodies of these tests (~lines 715–790):
  - `testTaperUnderway_rideLateOnDaySeven_isBaselineNotRecent`
  - `testTaperUnderway_ridesLateOnDayTwentyEight_areOutsideTheBaseline`
  - `testTaperUnderway_onlyRideAtStartOfDaySix_countsAsRecent`

Keep the `// Generated by /ship…` value-card comment above the third test, updated to the new days.

```swift
    /// A ride late on calendar day 8 belongs to the baseline, not the recent week
    /// (days 1–7). Clock-proof: 23:59 is the last minute of that day.
    func testTaperUnderway_rideLateOnDayEight_isBaselineNotRecent() async throws {
        let container = try makeFullContainer()
        let analyzer = TrainingDNAAnalyzer(modelContainer: container)

        var mock = MockPatternDataProvider()
        mock.historyDays = 180
        mock.hrvData = makeTaperHRVData(positive: true)
        await analyzer.setDataProvider(mock)

        try await analyzer.insertDailyScores(makeTaperScores(last7Load: 0.0, prev21Load: 1.0))
        var workouts = (9...28).map { taperWorkout(daysAgo: $0, hr: 150) }
        workouts.append(lateWorkout(daysAgo: 8, hr: 150))
        try await analyzer.insertWorkouts(workouts)

        _ = try await analyzer.analyze()

        let patterns = try await analyzer.fetchAllPatterns()
        XCTAssertFalse(patterns.contains { $0.patternType == .tapering },
                       "No ride in the 7 complete days is a stoppage; a late day-8 ride doesn't change that")
    }

    /// Rides late on calendar day 29 are outside the 21-day baseline (days 8–28).
    /// At a high HR they would inflate baseline intensity until a genuine taper fails
    /// the retention check.
    func testTaperUnderway_ridesLateOnDayTwentyNine_areOutsideTheBaseline() async throws {
        let container = try makeFullContainer()
        let analyzer = TrainingDNAAnalyzer(modelContainer: container)

        var mock = MockPatternDataProvider()
        mock.historyDays = 180
        mock.hrvData = makeTaperHRVData(positive: true)
        await analyzer.setDataProvider(mock)

        try await analyzer.insertDailyScores(makeTaperScores(last7Load: 0.65, prev21Load: 1.0))
        var workouts = baselineDays.map { taperWorkout(daysAgo: $0, hr: 140) }
        workouts += recentWeek.map { taperWorkout(daysAgo: $0, hr: 140, minutes: 35) }
        workouts += (0..<10).map { lateWorkout(daysAgo: 29, hr: 185, id: $0) }
        try await analyzer.insertWorkouts(workouts)

        _ = try await analyzer.analyze()

        let patterns = try await analyzer.fetchAllPatterns()
        XCTAssertTrue(patterns.contains { $0.patternType == .tapering },
                      "Same effort recent vs baseline is a taper; rides from day 29 must not count in the baseline")
    }

    // Generated by /ship test coverage audit (Claude Code), pass 2; re-anchored to complete days.
    // Value: protects=a ride at 00:00 on calendar day 7 is in the recent week (days 1–7), so it alone passes
    //   session presence; fails_when=recentStart moves one day later or the recent filter becomes `>`;
    //   why_new=the clock-proof tests pin the outer edges (day 8, day 29); seam=none;
    //   no_claim=HRV and volume tiers beyond the fixtures (mocked HRV provider, in-memory store; unit only)
    func testTaperUnderway_onlyRideAtStartOfDaySeven_countsAsRecent() async throws {
        let container = try makeFullContainer()
        let analyzer = TrainingDNAAnalyzer(modelContainer: container)

        var mock = MockPatternDataProvider()
        mock.historyDays = 180
        mock.hrvData = makeTaperHRVData(positive: true)
        await analyzer.setDataProvider(mock)

        try await analyzer.insertDailyScores(makeTaperScores(last7Load: 0.65, prev21Load: 1.0))
        var workouts = baselineDays.map { taperWorkout(daysAgo: $0, hr: 150) }
        // From the clock now, not the suite-start `ref`: this ride sits exactly on the
        // window's inner edge, so a suite that crossed midnight would push it out.
        let today = Calendar.current.startOfDay(for: Date())
        workouts.append(StoredWorkout(
            id: "start-of-day-7",
            type: .cycling,
            startDate: Calendar.current.date(byAdding: .day, value: -7, to: today)!,
            duration: 35 * 60,
            distance: nil, power: nil, energy: nil, hr: 150,
            source: "test"
        ))
        try await analyzer.insertWorkouts(workouts)

        _ = try await analyzer.analyze()

        let patterns = try await analyzer.fetchAllPatterns()
        XCTAssertTrue(patterns.contains { $0.patternType == .tapering },
                      "Day 7 is part of the recent week from its first minute; its ride must count")
    }
```

- [ ] **Step 4: Shift the analyzer-test score fixtures back one day so they end yesterday.** In `HealthAnalyticsTests/TrainingDNAAnalyzerTests.swift`:
  - `makeBackToBackScores` (~line 641): change `let date = day(-(daysBack - 1 - i))` to `let date = day(-(daysBack - i))`.
  - `testWarmupDaysDoNotCountAsHardDays` (~line 675): change `let date = day(-(89 - i))` to `let date = day(-(90 - i))`.

- [ ] **Step 5: Run the two classes and confirm the new tests fail on the old code.**

Run: `xcodebuild test … -only-testing:HealthAnalyticsTests/PredictiveIntelligenceTests -only-testing:HealthAnalyticsTests/TrainingDNAAnalyzerTests`

Expected: FAIL. At least these fail:
- `testTaperUnderway_noRowForToday_stillFires`: only 27 days are counted, so the `daily.count >= 28` guard returns nil.
- `testTaperUnderway_todaysPartialRowCannotHideATaper`
- `testTaperUnderway_rideTodayDoesNotCountAsRecent`
- `testTaperUnderway_onlyRideAtStartOfDaySeven_countsAsRecent`: on the old window, day 7 is baseline.

If any of these four passes on the old code, it isn't guarding anything. Stop and fix the test before continuing.

`…rideLateOnDayEight…` and `…ridesLateOnDayTwentyNine…` pass on both the old and new windows. They guard the new outer edges against an off-by-one in Step 6. Break-check them after Step 7 by temporarily changing `-7` to `-8` (recentStart) and `-28` to `-29` (windowStart) in `taperIsCorroborated`. Confirm each fails, then revert.

Record every `failed (` line from the full log.

- [ ] **Step 6: Implement the anchoring in `TrainingDNAAnalyzer.swift`.**

Add these helpers below `dayFormatter`:

```swift
    /// Store-based checks read complete calendar days only, ending yesterday. Today's
    /// StoredDailyScore row is partial (written on each foreground open) and the
    /// background pass never writes one, so including it made a verdict depend on who
    /// ran the analysis and when. Live HealthKit series (HRV, sleep, steps, active
    /// energy) still include today — this morning's HRV is what the alerts are for.
    private var completeDaysEnd: Date { Calendar.current.startOfDay(for: Date()) }

    /// Start of the complete-days window `daysBack` days before `completeDaysEnd`.
    private func completeDayStart(daysBack: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -daysBack, to: completeDaysEnd) ?? completeDaysEnd
    }
```

In `detectHRVPrecursor`, replace

```swift
        let cutoff = Calendar.current.date(byAdding: .day, value: -180, to: Date()) ?? Date()
        let dailyScores = (try? modelContext.fetch(
            FetchDescriptor<StoredDailyScore>(
                predicate: #Predicate<StoredDailyScore> { $0.date >= cutoff }
            )
        )) ?? []
```

with

```swift
        let cutoff = completeDayStart(daysBack: 180)
        let end = completeDaysEnd
        let dailyScores = (try? modelContext.fetch(
            FetchDescriptor<StoredDailyScore>(
                predicate: #Predicate<StoredDailyScore> { $0.date >= cutoff && $0.date < end }
            )
        )) ?? []
```

In `detectBackToBackReadinessCrash`, replace

```swift
        let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date()
        let predicate = #Predicate<StoredDailyScore> { $0.date >= cutoff }
```

with

```swift
        let cutoff = completeDayStart(daysBack: 90)
        let end = completeDaysEnd
        let predicate = #Predicate<StoredDailyScore> { $0.date >= cutoff && $0.date < end }
```

In `detectPerformancePeak`, replace

```swift
        let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date()
        let predicate90 = #Predicate<StoredDailyScore> { $0.date >= cutoff }
```

with

```swift
        let cutoff = completeDayStart(daysBack: 90)
        let end = completeDaysEnd
        let predicate90 = #Predicate<StoredDailyScore> { $0.date >= cutoff && $0.date < end }
```

In `detectTaperUnderway`, replace

```swift
        let cutoff28 = Calendar.current.date(byAdding: .day, value: -28, to: Date()) ?? Date()
        let predicate28 = #Predicate<StoredDailyScore> { $0.date >= cutoff28 }
```

with

```swift
        // The 28 complete days ending yesterday.
        let cutoff28 = completeDayStart(daysBack: 28)
        let end = completeDaysEnd
        let predicate28 = #Predicate<StoredDailyScore> { $0.date >= cutoff28 && $0.date < end }
```

and replace `guard taperIsCorroborated(referenceDate: Date()) else { return nil }` with `guard taperIsCorroborated(endingBefore: completeDaysEnd) else { return nil }`.

Replace the head of `taperIsCorroborated` (its signature through the `stored` fetch) with:

```swift
    private func taperIsCorroborated(endingBefore end: Date) -> Bool {
        let cal = Calendar.current
        let end = cal.startOfDay(for: end)
        // Complete calendar days, matching the volume comparison's 28 daily scores:
        // recent = the 7 days ending yesterday, baseline = the 21 days before that.
        // Today's workouts count from tomorrow.
        guard let windowStart = cal.date(byAdding: .day, value: -28, to: end),
              let recentStart = cal.date(byAdding: .day, value: -7, to: end)
        else { return false }

        let descriptor = FetchDescriptor<StoredWorkout>(
            predicate: #Predicate { $0.startDate >= windowStart && $0.startDate < end },
            sortBy: [SortDescriptor(\.startDate)]
        )
        let stored = (try? modelContext.fetch(descriptor)) ?? []
```

Leave the rest of the function (from `let workouts = stored.map …`) unchanged. Also update the doc comment above the function so it describes these windows.

- [ ] **Step 7: Run both classes again.**

Run: the Step 5 command.
Expected: PASS, 0 failures. If any other existing test fails, check whether its fixture places the deciding row or workout on today (day 0). If it does, move that fixture back one day, the same way as Step 4. Do not change detector thresholds.

- [ ] **Step 8: Commit.**

```bash
git add HealthAnalytics/Services/Analytics/TrainingDNAAnalyzer.swift HealthAnalyticsTests/PredictiveIntelligenceTests.swift HealthAnalyticsTests/TrainingDNAAnalyzerTests.swift
git commit -m "feat: store-based pattern checks read complete days ending yesterday

<trailers>"
```

---

### Task 2: Commit gate on `analyze`

**Files:**
- Modify: `HealthAnalytics/Services/Analytics/TrainingDNAAnalyzer.swift` (`PatternAnalysisError` ~line 224; `analyze` ~line 281)
- Test: `HealthAnalyticsTests/PredictiveIntelligenceTests.swift`

**Interfaces:**
- Produces:
  - `PatternAnalysisError.commitDeclined`
  - `func analyze(sourcePreference: HRVSourcePreference = .auto, commitGate: @Sendable () async -> Bool = { true }) async throws -> Int`. It throws `.commitDeclined` when the gate returns false, after detection and before any write.

- [ ] **Step 1: Write the failing tests** in `PredictiveIntelligenceTests.swift`:

```swift
    /// The background pass discards a run that spanned a suspension. Detection must
    /// write nothing — no pattern rows, no renewed detectedAt — before the gate.
    func testAnalyze_commitGateDeclined_writesNothing() async throws {
        let container = try makeFullContainer()
        let analyzer = TrainingDNAAnalyzer(modelContainer: container)

        var mock = MockPatternDataProvider()
        mock.historyDays = 180
        mock.hrvData = makeTaperHRVData(positive: true)
        await analyzer.setDataProvider(mock)
        try await analyzer.insertDailyScores(makeTaperScores(last7Load: 0.65, prev21Load: 1.0))
        try await seedIntensityHeldWorkouts(analyzer)

        do {
            _ = try await analyzer.analyze(commitGate: { false })
            XCTFail("A declined gate must throw commitDeclined")
        } catch PatternAnalysisError.commitDeclined {
            // expected
        }

        let patterns = try await analyzer.fetchAllPatterns()
        XCTAssertTrue(patterns.isEmpty, "Nothing may be persisted when the commit gate declines")
    }

    func testAnalyze_commitGateAccepted_persistsAsBefore() async throws {
        let container = try makeFullContainer()
        let analyzer = TrainingDNAAnalyzer(modelContainer: container)

        var mock = MockPatternDataProvider()
        mock.historyDays = 180
        mock.hrvData = makeTaperHRVData(positive: true)
        await analyzer.setDataProvider(mock)
        try await analyzer.insertDailyScores(makeTaperScores(last7Load: 0.65, prev21Load: 1.0))
        try await seedIntensityHeldWorkouts(analyzer)

        _ = try await analyzer.analyze(commitGate: { true })

        let patterns = try await analyzer.fetchAllPatterns()
        XCTAssertTrue(patterns.contains { $0.patternType == .tapering })
    }
```

- [ ] **Step 2: Run them and confirm they fail.**

Run: `xcodebuild test … -only-testing:HealthAnalyticsTests/PredictiveIntelligenceTests`
Expected: a build failure, because `commitGate` and `commitDeclined` don't exist yet.

- [ ] **Step 3: Implement it.** Change the error enum to:

```swift
enum PatternAnalysisError: Error {
    case insufficientData
    case persistenceFailed(Error)
    /// The caller's commit gate refused after detection; nothing was written.
    case commitDeclined
}
```

Change the `analyze` signature to:

```swift
    /// `commitGate` runs after detection and before any write. The background pass uses
    /// it to discard a run that spanned a suspension (stale and fresh reads mixed); the
    /// default commits, so foreground callers behave exactly as before.
    func analyze(
        sourcePreference: HRVSourcePreference = .auto,
        commitGate: @Sendable () async -> Bool = { true }
    ) async throws -> Int {
```

Immediately after the existing `guard !Task.isCancelled else { return historyDays }` and before `try upsertPatterns(detected)`, insert:

```swift
        guard await commitGate() else { throw PatternAnalysisError.commitDeclined }
```

- [ ] **Step 4: Run the class.** Expected: PASS, 0 failures.

- [ ] **Step 5: Commit.**

```bash
git add HealthAnalytics/Services/Analytics/TrainingDNAAnalyzer.swift HealthAnalyticsTests/PredictiveIntelligenceTests.swift
git commit -m "feat: analyze takes a commit gate checked after detection, before any write

<trailers>"
```

---

### Task 3: Score-row finalization

**Files:**
- Create: `HealthAnalytics/Services/Analytics/ScoreRowFinalization.swift`
- Modify: `HealthAnalytics/HealthAnalytics/Services/Analytics/ReadinessRepository.swift` (`refreshIfNecessary` ~line 352; `backfillHistoricalScores` ~line 952)
- Test: `HealthAnalyticsTests/ScoreRowFinalizationTests.swift`

**Interfaces:**
- Produces:
  - `enum ScoreRowFinalization { nonisolated static let maxRecomputeDays = 90; nonisolated static func recomputeRange(finalizedThrough: Date?, now: Date, calendar: Calendar = .current) -> ClosedRange<Date>? }`
  - `ReadinessRepository.finalizeScoreRows(modelContext: ModelContext, now: Date = Date()) async`, which is internal and used by Task 5
  - The UserDefaults key `"scoresFinalizedThrough"`

- [ ] **Step 1: Write the failing tests** in `HealthAnalyticsTests/ScoreRowFinalizationTests.swift`:

```swift
//
//  ScoreRowFinalizationTests.swift
//  HealthAnalyticsTests
//
//  Pins which stored score days get recomputed. A row written mid-afternoon on the
//  user's last open must be recomputed once that day is complete; today is never
//  recomputed (its row stays foreground-only).
//

import XCTest
@testable import HealthAnalytics

final class ScoreRowFinalizationTests: XCTestCase {
    private let cal = Calendar.current
    private var today: Date { cal.startOfDay(for: Date()) }
    private func day(_ offset: Int) -> Date { cal.date(byAdding: .day, value: offset, to: today)! }

    func test_neverFinalized_recomputesYesterdayOnly() {
        let range = ScoreRowFinalization.recomputeRange(finalizedThrough: nil, now: Date())
        XCTAssertEqual(range, day(-1)...day(-1))
    }

    /// Last open was 3 days ago, which finalized through 4 days ago. The open day's
    /// partial row (day -3) and everything after it through yesterday get recomputed.
    func test_lastOpenThreeDaysAgo_recomputesFromThatDayThroughYesterday() {
        let range = ScoreRowFinalization.recomputeRange(finalizedThrough: day(-4), now: Date())
        XCTAssertEqual(range, day(-3)...day(-1))
    }

    func test_alreadyFinalizedThroughYesterday_nothingDue() {
        XCTAssertNil(ScoreRowFinalization.recomputeRange(finalizedThrough: day(-1), now: Date()))
    }

    func test_neverIncludesToday() {
        let range = ScoreRowFinalization.recomputeRange(finalizedThrough: day(-10), now: Date())
        XCTAssertEqual(range?.upperBound, day(-1))
    }

    /// Review focus 5: a long absence is bounded by the backfill horizon.
    func test_longAbsence_isBoundedToNinetyDays() {
        let range = ScoreRowFinalization.recomputeRange(finalizedThrough: day(-400), now: Date())
        XCTAssertEqual(range?.lowerBound, day(-ScoreRowFinalization.maxRecomputeDays))
    }

    /// Review focus 5: a clock moved backwards leaves finalizedThrough in the future.
    func test_finalizedThroughInTheFuture_nothingDue() {
        XCTAssertNil(ScoreRowFinalization.recomputeRange(finalizedThrough: day(5), now: Date()))
    }

    /// The finalized marker is a calendar day; a time-of-day on it must not shift the range.
    func test_finalizedThroughWithTimeOfDay_usesItsCalendarDay() {
        let lateOnDayMinus4 = day(-3).addingTimeInterval(-60)
        let range = ScoreRowFinalization.recomputeRange(finalizedThrough: lateOnDayMinus4, now: Date())
        XCTAssertEqual(range, day(-3)...day(-1))
    }
}
```

- [ ] **Step 2: Run them and confirm they fail.**

Run: `xcodebuild test … -only-testing:HealthAnalyticsTests/ScoreRowFinalizationTests`
Expected: a build failure, because `ScoreRowFinalization` doesn't exist yet.

- [ ] **Step 3: Implement the rule** in `HealthAnalytics/Services/Analytics/ScoreRowFinalization.swift`:

```swift
//
//  ScoreRowFinalization.swift
//  HealthAnalytics
//
//  Which stored StoredDailyScore days must be recomputed. `backfillHistoricalScores`
//  skips days that already have a row, so a row written mid-afternoon on the user's
//  last open kept that partial load forever — including after an evening ride.
//

import Foundation

enum ScoreRowFinalization {
    /// Matches the backfill horizon (`backfillHistoricalScores` covers 90 days).
    nonisolated static let maxRecomputeDays = 90

    /// Days to recompute: from the day after `finalizedThrough` (yesterday when nothing
    /// was ever finalized) through yesterday, never today, at most `maxRecomputeDays`
    /// back. Nil when nothing is due, including a `finalizedThrough` in the future.
    nonisolated static func recomputeRange(
        finalizedThrough: Date?,
        now: Date,
        calendar: Calendar = .current
    ) -> ClosedRange<Date>? {
        let today = calendar.startOfDay(for: now)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
              let horizon = calendar.date(byAdding: .day, value: -maxRecomputeDays, to: today)
        else { return nil }

        var start = yesterday
        if let finalizedThrough {
            let finalizedDay = calendar.startOfDay(for: finalizedThrough)
            guard finalizedDay < yesterday,
                  let next = calendar.date(byAdding: .day, value: 1, to: finalizedDay)
            else { return nil }
            start = max(next, horizon)
        }
        return start...yesterday
    }
}
```

- [ ] **Step 4: Run the class.** Expected: PASS (7 tests).

- [ ] **Step 5: Make the backfill recompute days in range.** In `ReadinessRepository.backfillHistoricalScores`:

Change the signature to:

```swift
    private func backfillHistoricalScores(modelContext: ModelContext, force: Bool = false, recomputeFrom: Date? = nil) async {
```

Change the early-return guard to:

```swift
        guard force || recomputeFrom != nil || !UserDefaults.standard.bool(forKey: udKey) || existingCount < 14 || hasRecentGap else { return }
```

Replace

```swift
        let allExisting  = (try? modelContext.fetch(FetchDescriptor<StoredDailyScore>())) ?? []
        let existingDates = Set(allExisting.map { $0.dateString })
```

with

```swift
        let allExisting  = (try? modelContext.fetch(FetchDescriptor<StoredDailyScore>())) ?? []
        let existingDates = Set(allExisting.map { $0.dateString })
        // First row per day; duplicate-day twins are resolved by the detectors (max load).
        let existingByDate = Dictionary(allExisting.map { ($0.dateString, $0) }, uniquingKeysWith: { first, _ in first })
        let recomputeStart = recomputeFrom.map { calendar.startOfDay(for: $0) }
```

Replace `guard !existingDates.contains(dateStr) else { continue }` with:

```swift
            let isRecompute = recomputeStart.map { day >= $0 } ?? false
            guard isRecompute || !existingDates.contains(dateStr) else { continue }
```

Replace the `modelContext.insert(StoredDailyScore(…))` / `inserted += 1` block with:

```swift
            if isRecompute, let row = existingByDate[dateStr] {
                // Count only real changes, so an unchanged day doesn't clear the
                // pattern stamp below.
                let changed = row.readinessScore != readiness.score
                    || row.dailyStrain != acwr
                    || row.workoutCount != todayWorkouts.count
                    || row.dailyLoad != dayLoad
                guard changed else { continue }
                row.readinessScore = readiness.score
                row.dailyStrain = acwr
                row.workoutCount = todayWorkouts.count
                row.dailyLoad = dayLoad
            } else {
                modelContext.insert(StoredDailyScore(
                    date: day,
                    readinessScore: readiness.score,
                    dailyStrain: acwr,
                    workoutCount: todayWorkouts.count,
                    dailyLoad: dayLoad
                ))
            }
            inserted += 1
```

Update the comment above `if inserted > 0 {` so it says "inserted or recomputed".

- [ ] **Step 6: Add `finalizeScoreRows` and route `refreshIfNecessary` through it.** Add this to `ReadinessRepository`, directly above `backfillHistoricalScores`:

```swift
    /// Writes missing past score rows and recomputes stale ones (days from the one
    /// after `scoresFinalizedThrough` through yesterday). Never touches today's row.
    /// Shared by the foreground refresh and the background pattern pass.
    func finalizeScoreRows(modelContext: ModelContext, now: Date = Date()) async {
        let key = "scoresFinalizedThrough"
        let range = ScoreRowFinalization.recomputeRange(
            finalizedThrough: UserDefaults.standard.object(forKey: key) as? Date,
            now: now
        )
        await backfillHistoricalScores(modelContext: modelContext, recomputeFrom: range?.lowerBound)
        if let range { UserDefaults.standard.set(range.upperBound, forKey: key) }
    }
```

In `refreshIfNecessary`, replace

```swift
        // Backfill StoredDailyScore from HealthKit history on first launch.
        await backfillHistoricalScores(modelContext: modelContext)
```

with

```swift
        // Backfill missing StoredDailyScore days and recompute any written before
        // their day ended.
        await finalizeScoreRows(modelContext: modelContext)
```

Leave the `force: true` forecast call (~line 885) unchanged.

- [ ] **Step 7: Run the full lane.** Expected: PASS, with no new failures. The backfill reads HealthKit, so the recompute path has no simulator seam. The rule is pinned by Step 1, and Task 7's device checklist covers the rest.

- [ ] **Step 8: Commit.**

```bash
git add HealthAnalytics/Services/Analytics/ScoreRowFinalization.swift HealthAnalytics/HealthAnalytics/Services/Analytics/ReadinessRepository.swift HealthAnalyticsTests/ScoreRowFinalizationTests.swift
git commit -m "fix: recompute score rows written before their day ended

<trailers>"
```

---

### Task 4: HealthKit-only workout refresh

**Files:**
- Modify: `HealthAnalytics/Utilities/SyncManager.swift`. Changes go in `SyncManager` (near `performSmartSync`) and in `DataPersistenceActor` (near `upsertRecentData`, ~line 887).
- Test: `HealthAnalyticsTests/HealthKitWorkoutRefreshTests.swift`

**Interfaces:**
- Produces:
  - `SyncManager.refreshWorkoutsFromHealthKit(now: Date = Date()) async throws`
  - `DataPersistenceActor.upsertHealthKitWorkoutsOnly(_ workouts: [WorkoutData], since: Date)`
  - `nonisolated static func DataPersistenceActor.healthKitWorkoutsNotCoveredByStrava(_ healthKit: [WorkoutData], storedStrava: [StravaImportData]) -> [WorkoutData]`
  - The UserDefaults key `"lastBackgroundWorkoutRefresh"`

- [ ] **Step 1: Write the failing tests** in `HealthAnalyticsTests/HealthKitWorkoutRefreshTests.swift`:

```swift
//
//  HealthKitWorkoutRefreshTests.swift
//  HealthAnalyticsTests
//
//  The background pass refreshes workouts from HealthKit only (no Strava). A ride the
//  foreground already stored as its Strava copy must not gain a second, HealthKit-UUID
//  row: double load fakes tapers and back-to-back crashes.
//

import XCTest
import HealthKit
@testable import HealthAnalytics

final class HealthKitWorkoutRefreshTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_790_000_000)

    private func healthKitRide(offset: TimeInterval = 0, minutes: Double = 60,
                               type: HKWorkoutActivityType = .cycling) -> WorkoutData {
        let s = start.addingTimeInterval(offset)
        return WorkoutData(workoutType: type, startDate: s, endDate: s.addingTimeInterval(minutes * 60),
                           duration: minutes * 60, totalEnergyBurned: nil, totalDistance: nil,
                           averagePower: nil, averageHeartRate: 140, source: .appleWatch)
    }

    private func storedStravaRide(offset: TimeInterval = 0, minutes: Double = 60) -> StravaImportData {
        StravaImportData(id: "strava-1", title: "Ride", workoutType: .cycling,
                         startDate: start.addingTimeInterval(offset), duration: minutes * 60,
                         distance: nil, power: 200, normalizedPower: 210, energy: nil, averageHeartRate: 140)
    }

    /// Review focus 1.
    func test_rideAlreadyStoredAsStrava_isNotUpsertedAgain() {
        let result = DataPersistenceActor.healthKitWorkoutsNotCoveredByStrava(
            [healthKitRide()], storedStrava: [storedStravaRide(offset: 30)])
        XCTAssertTrue(result.isEmpty)
    }

    func test_rideWithNoStravaCopy_isKept() {
        let result = DataPersistenceActor.healthKitWorkoutsNotCoveredByStrava(
            [healthKitRide()], storedStrava: [])
        XCTAssertEqual(result.count, 1)
    }

    func test_differentActivityAtTheSameTime_isKept() {
        let result = DataPersistenceActor.healthKitWorkoutsNotCoveredByStrava(
            [healthKitRide(type: .running)], storedStrava: [storedStravaRide()])
        XCTAssertEqual(result.count, 1, "A run overlapping a stored ride is a different workout")
    }

    func test_nonOverlappingRide_isKept() {
        let result = DataPersistenceActor.healthKitWorkoutsNotCoveredByStrava(
            [healthKitRide(offset: 6 * 3600)], storedStrava: [storedStravaRide()])
        XCTAssertEqual(result.count, 1)
    }
}
```

- [ ] **Step 2: Run them and confirm they fail.**

Run: `xcodebuild test … -only-testing:HealthAnalyticsTests/HealthKitWorkoutRefreshTests`
Expected: a build failure, because `healthKitWorkoutsNotCoveredByStrava` doesn't exist yet.

- [ ] **Step 3: Implement the filter and the actor method** inside `actor DataPersistenceActor`, directly after `upsertRecentData`:

```swift
    /// HealthKit-only workout upsert for the background pattern pass. Rides the
    /// foreground already stored as their Strava copy are skipped: `upsertRecentData`
    /// matches HealthKit workouts only against the Strava list it is handed, and the
    /// background hands it none, so without this filter a stored Strava ride would gain
    /// a second HealthKit-UUID row (double load). A ride not yet on Strava is stored
    /// under its HealthKit UUID; the next foreground sync's match replaces it.
    func upsertHealthKitWorkoutsOnly(_ workouts: [WorkoutData], since: Date) {
        let windowStart = since.addingTimeInterval(-86400)
        let descriptor = FetchDescriptor<StoredWorkout>(
            predicate: #Predicate { $0.startDate >= windowStart && $0.source == "Strava" }
        )
        let storedStrava = ((try? modelContext.fetch(descriptor)) ?? []).map(Self.stravaImport(from:))
        let uncovered = Self.healthKitWorkoutsNotCoveredByStrava(workouts, storedStrava: storedStrava)
        guard !uncovered.isEmpty else { return }
        upsertRecentData(workouts: uncovered, strava: [], sleep: [], hrv: [], rhr: [],
                         steps: [], weight: [], nutrition: [], vo2max: [])
    }

    nonisolated static func healthKitWorkoutsNotCoveredByStrava(
        _ healthKit: [WorkoutData],
        storedStrava: [StravaImportData]
    ) -> [WorkoutData] {
        healthKit.filter { WorkoutMatcher.findMatch(for: $0, in: storedStrava) == nil }
    }

    private static func stravaImport(from stored: StoredWorkout) -> StravaImportData {
        StravaImportData(
            id: stored.id,
            title: stored.title ?? "",
            workoutType: HKWorkoutActivityType(rawValue: UInt(stored.workoutTypeInt)) ?? .other,
            startDate: stored.startDate,
            duration: stored.duration,
            distance: stored.distance,
            power: stored.averagePower,
            normalizedPower: stored.normalizedPower,
            energy: stored.totalEnergyBurned,
            averageHeartRate: stored.averageHeartRate
        )
    }
```

If `SyncManager.swift` doesn't import HealthKit, add `import HealthKit` at the top.

- [ ] **Step 4: Add the refresh entry point** to `SyncManager`, directly after `performSmartSync`:

```swift
    private var lastBackgroundWorkoutRefresh: Date? {
        get { UserDefaults.standard.object(forKey: "lastBackgroundWorkoutRefresh") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "lastBackgroundWorkoutRefresh") }
    }

    /// HealthKit-only workout refresh for the background pattern pass. Never calls
    /// Strava, never posts `DataSyncCompleted` (its observer runs the Coach refresh),
    /// and never moves `lastSyncDate` — the next foreground sync must still pull Strava
    /// power data for this window.
    func refreshWorkoutsFromHealthKit(now: Date = Date()) async throws {
        let since = [lastBackgroundWorkoutRefresh, lastSyncDate].compactMap { $0 }.max()
            ?? now.addingTimeInterval(-7 * 86400)
        let start = Calendar.current.date(byAdding: .day, value: -1, to: since) ?? since
        let workouts = try await healthKitManager.fetchWorkouts(startDate: start, endDate: now)
        let dataHandler = DataPersistenceActor(modelContainer: HealthDataContainer.shared)
        await dataHandler.upsertHealthKitWorkoutsOnly(workouts, since: start)
        lastBackgroundWorkoutRefresh = now
    }
```

- [ ] **Step 5: Run the class, then the full lane.** Expected: PASS for both. The new class has 4 tests.

- [ ] **Step 6: Commit.**

```bash
git add HealthAnalytics/Utilities/SyncManager.swift HealthAnalyticsTests/HealthKitWorkoutRefreshTests.swift
git commit -m "feat: HealthKit-only workout refresh that skips rides already stored from Strava

<trailers>"
```

---

### Task 5: `BackgroundPatternPass`, its log, and repository wiring

**Files:**
- Create: `HealthAnalytics/Services/Analytics/BackgroundPatternPass.swift`
- Modify: `HealthAnalytics/HealthAnalytics/Services/Analytics/ReadinessRepository.swift`
- Test: `HealthAnalyticsTests/BackgroundPatternPassTests.swift`

**Interfaces:**
- Consumes:
  - `ReadinessRepository.shouldRunPatternAnalysis(lastRun:trigger:now:)` and `.PatternAnalysisTrigger.background` (existing)
  - `PatternAnalysisError.commitDeclined` / `.insufficientData` (Task 2)
  - `finalizeScoreRows(modelContext:now:)` (Task 3)
  - `SyncManager.refreshWorkoutsFromHealthKit(now:)` (Task 4)
- Produces:
  - `enum BackgroundPassWake: String, CaseIterable, Sendable { case hrvDelivery, workoutDelivery, appRefresh }`
  - `enum BackgroundPassOutcome: String, CaseIterable, Sendable { case skippedLocked, throttled, completed, abandoned, failed }`
  - `@MainActor protocol BackgroundPassSteps`, with the members shown below
  - `@MainActor final class BackgroundPatternPass`:
    - `init(steps:log:now:)`
    - `@discardableResult func run() async -> BackgroundPassOutcome`
    - `nonisolated static let maxDuration`
    - `nonisolated static func isWithinBudget(startedAt:now:) -> Bool`
  - `@MainActor struct BackgroundPassLog`:
    - `init(defaults:)`, `static var standard`
    - `recordWake(_:)`, `record(_:at:)`, `recordLatency(_:)`
    - `count(_ wake:)`, `count(_ outcome:)`
    - `lastOutcome: BackgroundPassOutcome?`, `lastOutcomeAt: Date?`, `lastLatency: TimeInterval?`
  - `ReadinessRepository.runBackgroundPass(container: ModelContainer, wake: BackgroundPassWake) async`

- [ ] **Step 1: Write the failing tests** in `HealthAnalyticsTests/BackgroundPatternPassTests.swift`:

```swift
//
//  BackgroundPatternPassTests.swift
//  HealthAnalyticsTests
//
//  The pass's ordering, skip rules, abandon rule and stamp, against fake steps and a
//  fake clock — no singleton, no HealthKit.
//

import XCTest
@testable import HealthAnalytics

@MainActor
private final class FakeClock: @unchecked Sendable {
    var now: Date
    init(_ now: Date) { self.now = now }
}

@MainActor
private final class FakeSteps: BackgroundPassSteps {
    var protectedDataAvailable = true
    var lastRun: Date?
    var analyzeError: Error?
    var refreshWorkoutsError: Error?
    /// Advances the fake clock during analysis, before the gate is asked.
    var advanceDuringAnalysis: TimeInterval = 0
    var newestHRV: Date?
    let clock: FakeClock

    private(set) var calls: [String] = []
    private(set) var stamped: Date?
    private(set) var gateResult: Bool?

    init(clock: FakeClock) { self.clock = clock }

    func isProtectedDataAvailable() -> Bool { protectedDataAvailable }
    func lastPatternRun() -> Date? { lastRun }
    func refreshWorkouts() async throws {
        calls.append("refreshWorkouts")
        if let refreshWorkoutsError { throw refreshWorkoutsError }
    }
    func finalizeScoreRows() async { calls.append("finalizeScoreRows") }
    func analyzePatterns(commitGate: @escaping @Sendable () async -> Bool) async throws {
        calls.append("analyze")
        if let analyzeError { throw analyzeError }
        clock.now = clock.now.addingTimeInterval(advanceDuringAnalysis)
        let ok = await commitGate()
        gateResult = ok
        if !ok { throw PatternAnalysisError.commitDeclined }
        calls.append("commit")
    }
    func stamp(_ startedAt: Date) { calls.append("stamp"); stamped = startedAt }
    func refreshCoachIfForeground() async { calls.append("coach") }
    func newestHRVSampleDate() async -> Date? { newestHRV }
}

private struct SomeHealthKitError: Error {}

@MainActor
final class BackgroundPatternPassTests: XCTestCase {
    private var defaults: UserDefaults!
    private let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    override func setUp() {
        defaults = UserDefaults(suiteName: "BackgroundPatternPassTests")
        defaults.removePersistentDomain(forName: "BackgroundPatternPassTests")
    }

    private func makePass(_ steps: FakeSteps, _ clock: FakeClock) -> (BackgroundPatternPass, BackgroundPassLog) {
        let log = BackgroundPassLog(defaults: defaults)
        let pass = BackgroundPatternPass(steps: steps, log: log, now: { MainActor.assumeIsolated { clock.now } })
        return (pass, log)
    }

    func test_completedPass_runsStepsInOrder_andStampsTheStartTime() async {
        let clock = FakeClock(t0)
        let steps = FakeSteps(clock: clock)
        steps.advanceDuringAnalysis = 20
        let (pass, log) = makePass(steps, clock)

        let outcome = await pass.run()

        XCTAssertEqual(outcome, .completed)
        XCTAssertEqual(steps.calls, ["refreshWorkouts", "finalizeScoreRows", "analyze", "commit", "stamp", "coach"])
        XCTAssertEqual(steps.stamped, t0, "The stamp describes the data the run read: its start, not its end")
        XCTAssertEqual(log.count(.completed), 1)
    }

    func test_locked_skipsEveryStep() async {
        let clock = FakeClock(t0)
        let steps = FakeSteps(clock: clock)
        steps.protectedDataAvailable = false
        let (pass, log) = makePass(steps, clock)

        let outcome = await pass.run()

        XCTAssertEqual(outcome, .skippedLocked)
        XCTAssertTrue(steps.calls.isEmpty)
        XCTAssertEqual(log.count(.skippedLocked), 1)
    }

    /// Review focus 2: a burst of deliveries inside the 5-minute window does nothing.
    func test_burstWithinThrottleWindow_isThrottled() async {
        let clock = FakeClock(t0)
        let steps = FakeSteps(clock: clock)
        steps.lastRun = t0.addingTimeInterval(-60)
        let (pass, log) = makePass(steps, clock)

        let outcome = await pass.run()

        XCTAssertEqual(outcome, .throttled)
        XCTAssertTrue(steps.calls.isEmpty)
        XCTAssertEqual(log.count(.throttled), 1)
    }

    func test_runSpanningASuspension_isAbandoned_withoutStampOrCommit() async {
        let clock = FakeClock(t0)
        let steps = FakeSteps(clock: clock)
        steps.advanceDuringAnalysis = BackgroundPatternPass.maxDuration + 1
        let (pass, log) = makePass(steps, clock)

        let outcome = await pass.run()

        XCTAssertEqual(outcome, .abandoned)
        XCTAssertEqual(steps.gateResult, false)
        XCTAssertNil(steps.stamped, "An abandoned run must not stamp, so the next trigger runs fresh")
        XCTAssertFalse(steps.calls.contains("commit"))
        XCTAssertFalse(steps.calls.contains("coach"))
        XCTAssertEqual(log.count(.abandoned), 1)
    }

    /// Review focus 3: the clock moving backwards mid-run is not proof of freshness.
    func test_clockMovedBackwardsMidRun_isAbandoned() async {
        let clock = FakeClock(t0)
        let steps = FakeSteps(clock: clock)
        steps.advanceDuringAnalysis = -3600
        let (pass, _) = makePass(steps, clock)

        let outcome = await pass.run()

        XCTAssertEqual(outcome, .abandoned)
        XCTAssertNil(steps.stamped)
    }

    /// Review focus 4: HealthKit failing is silent and unstamped.
    func test_analysisFailure_isFailed_withoutStamp() async {
        let clock = FakeClock(t0)
        let steps = FakeSteps(clock: clock)
        steps.analyzeError = SomeHealthKitError()
        let (pass, log) = makePass(steps, clock)

        let outcome = await pass.run()

        XCTAssertEqual(outcome, .failed)
        XCTAssertNil(steps.stamped)
        XCTAssertEqual(log.count(.failed), 1)
    }

    /// Fewer than 60 days of history: nothing to keep alive, safe to throttle (as the
    /// foreground does).
    func test_insufficientData_isCompleted_andStamped() async {
        let clock = FakeClock(t0)
        let steps = FakeSteps(clock: clock)
        steps.analyzeError = PatternAnalysisError.insufficientData
        let (pass, _) = makePass(steps, clock)

        let outcome = await pass.run()

        XCTAssertEqual(outcome, .completed)
        XCTAssertEqual(steps.stamped, t0)
    }

    func test_workoutRefreshFailure_doesNotBlockDetection() async {
        let clock = FakeClock(t0)
        let steps = FakeSteps(clock: clock)
        steps.refreshWorkoutsError = SomeHealthKitError()
        let (pass, _) = makePass(steps, clock)

        let outcome = await pass.run()

        XCTAssertEqual(outcome, .completed)
        XCTAssertTrue(steps.calls.contains("analyze"))
    }

    func test_completedPass_recordsLatencyFromTheNewestHRVSample() async {
        let clock = FakeClock(t0)
        let steps = FakeSteps(clock: clock)
        steps.newestHRV = t0.addingTimeInterval(-600)
        steps.advanceDuringAnalysis = 15
        let (pass, log) = makePass(steps, clock)

        _ = await pass.run()

        XCTAssertEqual(log.lastLatency ?? -1, 615, accuracy: 0.001)
    }

    func test_log_countsWakesPerTrigger() {
        let log = BackgroundPassLog(defaults: defaults)
        log.recordWake(.hrvDelivery)
        log.recordWake(.hrvDelivery)
        log.recordWake(.appRefresh)
        XCTAssertEqual(log.count(.hrvDelivery), 2)
        XCTAssertEqual(log.count(.appRefresh), 1)
        XCTAssertEqual(log.count(.workoutDelivery), 0)
    }

    func test_isWithinBudget_edges() {
        XCTAssertTrue(BackgroundPatternPass.isWithinBudget(startedAt: t0, now: t0))
        XCTAssertTrue(BackgroundPatternPass.isWithinBudget(startedAt: t0, now: t0.addingTimeInterval(BackgroundPatternPass.maxDuration)))
        XCTAssertFalse(BackgroundPatternPass.isWithinBudget(startedAt: t0, now: t0.addingTimeInterval(BackgroundPatternPass.maxDuration + 0.001)))
        XCTAssertFalse(BackgroundPatternPass.isWithinBudget(startedAt: t0, now: t0.addingTimeInterval(-1)))
    }
}
```

- [ ] **Step 2: Run them and confirm they fail.**

Run: `xcodebuild test … -only-testing:HealthAnalyticsTests/BackgroundPatternPassTests`
Expected: a build failure, because the types don't exist yet.

- [ ] **Step 3: Implement the pass** in `HealthAnalytics/Services/Analytics/BackgroundPatternPass.swift`:

```swift
//
//  BackgroundPatternPass.swift
//  HealthAnalytics
//
//  The one thing background triggers (HealthKit delivery, app refresh) run. Order:
//  protected-data guard → throttle → HealthKit-only workout refresh → score-row
//  finalization → detection behind a commit gate → stamp (start time) → Coach only
//  if the app is in the foreground. Never posts DataSyncCompleted, never calls Strava.
//

import Foundation
import HealthKit
import SwiftData
import UIKit

enum BackgroundPassWake: String, CaseIterable, Sendable {
    case hrvDelivery, workoutDelivery, appRefresh
}

enum BackgroundPassOutcome: String, CaseIterable, Sendable {
    case skippedLocked, throttled, completed, abandoned, failed
}

@MainActor
protocol BackgroundPassSteps {
    func isProtectedDataAvailable() -> Bool
    func lastPatternRun() -> Date?
    func refreshWorkouts() async throws
    func finalizeScoreRows() async
    /// Detects, then commits only if `commitGate` returns true; throws
    /// `PatternAnalysisError.commitDeclined` when it refuses.
    func analyzePatterns(commitGate: @escaping @Sendable () async -> Bool) async throws
    func stamp(_ startedAt: Date)
    func refreshCoachIfForeground() async
    func newestHRVSampleDate() async -> Date?
}

@MainActor
final class BackgroundPatternPass {
    /// A background budget is ~30s. A run whose detection finishes later than this
    /// after it started spanned a suspension: some reads predate the freeze, some
    /// follow it, so its verdict describes no real moment. Discard it.
    nonisolated static let maxDuration: TimeInterval = 2 * 60

    private let steps: BackgroundPassSteps
    private let log: BackgroundPassLog
    private let now: @Sendable () -> Date

    init(steps: BackgroundPassSteps, log: BackgroundPassLog, now: @escaping @Sendable () -> Date = { Date() }) {
        self.steps = steps
        self.log = log
        self.now = now
    }

    @discardableResult
    func run() async -> BackgroundPassOutcome {
        let outcome = await perform()
        log.record(outcome, at: now())
        return outcome
    }

    private func perform() async -> BackgroundPassOutcome {
        guard steps.isProtectedDataAvailable() else { return .skippedLocked }
        let startedAt = now()
        guard ReadinessRepository.shouldRunPatternAnalysis(
            lastRun: steps.lastPatternRun(), trigger: .background, now: startedAt
        ) else { return .throttled }

        // Neither step may block detection: a stale store is still checked by the gate.
        try? await steps.refreshWorkouts()
        await steps.finalizeScoreRows()

        let clock = now
        do {
            try await steps.analyzePatterns(commitGate: {
                Self.isWithinBudget(startedAt: startedAt, now: clock())
            })
        } catch PatternAnalysisError.commitDeclined {
            return .abandoned
        } catch PatternAnalysisError.insufficientData {
            // < 60 days of history: nothing to keep alive, safe to throttle (as the
            // foreground does).
            steps.stamp(startedAt)
            return .completed
        } catch {
            // Silent in the background (HealthKit refuses reads while locked, or
            // isn't authorized). Unstamped, so the next trigger retries.
            return .failed
        }

        steps.stamp(startedAt)
        if let newest = await steps.newestHRVSampleDate() {
            log.recordLatency(now().timeIntervalSince(newest))
        }
        await steps.refreshCoachIfForeground()
        return .completed
    }

    /// Inside the budget and not before the start (a clock moved backwards proves
    /// nothing about freshness).
    nonisolated static func isWithinBudget(startedAt: Date, now: Date) -> Bool {
        let elapsed = now.timeIntervalSince(startedAt)
        return elapsed >= 0 && elapsed <= maxDuration
    }
}

/// Counters for the debug "Background Pass" screen: how often each trigger wakes the
/// app, how each pass ends, and how long after the newest HRV sample a pass committed.
@MainActor
struct BackgroundPassLog {
    let defaults: UserDefaults

    init(defaults: UserDefaults) { self.defaults = defaults }

    static var standard: BackgroundPassLog { BackgroundPassLog(defaults: .standard) }

    func recordWake(_ wake: BackgroundPassWake) { increment("backgroundPass.wake.\(wake.rawValue)") }

    func record(_ outcome: BackgroundPassOutcome, at date: Date) {
        increment("backgroundPass.outcome.\(outcome.rawValue)")
        defaults.set(outcome.rawValue, forKey: "backgroundPass.lastOutcome")
        defaults.set(date, forKey: "backgroundPass.lastOutcomeAt")
    }

    func recordLatency(_ seconds: TimeInterval) {
        defaults.set(seconds, forKey: "backgroundPass.lastLatency")
    }

    func count(_ wake: BackgroundPassWake) -> Int { defaults.integer(forKey: "backgroundPass.wake.\(wake.rawValue)") }
    func count(_ outcome: BackgroundPassOutcome) -> Int { defaults.integer(forKey: "backgroundPass.outcome.\(outcome.rawValue)") }

    var lastOutcome: BackgroundPassOutcome? {
        defaults.string(forKey: "backgroundPass.lastOutcome").flatMap(BackgroundPassOutcome.init(rawValue:))
    }
    var lastOutcomeAt: Date? { defaults.object(forKey: "backgroundPass.lastOutcomeAt") as? Date }
    var lastLatency: TimeInterval? { defaults.object(forKey: "backgroundPass.lastLatency") as? TimeInterval }

    private func increment(_ key: String) { defaults.set(defaults.integer(forKey: key) + 1, forKey: key) }
}

/// Production steps. Not unit-tested (singleton + HealthKit); see the device checklist.
@MainActor
struct LiveBackgroundPassSteps: BackgroundPassSteps {
    let repository: ReadinessRepository
    let container: ModelContainer

    func isProtectedDataAvailable() -> Bool { UIApplication.shared.isProtectedDataAvailable }

    func lastPatternRun() -> Date? {
        UserDefaults.standard.object(forKey: "lastPatternAnalysisDate") as? Date
    }

    func refreshWorkouts() async throws { try await SyncManager.shared.refreshWorkoutsFromHealthKit() }

    func finalizeScoreRows() async { await repository.finalizeScoreRows(modelContext: container.mainContext) }

    func analyzePatterns(commitGate: @escaping @Sendable () async -> Bool) async throws {
        try await repository.analyzePatternsForBackgroundPass(container: container, commitGate: commitGate)
    }

    func stamp(_ startedAt: Date) { UserDefaults.standard.set(startedAt, forKey: "lastPatternAnalysisDate") }

    func refreshCoachIfForeground() async {
        guard repository.isAppInForeground() else { return }
        await repository.refreshIfNecessary(modelContext: container.mainContext)
    }

    func newestHRVSampleDate() async -> Date? {
        await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKQuantityType(.heartRateVariabilitySDNN),
                predicate: nil,
                limit: 1,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
            ) { _, samples, _ in
                continuation.resume(returning: samples?.first?.endDate)
            }
            HKHealthStore().execute(query)
        }
    }
}
```

- [ ] **Step 4: Run the class.** Expected: PASS (11 tests).

If the compiler rejects the `now:` closure in `makePass` because of actor isolation, replace the closure body with `clock.now`. If it then rejects `FakeClock` capture, mark `FakeClock` `nonisolated` and keep `@unchecked Sendable`.

- [ ] **Step 5: Wire the repository.** In `ReadinessRepository.swift`, add a shared preference accessor near `performPatternAnalysis`:

```swift
    private var hrvSourcePreference: HRVSourcePreference {
        HRVSourcePreference(
            rawValue: UserDefaults.standard.string(forKey: "preferredHRVSource") ?? HRVSourcePreference.auto.rawValue
        ) ?? .auto
    }
```

Replace the `let preference = HRVSourcePreference(…) ?? .auto` block inside `performPatternAnalysis` with `let preference = hrvSourcePreference`.

Then add, directly after `runPatternAnalysis`:

```swift
    /// The background pattern pass (HealthKit delivery, app refresh). Shares
    /// `patternAnalysisFlight` with the foreground, so overlapping wakes and a Recovery
    /// visit during a background run still produce one run.
    func runBackgroundPass(container: ModelContainer, wake: BackgroundPassWake) async {
        let log = BackgroundPassLog.standard
        log.recordWake(wake)
        await patternAnalysisFlight.run { [self] in
            let steps = LiveBackgroundPassSteps(repository: self, container: container)
            await BackgroundPatternPass(steps: steps, log: log).run()
        }
    }

    /// Detection + gated commit for the background pass, on the same analyzer instance
    /// as the foreground. Throws what `analyze` throws, including `.commitDeclined`.
    func analyzePatternsForBackgroundPass(
        container: ModelContainer,
        commitGate: @escaping @Sendable () async -> Bool
    ) async throws {
        if trainingDNAAnalyzer == nil {
            trainingDNAAnalyzer = TrainingDNAAnalyzer(modelContainer: container)
        }
        let historyDays = try await trainingDNAAnalyzer!.analyze(
            sourcePreference: hrvSourcePreference,
            commitGate: commitGate
        )
        UserDefaults.standard.set(historyDays, forKey: "healthKitHistoryDays")
    }
```

If `isAppInForeground` is private, make it internal. It must be callable from `LiveBackgroundPassSteps`.

- [ ] **Step 6: Run the full lane.** Expected: PASS.

- [ ] **Step 7: Commit.**

```bash
git add HealthAnalytics/Services/Analytics/BackgroundPatternPass.swift HealthAnalytics/HealthAnalytics/Services/Analytics/ReadinessRepository.swift HealthAnalyticsTests/BackgroundPatternPassTests.swift
git commit -m "feat: BackgroundPatternPass with commit-gated detection, start-time stamp and outcome log

<trailers>"
```

---

### Task 6: Triggers (HealthKit background delivery and app refresh)

**Files:**
- Create: `HealthAnalytics/Services/HealthKit/HealthDataObserver.swift`
- Modify: `HealthAnalytics/HealthAnalyticsApp.swift`
- Modify: `HealthAnalytics/HealthAnalytics.entitlements`
- Test: `HealthAnalyticsTests/HealthDataObserverTests.swift`

**Interfaces:**
- Consumes: `ReadinessRepository.runBackgroundPass(container:wake:)` and `BackgroundPassWake` (Task 5).
- Produces:
  - `@MainActor final class HealthDataObserver { static let shared; func register(onUpdate: @escaping @MainActor (BackgroundPassWake) async -> Void) }`
  - `static func handleUpdate(wake:run:completion:) async`
  - `final class AppDelegate: NSObject, UIApplicationDelegate`

- [ ] **Step 1: Write the failing tests** in `HealthAnalyticsTests/HealthDataObserverTests.swift`:

```swift
//
//  HealthDataObserverTests.swift
//  HealthAnalyticsTests
//
//  iOS backs off HealthKit background delivery for an app that leaves an observer
//  update uncompleted, so the completion must run on every outcome.
//

import XCTest
@testable import HealthAnalytics

@MainActor
final class HealthDataObserverTests: XCTestCase {

    func test_handleUpdate_runsThePassForTheWake_thenCompletes() async {
        var ran: BackgroundPassWake?
        var completed = 0
        await HealthDataObserver.handleUpdate(
            wake: .hrvDelivery,
            run: { ran = $0 },
            completion: { completed += 1 }
        )
        XCTAssertEqual(ran, .hrvDelivery)
        XCTAssertEqual(completed, 1)
    }

    /// Review focus 4: the completion fires even when the pass ends early (locked,
    /// throttled, failed) — `run` returning is all the handler waits for.
    func test_handleUpdate_completesExactlyOnceWhenThePassReturnsImmediately() async {
        var completed = 0
        await HealthDataObserver.handleUpdate(wake: .workoutDelivery, run: { _ in }, completion: { completed += 1 })
        XCTAssertEqual(completed, 1)
    }

    func test_observedTypes_coverHRVAndWorkouts() {
        let wakes = HealthDataObserver.observedTypes.map(\.wake)
        XCTAssertEqual(Set(wakes), [.hrvDelivery, .workoutDelivery])
    }
}
```

- [ ] **Step 2: Run them and confirm they fail.**

Run: `xcodebuild test … -only-testing:HealthAnalyticsTests/HealthDataObserverTests`
Expected: a build failure, because `HealthDataObserver` doesn't exist yet.

- [ ] **Step 3: Implement the observer** in `HealthAnalytics/Services/HealthKit/HealthDataObserver.swift`:

```swift
//
//  HealthDataObserver.swift
//  HealthAnalytics
//
//  HealthKit background delivery for the signals pattern alerts depend on. iOS
//  relaunches the app in the background for a delivery, and the observer query that
//  receives it must exist by then — so this registers from the app delegate's
//  didFinishLaunching on every launch, not from a view's `.task`.
//

import HealthKit

@MainActor
final class HealthDataObserver {
    static let shared = HealthDataObserver()

    nonisolated static let observedTypes: [(type: HKSampleType, wake: BackgroundPassWake)] = [
        (HKQuantityType(.heartRateVariabilitySDNN), .hrvDelivery),
        (HKObjectType.workoutType(), .workoutDelivery),
    ]

    private let store = HKHealthStore()
    private var queries: [HKObserverQuery] = []

    private init() {}

    /// Idempotent: only the first call registers.
    func register(onUpdate: @escaping @MainActor (BackgroundPassWake) async -> Void) {
        guard queries.isEmpty, HKHealthStore.isHealthDataAvailable() else { return }
        for (type, wake) in Self.observedTypes {
            let query = HKObserverQuery(sampleType: type, predicate: nil) { _, completion, error in
                guard error == nil else { completion(); return }
                Task { @MainActor in
                    await Self.handleUpdate(wake: wake, run: onUpdate, completion: completion)
                }
            }
            store.execute(query)
            queries.append(query)
            store.enableBackgroundDelivery(for: type, frequency: .immediate) { enabled, error in
                #if DEBUG
                if !enabled { print("⚠️ Background delivery not enabled for \(type): \(String(describing: error))") }
                #endif
            }
        }
    }

    /// Always calls `completion`, whatever `run` does: iOS backs off delivery for an
    /// app that leaves an observer update uncompleted.
    static func handleUpdate(
        wake: BackgroundPassWake,
        run: (BackgroundPassWake) async -> Void,
        completion: () -> Void
    ) async {
        defer { completion() }
        await run(wake)
    }
}
```

If Swift 6 rejects capturing `completion` (`HKObserverQueryCompletionHandler`) in the `Task`, bind it first with `nonisolated(unsafe) let done = completion` and pass `done`.

- [ ] **Step 4: Run the class.** Expected: PASS (3 tests).

- [ ] **Step 5: Add the entitlement.** In `HealthAnalytics/HealthAnalytics.entitlements`, inside the `<dict>` and after the `com.apple.developer.healthkit` `<true/>`, add:

```xml
	<key>com.apple.developer.healthkit.background-delivery</key>
	<true/>
```

- [ ] **Step 6: Register at launch and switch the app-refresh handler.** In `HealthAnalyticsApp.swift`, add this above `@main`:

```swift
/// Registers HealthKit background delivery at every launch. A delivery relaunches the
/// app in the background, possibly without connecting a scene, so the WindowGroup's
/// `.task` can't be relied on to register in time.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        if UserDefaults.standard.bool(forKey: "isOnboardingComplete") {
            HealthAnalyticsApp.registerHealthDataObserver()
        }
        return true
    }
}
```

Inside `struct HealthAnalyticsApp`, after `patternAnalysisMinBackgroundInterval`, add:

```swift
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// Idempotent. Called at launch (onboarded users) and after onboarding completes.
    @MainActor static func registerHealthDataObserver() {
        HealthDataObserver.shared.register { wake in
            await ReadinessRepository.shared.runBackgroundPass(container: HealthDataContainer.shared, wake: wake)
        }
    }
```

In the onboarded `.task`, directly after `ReadinessRepository.shared.bootstrap()`, add:

```swift
                        // Covers the first session after onboarding, when didFinishLaunching
                        // ran before HealthKit authorization was requested.
                        Self.registerHealthDataObserver()
```

Replace the body of `.backgroundTask(.appRefresh(Self.patternAnalysisTaskID)) { … }` with:

```swift
            // Keep the chain going: iOS runs each request once, and otherwise the next one
            // is only submitted when the user next leaves the app.
            Self.schedulePatternAnalysisTask()
            // The pass owns the locked-device guard, throttle, abandon rule and stamp.
            await ReadinessRepository.shared.runBackgroundPass(container: HealthDataContainer.shared, wake: .appRefresh)
```

- [ ] **Step 7: Run the full lane.** Expected: PASS. `BackgroundRefreshConfigTests` stays green, since Info.plist is unchanged.

- [ ] **Step 8: Commit.**

```bash
git add HealthAnalytics/Services/HealthKit/HealthDataObserver.swift HealthAnalytics/HealthAnalyticsApp.swift HealthAnalytics/HealthAnalytics.entitlements HealthAnalyticsTests/HealthDataObserverTests.swift
git commit -m "feat: HealthKit background delivery for HRV and workouts runs the background pattern pass

<trailers>"
```

---

### Task 7: Debug counters screen, docs and final lane

**Files:**
- Create: `HealthAnalytics/Views/BackgroundPassStatsView.swift`
- Modify: `HealthAnalytics/Views/SettingsView.swift` (~line 89, next to the `WorkoutAuditView` link)
- Modify: `CLAUDE.md`, `TODOS.md`, `CHANGELOG.md`

**Interfaces:**
- Consumes: `BackgroundPassLog`, `BackgroundPassWake`, `BackgroundPassOutcome` (Task 5).

- [ ] **Step 1: Create the view** at `HealthAnalytics/Views/BackgroundPassStatsView.swift`:

```swift
//
//  BackgroundPassStatsView.swift
//  HealthAnalytics
//
//  Debug counters for the background pattern pass: how often HealthKit delivery and
//  app refresh wake the app, how each pass ends, and the latest alert latency.
//

import SwiftUI

struct BackgroundPassStatsView: View {
    private let log = BackgroundPassLog.standard

    var body: some View {
        List {
            Section("Wakes") {
                ForEach(BackgroundPassWake.allCases, id: \.self) { wake in
                    LabeledContent(wake.rawValue, value: "\(log.count(wake))")
                }
            }
            Section("Outcomes") {
                ForEach(BackgroundPassOutcome.allCases, id: \.self) { outcome in
                    LabeledContent(outcome.rawValue, value: "\(log.count(outcome))")
                }
            }
            Section("Last pass") {
                LabeledContent("Outcome", value: log.lastOutcome?.rawValue ?? "none")
                LabeledContent("At", value: log.lastOutcomeAt?.formatted(date: .abbreviated, time: .shortened) ?? "never")
                LabeledContent("HRV → commit", value: log.lastLatency.map { "\(Int($0 / 60)) min" } ?? "n/a")
            }
        }
        .foregroundStyle(Color.textPrimary)
        .navigationTitle("Background Pass")
    }
}
```

Check that `Color.textPrimary` exists in `DESIGN.md` or the color extension (`grep -rn "static let textPrimary" HealthAnalytics`). If it doesn't, use the token the neighbouring Settings rows use.

- [ ] **Step 2: Link it from Settings.** In `SettingsView.swift`, after the `WorkoutAuditView` `NavigationLink`, add:

```swift
                        NavigationLink {
                            BackgroundPassStatsView()
                        } label: {
                            Label("Background Pass", systemImage: "clock.arrow.circlepath")
                        }
```

- [ ] **Step 3: Update CLAUDE.md.**
  - Replace the "**Background pattern analysis is an app-refresh task.**" bullet with one covering:
    - the two triggers (HealthKit delivery for HRV + workouts, registered from `AppDelegate` at every launch; app refresh as backup)
    - `BackgroundPatternPass`'s order (guard, throttle, HealthKit-only workout refresh, `finalizeScoreRows`, gated detection, start-time stamp, Coach only in the foreground)
    - the 2-minute abandon rule
    - the never-post-`DataSyncCompleted` / never-move-`lastSyncDate` / no-Strava rules
    - the Strava-copy filter
    - the debug counters
    - the device checklist
  - Add a sentence to the "**Every pattern surface filters on `TrainingPattern.isActive`**" bullet's area, or a new bullet, stating that store-based checks read complete days ending yesterday (`completeDaysEnd`) and that live HealthKit series include today.
  - Update the taper Tier 1 wording: the recent week is now the 7 complete days ending yesterday, and the baseline is the 21 before that.

- [ ] **Step 4: Update TODOS.md.**
  - Move "Design the background pattern run properly" to `## Completed` with `**Completed:** unreleased (2026-10-27)` and a one-line summary.
  - In "BGProcessingTask Promotion", replace the cross-link sentence with: "The Background Pass counters (Settings → Background Pass) now measure the run rate."
  - In "Taper detection requires all 28 of the last 28 days to have a stored score", add a note that it now counts the 28 complete days ending yesterday.

- [ ] **Step 5: Update CHANGELOG.md** by adding an `## [Unreleased]` section above `## [0.1.15.0]`:

```markdown
## [Unreleased]

### Added

- **Pattern alerts arrive soon after your Health data does.** When a new HRV reading or workout lands in Apple Health, the app now checks your patterns in the background as soon as you unlock your phone, so an illness warning can reach you before you open the app.

### Fixed

- **A day's training is counted in full.** If you opened the app in the afternoon and rode that evening, that day's load used to stay at its afternoon value. Past days are now finished off once they're over.
- **Pattern checks look at complete days.** Taper, back-to-back and the other history checks now use whole days through yesterday, so a half-finished today can't fake or hide a pattern. Today's ride counts from tomorrow.
```

- [ ] **Step 6: Run the full lane.**

Run: `xcodebuild test -project HealthAnalytics.xcodeproj -scheme HealthAnalytics -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -only-testing:HealthAnalyticsTests`
Expected: `** TEST SUCCEEDED **`, 0 `failed (` lines in the full log. The test count rises from 252 by the number of tests added in Tasks 1–6.

- [ ] **Step 7: Commit.**

```bash
git add HealthAnalytics/Views/BackgroundPassStatsView.swift HealthAnalytics/Views/SettingsView.swift CLAUDE.md TODOS.md CHANGELOG.md
git commit -m "docs: background pattern pass, complete-days anchoring; debug counters screen

<trailers>"
```

- [ ] **Step 8: Hand off the device checklist** to the user. These need a real device, because the simulator can't run background delivery:
  1. Lock the phone, write an HRV sample (Health app → Heart Rate Variability → Add Data), then unlock. Within a few minutes, Settings → Background Pass shows `hrvDelivery` +1 and an outcome.
  2. A pattern that newly qualifies sends its notification without the app being opened.
  3. Pause the app in the debugger for more than 2 minutes mid-pass, then resume. The outcome is `abandoned`, and no notification is sent.
  4. Ride, open the app mid-ride-day, ride again that evening, then the next day check the Workout Audit / Load tab: the previous day's load includes both rides.
  5. A ride recorded on both Watch and Strava shows once in Workout Audit after a background wake.
