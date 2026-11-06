# 7-Day Forecast Plan Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the trend-line forecast with a personal 7-day plan (Today plus 6 days) of the hardest effort the rider can absorb, in plain words, and make the Coach agree with it.

**Architecture:** A pure `ForecastPlanner` learns a `ForecastProfile` from daily history and steps forward one day at a time in units of the rider's own spread. `ReadinessRepository` loads the inputs, calls the planner inside `performFullAnalysis`, and passes day 0 and day 1 to `MasterCoachEngine`. Projected ACWR still comes from the one engine, `PredictiveReadinessService`, which gains an optional planned-load argument.

**Tech Stack:** Swift 5 mode with default MainActor isolation, SwiftUI, SwiftData, XCTest. The Xcode project uses synchronized groups, so a new file on disk is already in the target.

**Spec:** `docs/superpowers/specs/2026-11-03-forecast-plan-design.md`

## Global Constraints

- Test lane: `xcodebuild test -project HealthAnalytics.xcodeproj -scheme HealthAnalytics -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -only-testing:HealthAnalyticsTests`
- All readiness logic stays out of ViewModels and views. Views get data through the repository.
- Colors and fonts come from `DESIGN.md` tokens in explicit form (`Color.statusOptimal`), never system colors or dot-shorthand.
- User-facing copy says "recovery", never "readiness". Forecast reasons are facts, not advice.
- Every coaching sentence lives once, in `generateHeuristicMessage`.
- Store-based reads use complete days ending yesterday. A missing score row is unknown, never rest. A day's load is its highest row.
- No score, number or chart on the forecast card. No LLM.
- `ForecastEffort.label` strings stay as they are (`Hard effort OK`, `Moderate training`, `Easy only`, `Rest recommended`).
- Every new `#Predicate` is fetched through an in-memory store in a test.

## Where this plan departs from the spec

The spec leaves these to the builder or could not know them. Craig can veto any of them.

1. **Craig's ruling, 2026-11-06: today's word includes today's workouts.** Day 0's word is the band of `intraDay.currentScore`, the in-day score the Coach shows, so a ride can lower it and it recovers as the day goes on. This replaces the spec's "Today keeps its word". The stepping into tomorrow starts from a score that ignores today's rides (`baseReadiness.score` reads today's workouts through the ACR bracket, so the plan runs `analyzeReadiness` again with workouts before today), and today's ride reaches tomorrow only through its load, so it isn't counted twice. The published morning score is not changed.
2. **The word has to move with the clock, so a cached analysis gets a maximum age.** The in-day score changes with time and steps, and neither is in the fingerprint. `refreshIfNecessary` re-runs when the last analysis is over 15 minutes old. It still runs only on a trigger (open, return to the app, sync). Steps reach today's word through the in-day score but not later days, because they are capped at 20% of a ride day's load and can't impair recovery alone.
3. **Nobody gets two Hard days in a row in this release.** Learned recovery time has a floor of 1 day. Goal 5 allows "until the history says otherwise", but the spec's fast-recoverer scenario stops at one non-hard day. The back-to-back crash rule ("at least the default") therefore holds by construction.
4. **A hard day also needs a load of at least 1.25 × the median training day and at least 1.0.** With the 75th percentile alone, a rider whose rides are all the same counts every ride as hard and never gets a Hard day.
5. **Elevated injury risk caps day 0 and day 1 only.** The risk is assessed for today and can't be projected. The load ceiling governs later days. A ride that pushes risk to high can lower today's word.
6. **Forecast Check replays recovery bands and recovery time only.** Pattern and note history isn't dated, so those caps can't be replayed.

## Planner rules and starting constants

All values are named `static let`s on `ForecastProfile`. The builder may tune them only to satisfy the scenario tests, and must report any change.

| Item | Value |
|---|---|
| Minimum history | 14 scored complete days in the last 28, else nil |
| Normal | median score over the last 28 complete days |
| Spread | `max(1.4826 × MAD, 4.0)` points |
| Bands (`z = (score − normal) / spread`) | Hard `z ≥ 0.2`, Moderate `z ≥ −0.5`, Easy `z ≥ −1.5`, otherwise Rest |
| Training day | load ≥ 1.0 in the last 90 complete days |
| Learned loads (≥ 8 training days) | hard threshold `max(P75, 1.25 × median, 1.0)`; moderate = median; easy = P25, each capped by the level above |
| Fallback loads | hard 3.0, moderate 1.5, easy 0.75, rest 0 |
| Episode | a hard day whose next day has a score and isn't hard; return is the first morning with `z ≥ −0.5`, within 5 days; skip the episode if another hard day comes first |
| Recovery days | median return days, rounded up and clamped to 1...3, with ≥ 4 episodes; else 1 |
| Dip (in spreads) | median next-morning `−z`, clamped to 0.5...2.0, with ≥ 4 episodes; else 1.0 |
| Reversion ρ | recovery days 1 → 0.4, 2 → 0.6, 3 → 0.75 |
| Next-day lift (in spreads) | rest +1.0, easy +0.7, moderate +0.35, hard −dip |
| A ride's effect | `1.0 − (1.0 + dip) × load / hardLoad` |

Moderate gives a small lift because the rider's normal already includes the cost of their hard days, so any non-hard day repays some of it.

**Stepping** (`z` starts from `startScore`, which ignores today's rides; day 0's word reads `currentScore`):

```text
z = z(startScore)
for offset in 0...6:
  byRecovery = offset == 0 ? band(z(currentScore)) : band(z)
  caps       = illness, notes, HRV, risk, load ceiling, recovery time, weekly cap
  effort     = max(byRecovery, caps)      // ForecastEffort: larger = more restrictive
  impulse    = lift(effort)
  if offset == 0 and rodeLoadToday > 0: impulse = min(impulse, rideEffect(rodeLoadToday))
  z = rho * z + impulse
```

**Load ceiling reference date:** day 0 closes at `now`, so today's ride counts. Each later day closes at the end of that day and includes earlier planned days. Today's planned entry is `max(0, typicalLoad(day 0 effort) − rodeLoadToday)`, because the ride is already in the workouts.

**Reason, at most one, first match wins:** illness → `Rode hard today` / `Rode today` on day 0 (ride load ≥ hard threshold / ≥ 0.5) → the binding cap, if it is stricter than `byRecovery` → on day 0 below Moderate, `Two short nights` / `Short sleep` / `Low recovery` → `Bouncing back after rest` when the previous day was Rest or Easy and this day is a higher level → nil.

Cap reasons: note category (`Injury`, `Travel`, `Stress`), `HRV dipping`, `Load ramping fast` (ACWR and injury risk), `Still recovering from <weekday>`.

**Short nights:** the count of the latest consecutive nights, up to 2, under 0.85 × the 28-day median sleep.

## Review Focus

1. **A rider whose rides are all the same load:** rides aren't all "hard", and Hard still appears. Pinned by `testUniformRider_ridesAreNotAllHard`.
2. **A rider with scores but almost no training history:** fallback loads apply and Hard is still reachable. Pinned by `testNoTrainingHistory_usesFallbacks`.
3. **Duplicate or missing score rows:** a duplicate day counts once at its highest load, and a missing row is neither rest nor a broken episode score. Pinned by `testHistory_duplicateAndMissingRows`.
4. **A row that says 0 load while a ride is stored that day, or the reverse:** the day's load is the larger of the two. Pinned by `testHistory_rideOnAZeroLoadRowCounts`.
5. **A failed store read, or the app left open past midnight:** a failed read keeps the last plan and never falls back to "no history", and row one reads `Today` only when it really is today. Pinned by `testFailedRead_keepsTheLastPlan` and `testRowTitle_staleFirstDayIsNotToday`.

---

### Task 1: Learn the rider's profile

**Files:**
- Create: `HealthAnalytics/Services/Analytics/ForecastPlanner.swift`
- Test: `HealthAnalyticsTests/ForecastPlannerTests.swift`

**Interfaces:**
- Produces:

```swift
struct ForecastHistoryDay: Equatable { let date: Date; let score: Int?; let load: Double }

struct ForecastProfile: Equatable {
    let normal, spread, hardLoad, moderateLoad, easyLoad, dip: Double
    let recoveryDays, episodeCount: Int
    /// `history` is ascending complete days, ending before `today`. Nil below the 14-score minimum.
    static func learn(history: [ForecastHistoryDay], today: Date, calendar: Calendar) -> ForecastProfile?
    func z(_ score: Double) -> Double
    func band(z: Double) -> ReadinessRepository.ForecastEffort
    var rho: Double { get }
    func typicalLoad(_ effort: ReadinessRepository.ForecastEffort) -> Double
    func rideEffect(load: Double) -> Double
    func isHard(load: Double) -> Bool
}
```

- [ ] **Step 1: Write the failing tests.** Build history with a local `historyDays(_:)` helper.
  - `testLearn_under14Scores_isNil`: 13 scored days returns nil.
  - `testLearn_normalAndSpreadAreRobust`: 27 days at 70 and one at 20 give normal 70 and spread 4.0.
  - `testBand_lowNormalRiderStillGetsHard`: median 55, a score of 58 with spread 4 reads Hard.
  - `testHardDay_isTheTopQuarterOfTrainingLoads`: varied loads 1...8 give `hardLoad == P75`.
  - `testUniformRider_ridesAreNotAllHard`: every load 1.0 gives `isHard(load: 1.0) == false`.
  - `testNoTrainingHistory_usesFallbacks`: all loads 0 give hard 3.0, moderate 1.5, easy 0.75, `recoveryDays == 1`.
  - `testRecovery_slowHistoryLearnsTwoDays`: ≥ 4 episodes, two mornings below normal, gives `recoveryDays == 2` and `rho == 0.6`.
  - `testRecovery_fastHistoryLearnsOneDay`: scores back the next morning gives `recoveryDays == 1` and `dip == 0.5`.
  - `testRecovery_threeEpisodesUsesTheDefault`: 3 episodes give `recoveryDays == 1`, `dip == 1.0`, `episodeCount == 3`.
  - `testRecovery_nextHardDayBeforeReturnSkipsTheEpisode`: back-to-back hard days add no episode.
  - `testRecovery_learnedTimeIsClampedToThree`: 5-day returns give `recoveryDays == 3`.
  - `testRecovery_missingNextDayRowAddsNoEpisode`.

- [ ] **Step 2: Run them and confirm they fail.** Run the lane with `-only-testing:HealthAnalyticsTests/ForecastPlannerTests`. Expected: build failure, `ForecastProfile` not found.
- [ ] **Step 3: Implement `ForecastHistoryDay` and `ForecastProfile`** using the constants table.
- [ ] **Step 4: Run them and confirm they pass.** Expected: all green.
- [ ] **Step 5: Commit** with `feat: learn the rider's normal and recovery speed for the forecast`.

### Task 2: Step the plan forward

**Files:**
- Modify: `HealthAnalytics/Services/Analytics/ForecastPlanner.swift`
- Modify: `HealthAnalytics/HealthAnalytics/Services/Analytics/ReadinessRepository.swift:358-366` (`ReadinessForecastDay` only)
- Modify: `HealthAnalytics/Views/Recovery/ReadinessForecastChart.swift` (minimum edit so the target builds; Task 5 replaces it)
- Remove from `HealthAnalyticsTests/PredictiveIntelligenceTests.swift`: every `testForecast_*` test and the `makeContainerWithWorkouts` / `insertRampWorkouts` helpers (lines 283-403, 1204-1289, about 1378-1468)
- Test: `HealthAnalyticsTests/ForecastPlannerTests.swift`

The old `compute7DayForecast` stays until Task 3. In this task it fills the new `ReadinessForecastDay` from its existing label, so the app keeps building.

**Interfaces:**
- Consumes: `ForecastProfile` (Task 1).
- Produces:

```swift
// Replaces the fields of ReadinessRepository.ReadinessForecastDay
struct ReadinessForecastDay: Identifiable {
    let id = UUID()
    let date: Date
    let effort: ForecastEffort
    let reason: String?
    var coaching: String { effort.label }
}

enum ForecastIllness: Equatable { case none, sick, recovering(daysLeft: Int) }  // daysLeft includes today
struct ForecastNoteCap: Equatable { let cap: ReadinessRepository.ForecastEffort; let reason: String; let until: Date? }

struct ForecastPlanInput {
    let now: Date
    let startScore: Int                 // ignores today's rides; starts the stepping
    let currentScore: Int               // in-day score; decides day 0's word
    let rodeLoadToday: Double
    let recentLoads: [ForecastHistoryDay]
    let profile: ForecastProfile
    var illness: ForecastIllness = .none
    var hrvPrecursorActive = false
    var injuryRiskElevated = false
    var noteCaps: [ForecastNoteCap] = []
    var shortSleepNights = 0
    var hardDaysPerWeekCap: Int? = nil  // release 2 fills this
    /// (window close, planned load by start of day) → ACWR
    let projectedACWR: (Date, [Date: Double]) -> Double
}

enum ForecastPlanner {
    static func plan(_ input: ForecastPlanInput, calendar: Calendar) -> [ReadinessRepository.ReadinessForecastDay]
}
```

- [ ] **Step 1: Write the failing scenario tests.** Use a fixed `now` at noon, normal 75, spread 6 and `projectedACWR` returning 1.0 unless stated.
  - `testCraigsWeek`: `startScore` and `currentScore` 63 (z = −2), no ride. Today Rest, tomorrow Moderate, the day after Hard, and not all 7 Rest.
  - `testNeverTwoHardDaysInARow_byDefault`: start at z = +1; no adjacent Hard days.
  - `testSlowRecoverer_twoNonHardDaysAfterEachHard`: `recoveryDays` 2, dip 1.5.
  - `testFastRecoverer_oneNonHardDayIsEnough`: `recoveryDays` 1, dip 0.5; at least one Hard, gap, Hard with a single gap day.
  - `testBackToBackRule_holdsForTheFastestLearnedRider`: `recoveryDays` 1, dip 0.5; no adjacent Hard days.
  - `testLowNormalRider_getsModerateAndHard`: normal 55.
  - `testRodeHardToday`: `startScore` z = +1, `currentScore` z = −2, `rodeLoadToday` at the hard threshold. Today Rest with `Rode hard today`; tomorrow not Hard.
  - `testTodaysWord_followsTheInDayScore`: same inputs with `currentScore` at z = −1, then z = 0, read Easy, then Moderate (the word recovers as the day goes on). Later days don't change.
  - `testBigRideToday_lowersTomorrowMoreThanASmallRide`.
  - `testRodeToday_smallRide`: load 0.6 reads `Rode today`; load 0.3 shows no ride reason.
  - `testYesterdaysHardRide_capsToday`: `recentLoads` hard yesterday, z = +1. Today Moderate, `Still recovering from <yesterday's weekday>`.
  - `testLoadCeiling_capsAndRelaxes`: closure returns 1.6 for days 0-2, 1.4 for day 3, then 1.0. Days 0-2 at most Easy, day 3 at most Moderate, a later day may be Hard, reason `Load ramping fast`.
  - `testLoadCeiling_isACeilingNeverAFloor`: z = −2, ACWR 1.6; today stays Rest.
  - `testLoadCeiling_day0ClosesNow_laterDaysCarryThePlan`: record the closure's arguments. Day 0 closes at `now`. Day 2's planned loads include day 0 and day 1. Today's planned entry is `max(0, typicalLoad − ride)`.
  - `testHRVPrecursor_capsTodayAndTomorrow`: at most Easy, `HRV dipping`; day 2 is free.
  - `testInjuryRisk_capsTodayAndTomorrow`: at most Moderate; day 2 is free.
  - `testSick_isAllRest`: all 7 Rest, `Sick`.
  - `testRecovering_daysLeftCapThenFree`: `daysLeft: 2`. Days 0-1 at most Easy, `Easing back after illness`; day 2 is free.
  - `testNoteCaps`: Injury caps at Easy; Travel and Stress at Moderate; `until` nil caps all 7; `until` tomorrow noon caps days 0-1 only.
  - `testMostRestrictiveCapWins_reasonNamesIt`: Injury plus ACWR 1.4 gives Easy, `Injury`.
  - `testReason_lowRecoveryToday`: `shortSleepNights` 2 → `Two short nights`; 1 → `Short sleep`; 0 → `Low recovery`.
  - `testReason_bouncingBack`: the day after a planned Rest that moves up reads `Bouncing back after rest`.
  - `testReason_nilWhenTheDayIsObvious`: z = 0 with no caps; day 0 reason nil.
  - `testNeverSevenRestDays_withoutIllness`: `startScore` 0, `recoveryDays` 3, dip 2.0; a non-Rest day by day 4.
  - `testHardDaysPerWeekCap_nilMeansNoCap_oneCapsTheWeek`.

- [ ] **Step 2: Run them and confirm they fail.** Expected: build failure, `ForecastPlanner` not found.
- [ ] **Step 3: Implement `ForecastPlanner.plan`** using the stepping, ceiling and reason rules above. Change `ReadinessForecastDay`, adapt the chart's data use to `effort` so it compiles, and delete the old forecast tests listed under Files. Their contract no longer exists.
- [ ] **Step 4: Run the test lane.** Expected: all green, including `MasterCoachEngineTests` and `IllnessLogTests`.
- [ ] **Step 5: Commit** with `feat: plan each day from the one before, with the rider's own caps`.

### Task 3: Wire the plan into analysis

**Files:**
- Modify: `HealthAnalytics/Services/Analytics/PredictiveReadinessService.swift:37-42,132-170`
- Modify: `HealthAnalytics/HealthAnalytics/Services/Analytics/ReadinessRepository.swift` (`performFullAnalysis:760-765,851-853,870-877`, `compute7DayForecast:1163-1276`, `canReuseCachedAnalysis:1362-1379`, `refreshIfNecessary:464-475`, `resetForTesting`)
- Modify: `HealthAnalytics/Services/Coaching/MasterCoachEngine.swift:14-36` (`recoveringDaysLeft` only)
- Modify: `CLAUDE.md` (rewrite the "7-day forecast" bullet to the new contract), `TODOS.md` (add release 2 and close nothing else)
- Test: `HealthAnalyticsTests/ForecastPlanStoreTests.swift`, `HealthAnalyticsTests/ReadinessRepositoryCoachingTests.swift` (holds `ReadinessRepositoryCacheTests`)

**Interfaces:**
- Consumes: `ForecastPlanner.plan`, `ForecastProfile.learn`.
- Produces:

```swift
// PredictiveReadinessService. The default leaves every existing caller unchanged.
func calculateReadiness(stravaActivities:, healthKitWorkouts:, ftpSnapshots:, referenceDate:,
                        plannedDailyLoads: [Date: Double] = [:]) -> ReadinessAssessment

// MasterCoachEngine.IllnessState
/// Days still recovering, counting today; 0 when not recovering. Uses the same rule as `from`.
static func recoveringDaysLeft(_ spells: [(start: Date, end: Date?)], now: Date, calendar: Calendar) -> Int

// ReadinessRepository
/// Complete days in the last 90, ascending. Duplicate days merge by dateString at the highest
/// load, and that row's score. Load = max(row, sum of the day's stored workouts). Throws on a failed fetch.
func loadForecastHistory(context: ModelContext, now: Date) throws -> [ForecastHistoryDay]
/// Hash of the complete-day rows and each stored workout's id and load (rounded to 2 places).
/// Today's row is left out because analysis itself rewrites it. Nil on a failed read.
func forecastInputSignature(context: ModelContext, now: Date) -> Int?
func computeForecastPlan(modelContext: ModelContext, startScore: Int, currentScore: Int,
                         illness: ForecastIllness, activePatterns: Set<PatternType>,
                         memories: [CoachMemoryNote],
                         injuryRisk: InjuryRiskCalculator.RiskLevel,
                         sleep: [HealthDataPoint], now: Date) throws -> [ReadinessForecastDay]?
```

`canReuseCachedAnalysis` gains `forecastSignature: Int? = nil, lastForecastSignature: Int? = nil, maxAge: TimeInterval? = nil`. A nil current signature (failed read) doesn't force a re-run. `refreshIfNecessary` passes `forecastLiveRefreshInterval` (900 s) as `maxAge`.

- [ ] **Step 1: Write the failing tests.** They use an in-memory store with `StoredDailyScore`, `StoredWorkout`, `StoredFTPSnapshot` and a fixed `now` at noon.
  - `testACWR_plannedLoadsCountInsideTheWindowOnly`: a planned load in the acute window raises ACWR; one after `referenceDate` doesn't; an empty dictionary equals today's result.
  - `testStorePlan_under14Rows_isNil`, and `testStorePlan_returnsSevenDaysStartingToday`.
  - `testStorePlan_todaysRowIsNotHistory`: a low score row for today doesn't move normal.
  - `testHistory_duplicateAndMissingRows`.
  - `testHistory_rideOnAZeroLoadRowCounts`.
  - `testStorePlan_rodeHardThisMorning`: a hard stored workout today, with a lowered `currentScore`, gives Today below its pre-ride word with `Rode hard today`, tomorrow not Hard, and a higher projected ACWR than with no ride.
  - `testStorePlan_overloadedRider_capsThenRelaxes`: rows at 88, 21 days of 1h then 7 days of 3h. Near-term at most Easy, and the last day is less restricted than the first.
  - `testStorePlan_poorRecoveryOnWellLoadedRider_staysRest`: normal 80, `startScore` 40.
  - `testStorePlan_activeNotesAndPatterns`: an active Injury note and an active `hrvPrecursor` reach the plan. A `Preference` note and an expired note don't.
  - `testCache_workoutStoredAfterAnalysisChangesThePlan`: the plan and the signature both change.
  - `testCache_zoneBackfillChangingLoadChangesTheSignature`: same workout count and dates, new load.
  - `testCache_todaysRowRewriteDoesNotChangeTheSignature`.
  - `testCanReuse_falseWhenOlderThanMaxAge`: with `maxAge` 900, an analysis 16 minutes old isn't reused and one 14 minutes old is; `maxAge` nil keeps today's behaviour.
  - `testCanReuse_falseWhenForecastSignatureMoved` and `testCanReuse_nilSignatureDoesNotForceARerun`.
  - `testRecoveringDaysLeft`: last sick day yesterday gives 2; two days ago gives 1; three days ago gives 0.
  - `testFailedRead_keepsTheLastPlan`: a repository test through a seam that makes the plan read throw. `forecast` keeps a same-day plan and is nil only when that plan is from another day.

- [ ] **Step 2: Run them and confirm they fail.** Expected: build failure on the new signatures.
- [ ] **Step 3: Add `plannedDailyLoads`** to `calculateReadiness` and both load windows, using the same `>= window start && <= referenceDate` rule. Keep all the math in that service.
- [ ] **Step 4: Replace `compute7DayForecast` with `computeForecastPlan`.** Remove the comment rejecting intra-forecast simulation. Map `Injury` to Easy and `Travel` and `Stress` to Moderate, using `isCurrentlyActive` and `expiresAt`. In `performFullAnalysis`, compute `startScore` from a second `analyzeReadiness` call with `workouts.filter { $0.startDate < today }` (falling back to `baseReadiness.score`), and fetch patterns, illness and notes before the plan. Keep the single forced-backfill retry when the plan is nil. Store `lastForecastSignature` with the other cache keys and clear it in `resetForTesting`.
- [ ] **Step 5: Rewrite the CLAUDE.md bullet and add release 2 to TODOS.md**, including the note that this release's plan can schedule alternating Hard days until that cap exists.
- [ ] **Step 6: Run the test lane.** Expected: all green.
- [ ] **Step 7: Commit** with `feat: build the forecast plan live from everything stored up to now`.

### Task 4: Make the Coach agree

**Files:**
- Modify: `HealthAnalytics/Services/Coaching/MasterCoachEngine.swift:38-67,100-126,129-221`
- Modify: `HealthAnalytics/HealthAnalytics/Services/Analytics/ReadinessRepository.swift:760-781`
- Test: `HealthAnalyticsTests/MasterCoachEngineTests.swift`, `HealthAnalyticsTests/ForecastPlanStoreTests.swift`

**Interfaces:**
- Consumes: `ReadinessForecastDay.effort` and `.coaching`.
- Produces: `StateVector.todayEffort: ReadinessRepository.ForecastEffort?`, default nil. When nil, today's score-band wording is unchanged, so existing tests stay valid and a rider under 14 days keeps a paragraph.

Exact copy when `todayEffort` is set (the percentage is `currentScore`; both paths keep their suffixes):

| Effort | Generic sentence |
|---|---|
| Hard | `You're N% recovered, which is high for you. You're ready for intensity today.` |
| Moderate | `You're N% recovered — enough for moderate work, but listen to your body.` |
| Easy | `You're N% recovered, a bit below your usual. Keep today easy.` |
| Rest | `Your recovery is well below your usual (N%). Prioritize rest to bounce back.` |

The peak and taper sentences appear only on Hard (the current ≥ 80 copy) and Moderate (the current ≥ 60 copy).

Injury-risk branch: `You're N% recovered, but injury risk is elevated from load spikes.` followed by `Keep today moderate, with no hard sessions.` / `Keep today easy.` / `Take today off.` for the plan's word.

Intraday branch: `StateVector.startedLow: Bool?` (default nil, which keeps `morningScore < 70`) picks "primed" or "fatigued", so a low-normal rider isn't told they started fatigued. The repository sets it from `band(z(startScore))` being Easy or Rest. When `todayEffort` is set, the branch's closing sentence uses the word: Hard `You still have room for hard work today.`, Moderate `You still have room for moderate work today.`, Easy `Keep the rest of today easy.`, Rest `Rest for the remainder of the day.`

- [ ] **Step 1: Write the failing tests.**
  - `testTodayEffort_eachWordUsesItsSentence`: all four, with a score that would have chosen a different band.
  - `testTodayEffort_nilKeepsScoreBands`.
  - `testTodayEffort_injuryRiskNeverSaysEasierThanThePlan`: Moderate gets the Moderate sentence and not `easy aerobic`.
  - `testTodayEffort_lowNormalRiderIsNotCalledFatigued`: morning 62, current 50, `startedLow` false, Easy.
  - `testTodayEffort_afterARideTheClosingSentenceMatchesTheWord`: morning 85, current 70, all four words, and none says `active recovery`.
  - `testTodayEffort_peakWindowNeverShownOnARestDay`.
  - `testSickStillOverridesThePlan`.
  - `testCoachAgreement_todayAndTomorrowMatchThePlan` in `ForecastPlanStoreTests`: build a plan from the store, then assert that a `StateVector` built by the new repository helper `coachState(plan:...)` has `todayEffort == plan[0].effort` and `nextDayForecast == plan[1].coaching`.

- [ ] **Step 2: Run them and confirm they fail.** Expected: build failure, `todayEffort` not found.
- [ ] **Step 3: Add `todayEffort`, the copy above, and the prompt line in `synthesizeWithLLM`.** Extract `coachState(plan:...)` in the repository so the test reads the real wiring.
- [ ] **Step 4: Run the test lane.** Expected: all green, including the banned-phrase tests.
- [ ] **Step 5: Commit** with `feat: Coach uses the plan's word for today and tomorrow`.

### Task 5: Show the plan as a list

**Files:**
- Rename: `HealthAnalytics/Views/Recovery/ReadinessForecastChart.swift` → `HealthAnalytics/Views/Recovery/ForecastPlanCard.swift`, struct `ForecastPlanCard`
- Modify: `HealthAnalytics/Views/Recovery/RecoveryTabView.swift:115-116`
- Test: `HealthAnalyticsTests/ForecastPlannerTests.swift`

**Interfaces:**
- Consumes: `ReadinessRepository.forecast`.
- Produces: `extension ReadinessRepository.ForecastEffort { var word: String; var light: Color }`, and `ForecastPlanCard.rowTitle(for date: Date, now: Date, calendar: Calendar) -> String`.

Words are `Rest`, `Easy`, `Moderate`, `Hard`. Lights are `Color.statusWarning` for Rest, `Color.statusMonitoring` for Easy, and `Color.statusOptimal` for Moderate and Hard. The row title is `Today` when the date is today, otherwise the wide weekday.

- [ ] **Step 1: Write the failing tests.** `testRowTitle_todayAndWeekday`, `testRowTitle_staleFirstDayIsNotToday` (yesterday's date reads its weekday), `testEffortWordAndLight_matchTheSpecTable`.
- [ ] **Step 2: Run them and confirm they fail.** Expected: build failure, `ForecastPlanCard` not found.
- [ ] **Step 3: Replace the chart with 7 rows** of light, title, word and an optional reason in secondary text. Read `DESIGN.md` first. Remove `import Charts` and all chart code. Keep the card chrome and the empty state. Give each row one combined accessibility label (for example `Tuesday, Moderate, Still recovering from Monday`), so the color isn't the only signal. Add a `#Preview` with fixture days in the forecast's shape.
- [ ] **Step 4: Run the test lane, then build and look at the card** in the simulator using the `run` skill. Expected: tests green, and on screen 7 rows with no number or chart.
- [ ] **Step 5: Commit** with `feat: forecast card shows a light, one word and a short reason per day`.

### Task 6: Settings → Forecast Check

**Files:**
- Modify: `HealthAnalytics/Services/Analytics/ForecastPlanner.swift`
- Modify: `HealthAnalytics/HealthAnalytics/Services/Analytics/ReadinessRepository.swift`
- Create: `HealthAnalytics/Views/ForecastCheckView.swift`
- Modify: `HealthAnalytics/Views/SettingsView.swift:95-99`
- Test: `HealthAnalyticsTests/ForecastPlannerTests.swift`

**Interfaces:**
- Consumes: `ForecastProfile.learn`, `ForecastPlanner.plan`, `loadForecastHistory`.
- Produces:

```swift
struct ForecastCheckResult: Equatable {
    struct Miss: Equatable { let date: Date; let suggested, actual: ReadinessRepository.ForecastEffort }
    let daysChecked, exact, withinOne: Int
    let recentMisses: [Miss]        // newest first, at most 10
    let recoveryDays, episodeCount: Int
}
extension ForecastPlanner {
    /// For each of the last `days` days D with a score on D and D+1, learn only from days
    /// before D, plan from D's score and actual load (ACWR held at 1.0, no pattern or note
    /// caps), and compare day 1 with `band(z:)` of D+1's real score.
    static func replay(history: [ForecastHistoryDay], days: Int, today: Date, calendar: Calendar) -> ForecastCheckResult
}
// ReadinessRepository
func forecastCheck(modelContext: ModelContext, now: Date) -> ForecastCheckResult?
```

- [ ] **Step 1: Write the failing tests.**
  - `testReplay_skipsDaysWithoutEnoughEarlierHistory`.
  - `testReplay_skipsDaysMissingAScoreOnEitherSide`.
  - `testReplay_neverSeesTheDayItPredicts`: changing D+1's score changes only the actual, never the suggestion.
  - `testReplay_countsExactAndWithinOne`: a built history with a known result.
  - `testReplay_missesAreNewestFirstAndCapped`.

- [ ] **Step 2: Run them and confirm they fail.** Expected: build failure, `replay` not found.
- [ ] **Step 3: Implement `replay` and `forecastCheck`,** then add a read-only `ForecastCheckView` in the `BackgroundPassStatsView` style: hit rate, exact count, learned recovery days and episode count, recent misses, and an empty state. Link it in Settings next to Background Pass as `Forecast Check`. The view gets its result from the repository, and it can show numbers because it's a debug screen.
- [ ] **Step 4: Run the test lane.** Expected: all green.
- [ ] **Step 5: Commit** with `feat: Forecast Check replays the plan against real next-day recovery`.
