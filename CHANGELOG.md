# Changelog

All notable changes to HealthAnalytics are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

### Added
- **Phase 4: Structured Ontology** — `CoachMemoryNote` now supports anatomical tagging (e.g., "Lower Body: Knee") for injuries. Added `SmartRoutingEngine` to dynamically filter workout recommendations based on active injuries (e.g., zeroing out "Running" readiness for a knee injury while preserving "Upper Body Strength"). Exposed `activityReadiness` through the `ReadinessRepository`'s `UnifiedReadiness` state.
- **Phase 5: Generative AI Integration** — Transformed `MasterCoachEngine` to support asynchronous LLM handoff for dynamic synthesis of the athlete's physiological state. The coaching paragraph is now generated dynamically using a `StateVector` encompassing readiness, load, injury risk, active patterns, memory notes, and forecasts. Migrated associated tests to `async/await`.

### Changed
- **Granular Cardio Load Zones** — The Strain tab's Time-in-Zone metrics (Zones 1-3 vs 4-5) are now calculated using exact granular heart rate samples from `CardiovascularStrainService` instead of an inaccurate estimate based on the workout's overall average heart rate.
- **7-Day Forecast Homeostasis** — Rewrote the 7-day readiness forecast in `ReadinessRepository` to simulate cumulative fatigue and natural recovery. Instead of a flatline projection, the forecast now exhibits mean-reversion homeostasis, pulling the readiness toward a baseline of 75 while correctly compounding simulated fatigue on days a "Hard" or "Moderate" workout is recommended.

### Fixed
- **Startup Sync Race Condition** — Fixed an issue where the app would display a stale readiness score (e.g., 63) at launch before updating. `CoachTabView` and `ContentView` now correctly listen for the `DataSyncCompleted` notification and refresh their data seamlessly.
- **Missing Loading Overlay on Launch** — Restored the full-screen `LoadingOverlay` ("Analyzing your readiness...") on the Coach tab to prevent the app from briefly flashing a "0" placeholder score during the initial data synchronization upon launch.

## [0.1.7.0] - 2026-05-03

### Added
- **Pattern Confidence Badge (E4)** — each Training DNA card in the Intelligence tab now shows a color-coded confidence pill (Consistent / Mixed / Tentative) alongside a count-and-duration line (e.g., "7 of 9 blocks · 14 days"). The badge maps directly to detection quality: green means the pattern is well-established, amber means it's emerging, gray means tentative early data. Accessible label covers tier, count, and tracked duration.

### Changed
- **Signal Indigo design system** — replaced the Warm Signal (terracotta / earthy) palette with Signal Indigo across the entire app. Background moves from warm near-black to cool near-black (`#09090E`); accent shifts from terracotta (`#E8885A`) to electric violet (`#7C5CFC`). All text tokens gain an indigo cast for a cooler, more precise feel. Status colors (green / amber / ember / sky blue) are unchanged.
- **InsightBox and MetricList token sweep** — hardcoded colors and gradient borders replaced with `Color.surface`, `Color.surfaceRaised`, `Color.accent`, and `Color.accentBorder` design tokens. Consistent with every other card in the app.

## [0.1.6.1] - 2026-05-03

### Fixed
- Loading overlay on Intelligence tab now reads "Opening [Pattern Name]..." instead of "Analyzing your data..." when the tab opens cold via a deep-link tap from the Recovery tab. Eliminates the blank-context skeleton gap introduced in E3.

## [0.1.6.0] - 2026-05-03

### Added
- **Coach → Pattern deep-link (E3)** — tapping a pattern reference in the Recovery tab's coaching message navigates directly to the Intelligence tab, scrolled to the corresponding Training DNA card. Powered by a new `TabCoordinator` environment object (`selectedTab` / `pendingScrollPattern`), injected at app root and consumed by `RecoveryTabView` and `InsightsView`. `InsightBox` gains optional `navigationText` / `navigationAction` params for the cross-tab CTA.
- `PatternType.displayPriority` — static method providing canonical priority ordering (`[.hrvPrecursor, .backToBackCrash, .blockCrashCycle, .sleepFragmentation, .performancePeak, .tapering]`), shared by `RecoveryTabView` (top pattern selection) and `InsightsView` (today's signal card).
- 4 new `TabCoordinatorTests` covering initial state, navigation with/without pattern, and double-navigation overwrite.

## [0.1.5.0] - 2026-05-03

### Added
- **Intelligence tab** — the app's richest analysis (Training DNA patterns, biological aging, performance correlations, MasterCoachEngine synthesis) is now a permanent 5th tab with a `sparkles` icon, not a hidden toolbar sheet. Users can navigate directly to it without ever opening the Recovery tab first.
- **"Today's Signal" card** — surfaces at the top of the Intelligence tab on every launch. When active patterns exist (within 7 days), it shows the MasterCoachEngine coaching paragraph with a left-edge terracotta accent stripe and a subtitle naming the top detected pattern. When signals are quiet, it shows "All signals quiet — everything looks good." The card is hidden until data loads.

### Changed
- Renamed "Analysis" → "Intelligence" throughout (tab label, navigation title). The `sparkles` icon signals synthesis, not raw data.
- Removed the `chart.bar.xaxis` toolbar button from the Recovery tab — one path to the Intelligence content is better than two competing entry points.

### Fixed
- Corrects missed VERSION file bump from the v0.1.4.0 commit (CHANGELOG was updated but VERSION stayed at 0.1.3.1).

## [0.1.4.0] - 2026-05-01

### Added
- **Pattern-aware coaching messages** — `MasterCoachEngine` now receives live pattern detection results from `ReadinessRepository` and uses them to personalise every coaching paragraph. Pattern priority hierarchy: HRV precursor overrides all positive signals; `backToBackCrash` and `blockCrashCycle` append a load-specific warning; `sleepFragmentation` appends a sleep note; `performancePeak` and `tapering` upgrade the baseline readiness message tier. Patterns are scoped to the past 7 days so stale detections don't affect current advice. `StateVector.activePatterns` is typed `[String]` (raw `PatternType` values) to keep the engine a pure Foundation struct with no SwiftData dependency. `ReadinessRepository` passes `activePatternTypes.map(\.rawValue)` at the call site.
- **8 new unit tests for pattern-aware coaching** — covers HRV precursor override, performance peak upgrade, taper upgrade, back-to-back crash load note, sleep fragmentation note, and all three existing baseline cases.

## [0.1.3.1] - 2026-04-30

### Fixed
- **HRV precursor pattern now fires for daily-workout users** — the sick-day proxy previously required two consecutive low-step days with *no workout at all*, so users who do a daily warmup session (even a short 10-min spin) were permanently blocked from the pattern. The workout filter now uses a load threshold of ≥ 0.5 TSS (sourced from `StoredDailyScore.dailyLoad`), so warmup rides (~0.17 TSS) are excluded while real training sessions are still respected. `detectHRVPrecursor` now fetches significant workout days directly from SwiftData rather than via HealthKit's `fetchWorkoutDays`. Formatter consistency fix: both construction and lookup of the `significantWorkoutDays` set use the same local `fmt` DateFormatter instance to prevent timezone drift.

## [0.1.3.0] - 2026-04-30

### Added
- **Today's step activity now shows up in your energy bank** — if you walked or hiked significantly more than your personal 30-day average, that extra movement adds to your intra-day fatigue curve. The effect is proportional and capped: steps can contribute at most 20% of your workout strain (or 2 points on a rest day), so a long walk never dominates the chart the way a hard interval session does. `RecoveryDecayService.calculateIntraDayReadiness` accepts the new `todayStepExcessTSS` parameter; `ReadinessRepository` derives it from your rolling step baseline using a 3 000-steps-per-TSS conversion.

### Removed
- **Cleaned up 5 unused ML-experiment files** from `ML-Components/` — `TemporalInsightsCard`, `IntentAwareReadinessTestView`, `ActivityIntentLabelerView`, `IntentAwareReadinessCard`, and `EnhancedIntentReadinessCard` were superseded by the `HeuristicIntentClassifier` path and had zero references in active code. Removed to reduce SourceKit indexing overhead and eliminate false targets when searching where logic lives.

## [0.1.2.0] - 2026-04-30

### Added
- **Overnight recovery now reflects yesterday's full load** — when you had a hard workout day AND high step activity, the app slows the overnight fatigue recovery curve accordingly (half-life stretches from 16h up to 32h). A rest day after a big day no longer bounces back unrealistically fast. Sleep still dominates — 9 hrs always beats 5 hrs, even on high-load days. `RecoveryDecayService.overnightRecoveryMultiplier(workoutTSS:stepExcessTSS:)` computes the [0.5, 1.0] rate multiplier; does not activate on step excess alone.
- **Back-to-back crash detection no longer fires on warmup spins** — the pattern now requires a real training load (≥ 1.0 TSS, equivalent to a 60-min zone-2 ride) to count as a hard day. Short 20-min warmup sessions (≈ 0.17 TSS) are filtered out so they no longer suppress the signal by making every day look like heavy training. Existing records are backfilled on first launch. `hardDayLoadThreshold = 1.0`: 20-min zone-1 warmup ≈ 0.17 TSS; 60-min zone-2 base ride ≈ 1.0 TSS.

## [0.1.1.0] - 2026-04-23

### Added
- **Dynamic Master Coach Engine** — the app now generates a single coaching paragraph that evolves throughout the day. It explicitly references the gap between your morning baseline and your current fatigue state after workouts, so advice stays coherent as your day unfolds. Semantic tone rules prevent contradictory guidance (e.g., "push hard" appearing after a flagged recovery deficit).
- `MasterCoachEngine.swift` powers the synthesis pipeline; `coachAdvice` is now a first-class field in `UnifiedReadiness` and `CachedAnalysis` (widget-ready).

### Changed
- Replaced fragmented instructions (`DailyInstructionCard`) in the `HeroReadinessCard` and `ReadinessView` with a single, synthesized `MasterCoachSummary` text.
- `ReadinessRepository` functionally isolates `morningReadinessScore` calculations to omit same-day workouts for a static morning baseline.
- `UnifiedReadiness` includes the new `coachAdvice` message, and `CachedAnalysis` supports it for iOS widgets.

## [0.1.0.0] - 2026-04-20

### Added
- **14-Day Training Signature** — `TrainingSignatureCard` displays a spaghetti-plot
  of your last 14 days of readiness + strain with a vote-algorithm pattern summary.
  `StoredDailyScore` SwiftData model persists per-day readiness and ACWR for offline replay.
- **Pattern Engine** — the app now detects six training patterns:
  Block Crash Cycle, HRV Precursor to Illness, Sleep Fragmentation, Back-to-Back
  Readiness Crash (with Pearson graduation gate at n≥10), Performance Peak, and
  Taper Underway. Results surface in the Training DNA card and as local notifications.
- **7-Day Readiness Forecast** — you can now see where your readiness is likely to
  land over the next week based on your last 14 days. Uses OLS regression with ACWR
  load modifiers and widening confidence bands grounded in Mujika & Padilla 2003 taper science.
- **FTP History** — you can now track your FTP over time. Add, edit, and delete
  historical FTP values in Settings → Training Zones. Historical Strava workouts now
  use the FTP that was in effect at the time for accurate power zone calculations (zone-weighted → NP TSS → duration fallback).
- **HK / Strava Dedup** — workout matching now uses temporal overlap (≥50% of the
  shorter session) instead of a start-time delta. This eliminates double-counting of
  Strava sessions where GPS tracking starts later than the HealthKit timer. A one-time
  cleanup removes any stale duplicate records on upgrade.
- **Healthspan calibration** — resting HR source picker and biological age inputs are
  now accessible from Settings, so the aging model can be tuned to your personal baseline.
- **Workout Audit** — Settings now includes a "Today's Workouts" debug view showing
  every stored workout with its source, FTP used, and zone breakdown — useful for
  verifying power-zone backfill after an FTP history change.

### Changed
- **Strain Sensitivity** — a new slider in Settings lets you adjust how sensitive the
  strain score is to effort. The underlying normalization was also recalibrated (70.0,
  down from 90.0) so a hard 60-min zone 4–5 ride scores ~16–18 (Strenuous) as expected.
- **Workout intent classification** — power-zone distribution now takes priority over
  average heart rate for cycling workouts when Strava stream data is present, giving
  more accurate intent labels for interval sessions where HR lags power.
- Workout intent classifier no longer reclassifies HealthKit workouts written by
  third-party apps — only workouts you directly own are relabeled.
- Strain zone weights unified across cardiovascular strain and predictive readiness
  services to eliminate score drift between tabs.
- Strava FTP sync now imports normalized power (`weighted_average_watts`) where
  available, falling back to average power.

### Fixed
- Taper pattern was silently scheduling a blank notification instead of being suppressed — now correctly skipped at the notification layer.
- Biological aging score for a 40-year-old used an incorrect HRV standard (45ms → 49ms per reference population).

### For contributors
- Corrected HealthKit API call: `getUserSex` → `getUserBiologicalSex`.
- Missing `SwiftData` import in `WorkoutAuditView` (build failure on clean checkout).
- `StoredFTPSnapshot` marked `Sendable` to silence actor-isolation warnings.
- Duplicate `self.source = source` assignment in `StoredWorkout.init` removed.
- Force-unwrap on calendar arithmetic in `StoredFTPSnapshot.upsertIfChanged` replaced with safe unwrap.
- `StoredFTPSnapshot.upsertIfChanged` now updates in place on same-day FTP change instead of inserting a duplicate row. Previous behavior caused two rows to exist for the same day when FTP changed.
- `SyncManager.invalidateZones(affectedAfter:)` date predicate was silently ignored — the fetch returned all Strava workouts regardless of `date`. Fixed with a `#Predicate` gate.
- Three unbounded `FetchDescriptor<StoredDailyScore>` full-table scans in `TrainingDNAAnalyzer` replaced with date-bounded predicates (90-day and 28-day windows).
- Forecast dedup added in `ReadinessRepository.compute7DayForecast` to prevent corrupted OLS regression input from duplicate-day `StoredDailyScore` rows.
- `ReadinessRepository.shared` singleton contamination in `PredictiveIntelligenceTests` fixed by adding a `#if DEBUG resetForTesting()` escape hatch called from `setUp`.
- Vacuous test `testBackToBackCrash_n10_lowLagR_fails` replaced with unconditional assertion (previously always passed regardless of implementation).
- Test `test_upsertIfChanged_sameDayDifferentWatts_inserts` renamed to `updatesInPlace` and updated to assert count=1 (was asserting the old buggy duplicate-row behavior).
- `ScienceCitationTests.testIsStale_logic` fixed to route through `CitationDatabase.citation(for:)` instead of `fileprivate ScienceCitation.hrv` (inaccessible via `@testable import`).
