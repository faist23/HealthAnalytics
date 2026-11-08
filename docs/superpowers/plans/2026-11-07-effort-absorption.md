# Effort Absorption Trend Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn Craig's Apple Watch ride ratings into a two-way absorption trend that shifts the 7-day plan, beside HRV, never past a cap.

**Architecture:** A pure `EffortAbsorption` computes each rated ride's felt difference against comparable rides and a decaying 14-day trend. Sync stores each ride's Apple-written rating on `StoredWorkout`. The repository builds the trend from stored rides and passes it to `ForecastPlanner`, which shifts its starting `z`. Effort Check shows the per-ride numbers and the trend.

**Tech Stack:** Swift 5 mode with default MainActor isolation, SwiftUI, SwiftData, HealthKit, XCTest. The Xcode project uses synchronized groups.

**Spec:** `docs/superpowers/specs/2026-11-07-effort-drift-design.md`

## Global Constraints

- Test lane: `xcodebuild test -project HealthAnalytics.xcodeproj -scheme HealthAnalytics -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -only-testing:HealthAnalyticsTests`
- Rides only (`workoutType == .cycling`). Only ratings whose sample source bundle identifier starts with `com.apple.` count.
- Comparable: other rated rides in the last 90 days, duration within 30% and load per hour within 20%. At least 3, else no felt difference.
- Felt difference = rating − median comparable rating; |difference| ≤ 1 counts as 0.
- Trend: rides from the 14 complete days before today, weight `0.5^(ageDays / 4)`, weighted mean. Today's rides don't count.
- Shift: `z` start moves by `−0.5 × trend` spreads, clamped to ±1.0.
- Every existing cap stays a ceiling. The shift never changes day 0's word (day 0 reads `currentScore`).
- Reasons: "Rides feeling harder than usual" or "Rides feeling easier than usual", under the existing one-reason order, after caps and the ride reasons, before "Bouncing back after rest".
- Load comes from `PredictiveReadinessService.calculateWorkoutLoad` (the one engine). No test-only production seams; HealthKit queries and view bodies stay untested.
- Every new `#Predicate` is fetched through an in-memory store in a test.

## Review Focus

1. **The same ride stored twice or a rating matching two stored rides:** a rating lands on one ride, never double-counts. Pinned by `testApplyRatings_oneRatingOneRide`.
2. **A rating that changes or disappears on a later sync:** the stored rating follows Apple Health, and a ride whose rating vanished drops back to nil. Pinned by `testApplyRatings_updatesAndClears`.
3. **A ride with load 0 (no power, no HR path) or under a minute:** no load per hour, so it is neither comparable nor judged. Pinned by `testFeltDifference_zeroLoadRideIsSkipped`.
4. **A felt-easier trend on a capped day:** the lift never raises a day past an illness, note, HRV, load or recovery-time cap. Pinned by `testShift_easierNeverLiftsPastACap`.
5. **A failed rating read during sync:** stored ratings stay as they were; nothing is cleared. Pinned by the call site rule in Task 2 (no seam; reviewed by reading).

---

### Task 1: Felt difference and the trend

**Files:**
- Create: `HealthAnalytics/Services/Analytics/EffortAbsorption.swift`
- Test: `HealthAnalyticsTests/EffortAbsorptionTests.swift`

**Interfaces:**
- Produces:

```swift
struct RatedRide: Equatable { let date: Date; let minutes: Double; let loadPerHour: Double; let rating: Double }

enum EffortAbsorption {
    static let historyDays = 90, trendDays = 14, minimumComparable = 3
    static let durationTolerance = 0.30, intensityTolerance = 0.20
    static let deadBand = 1.0, halfLifeDays = 4.0
    static let shiftPerPoint = 0.5, maximumShift = 1.0
    /// rating − median of comparable earlier-or-later rides in the 90 days before `ride`; nil under 3 comparable.
    static func feltDifference(_ ride: RatedRide, among rides: [RatedRide]) -> Double?
    /// Weighted mean felt difference over the 14 complete days before `now`; 0 with none.
    static func trend(_ rides: [RatedRide], now: Date, calendar: Calendar) -> Double
    /// −shiftPerPoint × trend, clamped to ±maximumShift.
    static func zShift(trend: Double) -> Double
}
```

- [ ] **Step 1: Write the failing tests.**
  - `testFeltDifference_medianOfComparableRides`: four comparable rides rated 5, 5, 6, 7 and a ride rated 8 gives 2.5.
  - `testFeltDifference_underThreeComparableIsNil`.
  - `testFeltDifference_excludesRidesOutsideTolerance`: a 2× longer ride and a 1.5× harder ride don't count.
  - `testFeltDifference_deadBandIsZero`: 1 point above reads 0; −1 reads 0.
  - `testFeltDifference_zeroLoadRideIsSkipped`: loadPerHour 0 or minutes < 1 gives nil and is not comparable to others.
  - `testFeltDifference_ignoresTheRideItself`.
  - `testTrend_weightsRecentRidesMore`: +2 yesterday and 0 eight days ago gives a trend above 1.
  - `testTrend_todaysRidesAndOlderThan14DaysDontCount`.
  - `testTrend_noJudgedRidesIsZero`.
  - `testZShift_signAndClamp`: trend +2 → −1.0; trend −1 → +0.5; trend +5 → −1.0; trend −5 → +1.0.
- [ ] **Step 2: Run them and confirm they fail.** Run the lane with `-only-testing:HealthAnalyticsTests/EffortAbsorptionTests`. Expected: build failure, `EffortAbsorption` not found.
- [ ] **Step 3: Implement `RatedRide` and `EffortAbsorption`** with the constants above.
- [ ] **Step 4: Run them and confirm they pass.**
- [ ] **Step 5: Commit** with `feat: felt difference and absorption trend from rated rides`.

### Task 2: Store Apple-written ratings on rides

**Files:**
- Modify: `HealthAnalytics/Models/StoredWorkout.swift` (add `var effortRating: Double?`, default nil in `init`)
- Modify: `HealthAnalytics/Services/HealthKit/HealthKitManager.swift`
- Modify: `HealthAnalytics/Utilities/SyncManager.swift` (`DataPersistenceActor` and `syncRecentData`)
- Test: `HealthAnalyticsTests/EffortRatingSyncTests.swift`

**Interfaces:**
- Produces:

```swift
struct EffortRatingSample: Equatable, Sendable { let workoutStart: Date; let workoutEnd: Date; let rating: Double }

// HealthKitManager. Rides in the window with their newest Apple-written workoutEffortScore.
func fetchRecentEffortRatings(days: Int = 14, now: Date = Date()) async throws -> [EffortRatingSample]

// DataPersistenceActor
/// For each stored cycling workout starting in the window: the rating whose workout overlaps it by at
/// least half of the shorter of the two, or nil when none does. A rating goes to its single best
/// overlap. Rides outside the window are untouched.
static func applyEffortRatings(_ ratings: [EffortRatingSample], windowStart: Date, in context: ModelContext)
func applyEffortRatings(_ ratings: [EffortRatingSample], windowStart: Date)
```

- `fetchRecentEffortRatings` queries cycling workouts from every source in the window. For each one, it reads all related `workoutEffortScore` samples and keeps the newest whose `sourceRevision.source.bundleIdentifier` starts with `com.apple.`.
- Call site: in `syncRecentData`, after the Strava block (after the `removeStravaRides` step) and only when the HealthKit fetch succeeded. Run `try? await healthKitManager.fetchRecentEffortRatings()`. On nil (a failed read), skip `applyEffortRatings` entirely, so stored ratings stay.

- [ ] **Step 1: Write the failing tests** against an in-memory store (`StoredWorkout`, `StoredFTPSnapshot`):
  - `testApplyRatings_writesToTheOverlappingRide`: a Strava ride stored 9:00-10:00 and a rating for a 9:02-10:01 workout.
  - `testApplyRatings_oneRatingOneRide`: two stored rides overlap one rating; only the larger overlap gets it.
  - `testApplyRatings_updatesAndClears`: a second apply with a new value updates; an apply without it clears to nil.
  - `testApplyRatings_leavesRidesOutsideTheWindowAlone`.
  - `testApplyRatings_ignoresNonCyclingWorkouts`.
- [ ] **Step 2: Run them and confirm they fail.** Expected: build failure on `applyEffortRatings`.
- [ ] **Step 3: Implement** the field, the HealthKit read, the actor method and the call site.
- [ ] **Step 4: Run the full lane.** Expected: all green.
- [ ] **Step 5: Commit** with `feat: sync stores the Watch effort rating on each ride`.

### Task 3: The trend shifts the plan

**Files:**
- Modify: `HealthAnalytics/Services/Analytics/ForecastPlanner.swift`
- Modify: `HealthAnalytics/HealthAnalytics/Services/Analytics/ReadinessRepository.swift` (`ForecastStoreSnapshot`, `loadForecastHistory`, `computeForecastPlan`)
- Modify: `CLAUDE.md` (the 7-day forecast bullet: one sentence on the absorption trend)
- Test: `HealthAnalyticsTests/ForecastPlannerTests.swift`, `HealthAnalyticsTests/ForecastPlanStoreTests.swift`

**Interfaces:**
- Consumes: `EffortAbsorption`, `StoredWorkout.effortRating`.
- Produces: `ForecastPlanInput.absorptionTrend: Double = 0`; `ForecastStoreSnapshot.ratedRides: [RatedRide]` (rides with a rating in the last 90 days plus today's, load from `calculateWorkoutLoad`, load per hour = load ÷ hours); the signature also hashes each workout's rating.

Planner rule: after `var z = profile.z(startScore)`, add `EffortAbsorption.zShift(trend:)`. Keep a second `zUnshifted` stepped with the same impulses. On days 1-6, when `band(z) != band(zUnshifted)` and no stronger reason applies, the reason is "Rides feeling harder than usual" (shift < 0) or "Rides feeling easier than usual" (shift > 0).

- [ ] **Step 1: Write the failing tests.**
  - Planner: `testShift_harderTrendLowersTheComingDays`, `testShift_easierTrendLiftsThem`, `testShift_neverChangesTodaysWord`, `testShift_easierNeverLiftsPastACap` (HRV, note and recovery-time caps), `testShift_reasonNamesTheTrendOnlyWhenItMovedTheDay`, `testShift_zeroTrendChangesNothing`.
  - Store: `testStorePlan_ratedRidesBuildTheTrend` (rides 2 above their comparables lower day 1 vs the same store without ratings), `testCache_newRatingChangesTheSignature`.
- [ ] **Step 2: Run them and confirm they fail.**
- [ ] **Step 3: Implement** the input field, the shift and the reason, the snapshot's rated rides, the trend in `computeForecastPlan`, and the signature. Update the CLAUDE.md bullet.
- [ ] **Step 4: Run the full lane.** Expected: all green, including the existing forecast scenarios (trend 0 changes nothing).
- [ ] **Step 5: Commit** with `feat: how rides feel shifts the plan beside HRV`.

### Task 4: Effort Check shows the numbers

**Files:**
- Modify: `HealthAnalytics/HealthAnalytics/Services/Analytics/ReadinessRepository.swift`
- Modify: `HealthAnalytics/Views/EffortCheckView.swift`
- Modify: `TODOS.md` (the effort-score entry: built in this release; leftovers stay)
- Test: `HealthAnalyticsTests/ForecastPlanStoreTests.swift`

**Interfaces:**
- Produces:

```swift
struct AbsorptionSummary: Equatable {
    struct Ride: Equatable { let date: Date; let rating: Double; let expected: Double?; let difference: Double? }
    let rides: [Ride]          // newest first, last 30 days
    let trend: Double
}
// ReadinessRepository; nil on a failed read.
func absorptionSummary(modelContext: ModelContext, now: Date = Date()) -> AbsorptionSummary?
```

`expected` is the comparable median (nil under 3). The screen gains a section "How rides feel": the trend in plain words ("Rides are feeling about 1.5 points harder than usual", or "about as usual" within ±0.5) and each ride's rating, usual and difference.

- [ ] **Step 1: Write the failing test** `testAbsorptionSummary_readsStoredRatings` (expected and difference per ride, the trend, newest first).
- [ ] **Step 2: Run it and confirm it fails.**
- [ ] **Step 3: Implement** the summary and the section. The view gets data from the repository and fetches nothing itself.
- [ ] **Step 4: Run the full lane.** Expected: all green.
- [ ] **Step 5: Commit** with `feat: Effort Check shows how rides feel against your usual`.
