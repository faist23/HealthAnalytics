# Changelog

All notable changes to HealthAnalytics are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [0.1.0.0] - 2026-04-20

### Added
- **14-Day Training Signature** — `TrainingSignatureCard` displays a spaghetti-plot
  of your last 14 days of readiness + strain with a vote-algorithm pattern summary.
  `StoredDailyScore` SwiftData model persists per-day readiness and ACWR for offline replay.
- **Pattern Engine — Phase 2b/3** — `TrainingDNAAnalyzer` now detects six patterns:
  Block Crash Cycle, HRV Precursor to Illness, Sleep Fragmentation, Back-to-Back
  Readiness Crash (with Pearson graduation gate at n≥10), Performance Peak, and
  Taper Underway. Results shown in `TrainingDNACard` and pushed as local notifications.
- **7-Day Readiness Forecast** — `ReadinessForecastChart` projects the next week of
  readiness from the last 14 days using OLS regression with ACWR modifiers and
  widening confidence bands (Mujika & Padilla 2003 taper science).
- **FTP History** — `StoredFTPSnapshot` model + `FTPHistoryView` lets you add, edit,
  and delete historical FTP values. `PredictiveReadinessService` now uses time-accurate
  power zones for all historical Strava workouts (zone-weighted → NP TSS → duration fallback).
- **HK / Strava Dedup v4** — `WorkoutMatcher` switched from ±5-min start-time delta
  to temporal overlap (≥50% of shorter session). One-time stale-record cleanup pass on
  upgrade. `SyncManager` tracks dedup version in UserDefaults to prevent re-running.
- **Healthspan calibration UI** — resting HR source picker and biological age inputs
  accessible from Settings.
- **WorkoutAuditView** — debug view showing all stored workouts with source, FTP,
  and zone data for power-zone backfill verification.

### Changed
- `HeuristicIntentClassifier` scope narrowed: only classifies workouts the user owns
  (prevents reclassifying HealthKit workouts written by third-party apps).
- Strain zone weights unified across cardiovascular strain and predictive readiness
  services to eliminate score drift between tabs.
- Strava FTP sync now imports from `weighted_average_watts` (normalised power) where
  available, falling back to average power.

### Fixed
- `getUserSex` renamed to correct `getUserBiologicalSex` HealthKit API.
- Missing `SwiftData` import in `WorkoutAuditView` causing build failure.
- `StoredFTPSnapshot` made `Sendable` to resolve actor-isolation warnings.
- `PatternNotificationService`: tapering pattern was scheduling a blank
  `UNNotificationRequest` instead of being suppressed.
- `StoredWorkout` init had duplicate `self.source = source` assignment (copy-paste artifact).
- `StoredFTPSnapshot.upsertIfChanged`: replaced force-unwrap on calendar arithmetic.
- `BiologicalAgingServiceTests`: age-40 standard HRV corrected to 49ms (was 45ms).
