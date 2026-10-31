# Background Pattern Pass — Design

**Date:** 2026-10-27
**Status:** Draft for review
**Replaces TODO:** P2 "Design the background pattern run properly" (TODOS.md)

## Goal

Timely pattern alerts. When overnight HRV (or a finished workout) lands in Apple Health, the matching pattern notification, most importantly the HRV precursor illness warning, should arrive within minutes of the user's first unlock, without opening the app.

Health data is encrypted while the device is locked, so "first unlock after the data is recorded" is the earliest any design can act. A late alert is better than a wrong one: the pass must never notify from stale or half-synced stores.

"Patterns are already current when I open the app" is a side benefit, not a requirement.

## Decisions (agreed 2026-10-27)

| Question | Decision |
|---|---|
| Purpose | Timely alerts |
| Latency target | Within minutes of the first unlock after new data |
| Ride data source in the background | HealthKit only. All rides reach Apple Health, so Strava is not needed in the background |
| Trigger | HealthKit background delivery (HRV + workouts) as primary, with the existing app-refresh task kept as a backup (approach A) |
| Today's partial data in store-based checks | Complete days everywhere: store-based checks read through yesterday in both the foreground and the background |

Constraints carried over from v0.1.15:
- The background must never run the Coach analysis (`performFullAnalysis` / `MasterCoachEngine`).
- `DataSyncCompleted` must not be posted from the background, because it triggers `refreshIfNecessary`.
- The foreground paths (`.appear`, `.staleCheck`, `.userRetry`, Coach) keep their behaviour, except for the complete-days anchoring below.

## What the detectors read today

| Detector | Live from HealthKit (fresh each run) | From stored tables (stale in the background) |
|---|---|---|
| Block crash cycle | active energy → ACWR | — |
| HRV precursor | HRV, steps | `StoredDailyScore.dailyLoad` (sick-day proxy) |
| Sleep fragmentation | sleep, active energy | — |
| Back-to-back crash | — | `StoredDailyScore.readinessScore`, `.dailyLoad` |
| Performance peak | HRV | `StoredDailyScore.dailyStrain` |
| Taper | HRV | `StoredDailyScore.dailyLoad` (28 days), `StoredWorkout` (corroboration) |

The stored tables are written by the foreground today: `StoredWorkout` by `SyncManager.performSmartSync`, today's score row by `performFullAnalysis` → `upsertDailyScore`, and past score rows by `backfillHistoricalScores`.

A pre-existing gap, NOT fixed here (see Recompute backed out and the TODOS.md entry): `backfillHistoricalScores` skips any day that already has a row. A row written mid-afternoon on the user's last open keeps that partial load forever, including after an evening ride.

## Architecture

### Units

**`BackgroundPatternPass`** (new file, `Services/Analytics/BackgroundPatternPass.swift`, `@MainActor`)
- The only thing background triggers call.
- Owns the step order, the protected-data guard, the start time, the commit gate and outcome recording.
- Depends on a `BackgroundPassSteps` protocol (see below) and an injectable clock, so it can be unit-tested without HealthKit or the repository singleton.
- Its result is `BackgroundPassOutcome`:

```swift
enum BackgroundPassOutcome {
    case skippedLocked
    case throttled
    case completed
    case abandoned
    case failed
}
```

`abandoned` means the run spanned a suspension, so its results were discarded.

As built, the enum also has `skippedForeground` (a wake while the app is in the foreground; see R2) and `skippedSyncing` (a store rewrite is running; see the As built note under Data flow).

**`BackgroundPassSteps`** (protocol; the live implementation lives beside the pass)
As built: `isProtectedDataAvailable`, `lastPatternRun`, `isRewritingStore`, `storeGeneration`, `isAppInForeground`, `lastSyncDate`, `refreshCoach()`, `refreshWorkouts()` (HealthKit-only refresh into `StoredWorkout`), `analyzePatterns(commitGate:)` (detection and the gated commit in one call), `stamp(_:)` and `newestHRVSampleDate()`. The pass decides whether to call `refreshCoach()` (`BackgroundPatternPass.mayRefreshCoach`). There is no score-row step (see Background fill removed) and no separate detect/commit split.

**`HealthDataObserver`** (new file, `Services/HealthKit/HealthDataObserver.swift`)
- Registers one `HKObserverQuery` for `heartRateVariabilitySDNN` and one for `HKWorkoutType`, each with `enableBackgroundDelivery(for:frequency: .immediate)`.
- Its handler runs the pass and calls the observer completion handler in a `defer` on every outcome. iOS backs off delivery when that call is missing.
- It is registered at app launch from a `UIApplicationDelegateAdaptor`'s `application(_:didFinishLaunchingWithOptions:)`, only once HealthKit authorization has been requested (onboarding complete). It is not registered from `bootstrap()`: that runs from the WindowGroup's `.task`, which never runs when iOS relaunches the app in the background for a delivery without connecting a scene. Observers must be registered on every launch, or the delivery that caused the launch has no handler.

**`TrainingDNAAnalyzer`** (changed)
- `analyze()` is split at its existing commit point, just before `upsertPatterns`:
  - `detect(sourcePreference:) -> PatternDetection` returns `historyDays` and the detected patterns. It writes nothing.
  - `commit(_ detection: PatternDetection)` runs `upsertPatterns`, `notifyIfNew` and `save`.
  - As built: there is no detect/commit split. `analyze(sourcePreference:commitGate:)` reads notification authorization, checks the gate, upserts, marks `notificationSent` for authorized types, saves, then calls `PatternNotificationService.send`.
  - `analyze()` stays as `detect` followed by `commit`, so the foreground behaves exactly as before.
- The store-based checks anchor on complete days. See "Complete-days anchoring".

### Triggers

1. **HealthKit background delivery** (primary): a new HRV sample or workout wakes the app soon after the first unlock.
2. **App refresh** (backup): the existing `.backgroundTask(.appRefresh(patternAnalysisTaskID))`. It still resubmits first and still submits on exit only when no request is pending. Its body changes from `runPatternAnalysis(.background)` to running the pass.

Both triggers run the pass through the existing `patternAnalysisFlight`. Overlapping wakes, and a foreground Recovery visit during a background run, still share one run. The `.background` throttle (`forcedPatternAnalysisMinInterval`, 5 minutes) still applies, so a burst of HRV samples does not re-run the pass several times.

## Data flow (one pass)

1. **Guard:** `UIApplication.shared.isProtectedDataAvailable` is false → `skippedLocked`.
2. **Throttle:** `shouldRunPatternAnalysis(lastRun:trigger: .background)` is false → `throttled`.
3. **Record the start:** `startedAt = clock.now`.
4. **Workouts:** `refreshWorkoutsFromHealthKit()`, reading from `healthKitRefreshWindowStart`: the later of the last background refresh and the last sync, else a week back, minus one day.
   - It saves through `DataPersistenceActor.upsertHealthKitWorkoutsOnly`, which drops any HealthKit ride that pairs with a stored Strava workout, and is serialized with the foreground sync by `BackgroundRefreshGate`.
   - It does not call Strava.
   - It does not post `DataSyncCompleted`.
   - It does not touch `SyncManager.lastSyncDate`, so the next open still runs the full foreground sync, including Strava power streams.
   - It stamps its own `lastBackgroundWorkoutRefresh`.
5. **No score-row step.** The pass never fills score rows (see Background fill removed). Missing rows are filled only by the foreground `refreshIfNecessary`, and the detectors treat a missing or stale row as unknown.
6. **Detect:** `detectPatterns()`.
7. **Commit gate:** if `clock.now − startedAt > maxBackgroundPassDuration` (2 minutes; the budget is about 30 seconds), the run spanned a suspension.
   - The result is `abandoned`: no commit, no stamp, no notification.
   - Because nothing was stamped, the next trigger can run straight away.
   - The gate applies to every pass, whoever is waiting on it. A caller that joined a pass which was later frozen and resumed runs its own work once (`SingleFlight.run`), because the abandoned pass reports not-completed.
8. **Commit:** `commitPatterns(detection)`. This upserts the patterns, renewing `detectedAt`, and sends notifications, which stay once ever per pattern through `notificationSent`.
9. **Stamp:** `lastPatternAnalysisDate = startedAt`, not completion time. The stamp then describes the data the run actually read.
10. **Coach:** never in the background. If the app is in the foreground at completion (`isAppInForeground`), run the existing `refreshIfNecessary`, as `performPatternAnalysis` does today.
11. **Record** the outcome (see "Measurement").

As built, the pass differs from the steps above in four places:
- **Rewrite guard** after the throttle: while `SyncManager.isRewritingStore` (a sync, the one-time workout dedup, or the power-zone backfill that runs after a sync or an FTP edit) the pass returns `skippedSyncing` and runs no steps. It records `SyncManager.storeRewriteGeneration` before the workout refresh.
- **Budget check after the workout refresh:** a pass past `BackgroundPatternPass.maxDuration` there returns `abandoned` before detection (no stamp).
- **The commit gate** also refuses when a store rewrite is running at commit or `storeRewriteGeneration` moved since the pass started (a quick sync can start and finish inside detection).
- **Coach** is refreshed only when `BackgroundPatternPass.mayRefreshCoach` holds: app in the foreground, no store rewrite running, and the last sync within `SyncManager.smartSyncMinInterval` (30 minutes). Foreground alone is not enough: a Coach refresh fills missing score rows, and before a sync those rows would get HealthKit-only loads.

## Complete-days anchoring

Store-based checks read complete calendar days ending yesterday, in both the foreground and the background:

| Check | Today (v0.1.15) | After this change |
|---|---|---|
| Taper volume | rows with `date >= now − 28d` (needs today's row to reach 28) | the 28 complete days ending yesterday |
| Taper corroboration (Tier 1 + Tier 2) | recent = today + previous 6 days; baseline = days 7–27 | recent = the 7 days ending yesterday; baseline = the 21 days before that |
| Back-to-back crash, performance peak streak | 90-day rows including today's partial row | 90 complete days ending yesterday |
| HRV precursor sick-day proxy | 180-day rows and live steps, both including today | 180 complete days ending yesterday, for the workout rows and the steps |

Live HealthKit series (HRV, RHR, sleep) keep including today, so a run uses the latest HRV reading. The sick-day proxy's steps are the exception (final-review ruling, overriding the earlier "steps stay live"): today's step count is partial, nearly everyone is under 2000 at 9am, so yesterday + today formed fake sick-day windows. The proxy reads steps over complete days only; HRV stays live.

Consequences:
- A background run and a foreground run on the same data give the same verdict.
- The taper no longer needs today's row.
- A partial day can't skew any check.
- Today's ride counts in these checks from tomorrow onward.

As built: `taperIsCorroborated(endingBefore: completeDaysEnd)`, and every store-based check bounds its reads with `completeDaysEnd` / `completeDayStart(daysBack:)` instead of `Date()`.

## Measurement

The pass records counters in UserDefaults (`backgroundPass.*`):
- wakes by trigger: HRV delivery, workout delivery, app refresh
- one count per outcome
- the last outcome and its time
- the latency from the newest HRV sample's `endDate` to the commit

The existing debug Settings screen (beside `WorkoutAuditView`) shows them in a new "Background Pass" row.

As built (`BackgroundPassLog`, `BackgroundPassStatsView`): wakes also count `launch` (a query's first fire in a process, which iOS fires on registration, so it is not delivery evidence), and every wake counts separately while the app is active; latency is recorded only for HRV-delivery wakes; a `skippedForeground` outcome is counted but never overwrites the last outcome. A few days of real use answer the run-rate question that the "BGProcessingTask Promotion" TODO is waiting on.

## Error handling

- Errors in the background stay silent, as in v0.1.15 (`isAppInForeground` / `isLockedDeviceError`). They are recorded as the `failed` outcome.
- `refreshWorkoutsFromHealthKit` failing does not stop the pass. Detection still runs, and the commit gate still applies.
- The observer completion handler is always called (`defer`).
- The app-refresh task always resubmits before doing anything else.
- `enableBackgroundDelivery` failing is logged (DEBUG). App refresh still covers the run.
- A pass the handler stops waiting on keeps running inside the flight. The commit gate handles the case where it is frozen and resumed later.

## Testing

Unit tests (simulator lane, no singleton, no HealthKit):
- **`BackgroundPatternPassTests`** use a fake `BackgroundPassSteps` and a fake clock. They cover:
  - step order
  - `skippedLocked` and `throttled` short-circuits (no steps run)
  - a step failure that doesn't block detection
  - the abandon rule: a clock advanced past `BackgroundPatternPass.maxDuration` between detect and commit → no commit, no stamp
  - the stamp equals `startedAt`
  - outcome counters
- **`TrainingDNAAnalyzer` detect/commit**, with the existing `MockPatternDataProvider` and in-memory container:
  - `detect` writes nothing (no `TrainingPattern` rows, no notifications)
  - `commit` upserts the patterns and sends notifications
  - `analyze` equals `detect` followed by `commit`
  - As built (no split): `analyze(commitGate:)` tests in `PredictiveIntelligenceTests` (a declined gate writes nothing and keeps an existing pattern; an accepted gate persists as before).
- **Complete-days anchoring:**
  - the taper fires with 28 complete days and no row for today
  - today's partial row is ignored by back-to-back and the taper
  - DST-safe fixtures (`day(n + 1) − 60s` for late-day rides)
- **Config:** `BackgroundRefreshConfigTests` gains the background-delivery entitlement check.

Device checklist (no seam):
- An HRV sample written while the device is locked fires the pass after unlock. Write one with the Health app, or let a Watch reading land.
- A notification arrives without opening the app.
- A pass frozen with the debugger for more than 2 minutes and then resumed records `abandoned` and sends no notification.
- The counters appear in debug Settings.

## Out of scope

- Strava in the background.
- Coach refresh in the background.
- Promoting background analysis to the primary trigger (the existing "BGProcessingTask Promotion" TODO decides that once the counters have data).
- Pattern logic changes beyond the complete-days anchoring.

## Files touched

| File | Change |
|---|---|
| `Services/Analytics/BackgroundPatternPass.swift` | new |
| `Services/HealthKit/HealthDataObserver.swift` | new |
| `Services/Analytics/TrainingDNAAnalyzer.swift` | commit gate; `notificationSent` saved before send; complete-days anchoring |
| `Services/Analytics/ReadinessRepository.swift` | `runBackgroundPass` (background trigger runs the pass), `analyzePatternsForBackgroundPass`, and `runPatternAnalysis`'s flight work returning false only when its commit gate declined (foreground runs use the same commit gate); `backfillHistoricalScores` is unchanged from main. The observer is registered from the AppDelegate's `didFinishLaunching` and right after onboarding in `HealthAnalyticsApp`, not from `bootstrap()` (see Architecture) |
| `Utilities/SyncManager.swift` | `refreshWorkoutsFromHealthKit()` (HealthKit-only, no notification, no `lastSyncDate`; window from `healthKitRefreshWindowStart`); `isRewritingStore` and `storeRewriteGeneration` for the rewrite guard; `noPowerStreamCSV` marks a ride with no watts stream |
| `Utilities/BackgroundRefreshGate.swift` | new: serializes the background upsert with the foreground sync (R6) |
| `Utilities/SingleFlight.swift` | work reports completion; a joiner of an uncompleted run reruns once; `shouldStart` gate |
| `Services/PatternNotificationService.swift` | `isAuthorized()`; `send` takes types, the analyzer marks and saves first |
| `Models/StoredWorkout.swift` | `powerZoneSeconds` is nil for `noPowerStreamCSV` and for all-zero zones |
| `Views/BackgroundPassStatsView.swift` | new: the Background Pass counters screen |
| `HealthAnalyticsApp.swift` | app-refresh handler runs the pass; `UIApplicationDelegateAdaptor` registers `HealthDataObserver` at launch |
| `HealthAnalytics.entitlements` | `com.apple.developer.healthkit.background-delivery` |
| `Views/SettingsView.swift` | debug "Background Pass" counters row |
| `CLAUDE.md`, `TODOS.md` | document the pass and complete-days anchoring; close the P2 |
| Tests | as listed above |

## Post-review changes (2026-10-27)

A red-team review found six holes; each is fixed on this branch. R1, R3 and R4 were later superseded by the structure fix below, which removed the marker they patched.

- **R1. The pass no longer finalizes days.** Before the Strava sync the store may hold only the HealthKit copy of yesterday's ride, so a pass that advanced `scoresFinalizedThrough` froze that day at the HealthKit-only load. `finalizeScoreRows(advancesMarker:)` (default true) is called with false by `LiveBackgroundPassSteps`: the pass recomputes rows, and only the foreground refresh, which runs after the Strava sync, advances the marker. Rule: `ScoreRowFinalization.markerAdvance`.
- **R2. A wake in the foreground skips the pass.** Observer queries fire once at registration, so every foreground cold launch ran a full pass. `runBackgroundPass` records the wake, then `BackgroundPatternPass.skipIfForeground` records the new `skippedForeground` outcome and returns before the flight.
- **R3. One-time 90-day recompute on upgrade.** With no marker, `recomputeRange` now starts at the horizon (today − 90), not yesterday, so mid-day rows the old backfill froze on any of those days are corrected once.
- **R4. HRV or RHR is enough to count as having read HealthKit.** The marker rule no longer requires sleep (`ScoreRowFinalization.readBiometrics`), so users without sleep data advance it.
- **R5. Budget checked between steps; joiners of an abandoned run rerun once.** The pass returns `abandoned` (no detection, no stamp) when the budget is gone after the workout refresh or after finalization. `SingleFlight.run`'s work returns whether it completed; a caller that joined a run that returned false runs its own work (or joins a fresh run another joiner started) exactly once. `runBackgroundPass` returns `outcome != .abandoned`, `runPatternAnalysis` true. (Superseded in part: finalization was removed in S1, so the budget check now follows only the workout refresh, and `runPatternAnalysis`'s work returns false when its commit gate declines; see Files touched.)
- **R6. Background upsert and foreground sync are serialized.** `BackgroundRefreshGate` on `SyncManager` (main actor): `refreshWorkoutsFromHealthKit` does nothing while `isSyncing`, and `performSmartSync` / `resetAllData` wait for an in-flight refresh after setting `isSyncing`, before their own upsert.

## Structure fix (2026-10-28): the marker is removed, not patched

R1, R3 and R4 each patched `scoresFinalizedThrough`, and each review pass found a new way it advanced too early (before the Strava copy of a ride arrived, before HealthKit was readable, with no marker at all on upgrade). Separately, the recompute rewrote whole rows, so a past day's `readinessScore` and `dailyStrain` (ACWR) were overwritten with the backfill's weaker ±1-day biometric estimate. Three fixes that each relocated the violation meant the structure was wrong, so it was replaced.

- **S1. Marker and whole-row recompute removed.** `scoresFinalizedThrough`, `finalizeScoreRows(modelContext:now:advancesMarker:)`, the backfill's `recomputeFrom:` parameter, its recompute branch and duplicate-twin rewrite, its Bool return and `readBiometrics`, and `ScoreRowFinalization` (`recomputeRange`, `markerAdvance`, `readBiometrics`, `maxRecomputeDays`) with its tests are gone. `backfillHistoricalScores` is back to `main`'s shape: it fills missing days only, and still clears `lastPatternAnalysisDate` only when it inserted rows.
- **S2. Trailing 7-day, load-only recompute (BACKED OUT, see below).** `ReadinessRepository.refreshRecentDailyLoads` re-derives `dailyLoad` and `workoutCount` for the 7 complete days ending yesterday from `StoredWorkout` only (no HealthKit read), with `calculateWorkoutLoad`, on every existing row of each day (twins included), only where they differ. It never writes `readinessScore` or `dailyStrain`, never touches today (`upsertDailyScore` owns it), never inserts. A change clears `lastPatternAnalysisDate`. Once on upgrade a 90-day pass runs first (`dailyLoadRecomputeV1Done`, set unconditionally after the run: nothing it reads can come back empty for a transient reason, so there is nothing to gate on). That pass only raises load and count (`onlyRaise`): the original backfill counted HealthKit workouts from before the app's first sync that were never stored as `StoredWorkout`, so a stored-only recompute would wrongly lower those days. The 7-day pass stays exact (the sync stores every HealthKit workout in that range). The pure part is `RecentDailyLoadRefresh` (calendar days, DST-safe). `refreshIfNecessary` runs the backfill and then this; the pass's step is renamed `refreshRecentDailyLoads` and the budget is still checked after it. A ride the pass stores from HealthKit reaches its day at once, and the next foreground refresh re-derives the same week after the Strava sync, so there is no "who may advance" rule to get wrong.
- **S3. A joiner's retry re-checks the foreground.** The skip ran only before the flight, so a wake that joined an abandoned pass and retried after the user opened the app ran a full pass. `BackgroundPatternPass.flightWork` checks inside the work handed to `patternAnalysisFlight` (records `skippedForeground`, reports completed) (superseded in bc04b6e: the check is the flight's `shouldStart` gate, `BackgroundPatternPass.shouldStart`, asked right before a run starts, so a declining wake starts nothing and a foreground caller beside it runs its own analysis); the pre-flight check stays so a foreground wake doesn't join at all.
- **S4. Test gaps.** `BackgroundPatternPass.isCompleted` (only `abandoned` is not completed) over every outcome; `BackgroundRefreshGate`'s join branch and a failing in-flight refresh reaching its joiner; `SyncManager.healthKitRefreshWindowStart` extracted and tested.

## Recompute backed out (2026-10-28)

The S2 trailing 7-day load recompute (`RecentDailyLoadRefresh`, `refreshRecentDailyLoads`, the one-time 90-day upgrade pass) was removed. It trusted `StoredWorkout`, which is not trustworthy: the foreground sync matches HealthKit rides only against the Strava list fetched in that call, so a silent Strava failure stores Health-UUID duplicates of Strava rides (a recompute would double the load); and it can miss rides (late HealthKit writers outside the `lastSyncDate - 1 day` window, and swallowed sync errors that still advance `lastSyncDate`). Every variant (finalized-through marker, foreground-only marker, trailing recompute) inherited the same flaw. The pass's step is now `fillMissingScoreRows()`, the fill-missing backfill as on `main`. A day's load stays fixed at its first write; the follow-up and its design constraints are in `TODOS.md` ("A day's load is frozen at the first write, and recomputing it needs a trustworthy workout store").

## Background fill removed (2026-10-28)

The pass's `fillMissingScoreRows()` step was removed. It inserted rows for days the user did not open the app, before the foreground Strava sync; since nothing rewrites rows, those days kept a Health-only load forever. Missing rows are filled only by the foreground `refreshIfNecessary`, after `performSmartSync`, as on `main`. The pass is now: guard, throttle, HealthKit-only workout refresh, gated detection, stamp, Coach only if foreground. (Later: a rewrite guard follows the throttle, the gate also checks store rewrites, and Coach needs a recent sync too; see the As built note under Data flow.)
