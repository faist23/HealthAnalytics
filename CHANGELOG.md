# Changelog

All notable changes to HealthAnalytics are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

## [0.1.2.0] - 2026-04-30

### Added
- **NEAT Mechanism 2 — overnight recovery rate modifier** — high combined load from yesterday (workout strain + excess step load above 30-day personal baseline) now reduces how quickly prior-day fatigue resolves overnight. Implemented as a percentage reduction on the prior-day fatigue half-life (16h → up to 32h at 0.5× floor), not a flat points deduction, preserving the sleep-duration hierarchy. Does not activate on step excess alone. `RecoveryDecayService.overnightRecoveryMultiplier(workoutTSS:stepExcessTSS:)` computes the [0.5, 1.0] rate multiplier; `ReadinessRepository` derives it from yesterday's load each analysis run and flows it through to `EnergyBankChart` via `UnifiedReadiness` → `ReadinessViewModel`.
- **Intensity-gated back-to-back crash detection** — `StoredDailyScore` gains a `dailyLoad: Double` field (total TSS-equivalent load per day). The back-to-back crash pattern now uses `dailyLoad >= 1.0` to identify hard training days instead of `workoutCount >= 1`, filtering out short warmup sessions (< 0.5 TSS) that were causing every day to register as a training day and suppressing the signal. A one-time migration (`backfillDailyLoad()`) populates `dailyLoad` on existing records from `StoredWorkout` on first launch. `hardDayLoadThreshold = 1.0`: 20-min zone-1 warmup ≈ 0.17 TSS; 60-min zone-2 base ride ≈ 1.0 TSS.

## [0.1.1.0] - 2026-04-23

### Added
- **Dynamic Master Coach Engine** — a unified heuristic engine that generates human-like coaching advice dynamically throughout the day. It explicitly references the delta between your morning readiness baseline and current fatigue state (e.g., after logging a workout). 
- `MasterCoachEngine.swift` introduces semantic tone rules and compositional pipeline string synthesis for consistent, non-contradictory advice.

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
