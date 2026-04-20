# HealthAnalytics — Claude Code Instructions

## Design System
Always read `DESIGN.md` before making any visual or UI decisions.
All colors, typography, spacing, and aesthetic direction are defined there. Do not deviate without explicit user approval.

In QA mode, flag any code that uses hardcoded hex values, system default colors (`Color.green`, `Color.orange`, `Color.blue`, `Color.red`, `Color.purple`, `Color.yellow`, `Color.pink`, `Color.cyan`, `Color.gray.opacity(...)`), or inline font sizes instead of the design tokens defined in `DESIGN.md`.

Note: `MainTabView.swift` uses a legacy `AppColors` struct and is intentionally excluded from the token sweep until the tab system is refactored.

The primary design direction is **Warm Signal**: warm dark surfaces (`#0F0D0B` background), terracotta accent (`#E8885A`), SF Pro Rounded for hero numerals, SF Pro Text for coaching voice, SF Pro Mono exclusively for raw data/chart annotations.

## Architecture
See `GEMINI.md` for the full engineering mandate. Key rules:
- All readiness logic lives in `ReadinessRepository` — never in ViewModels
- Use `DataFingerprint` caching to prevent score drift
- ACWR sweet spot: 0.8–1.3

### Key extension points (v0.1.0.0)
- **New patterns** — extend `PatternType` enum in `Models/TrainingPattern.swift`, add a `detectX()` method to `Services/Analytics/TrainingDNAAnalyzer.swift`, wire it in `upsertPatterns()`. Pattern data flows through `StoredDailyScore` snapshots (upserted after every analysis run via `ReadinessRepository.upsertDailyScore()`).
- **FTP history** — `Models/StoredFTPSnapshot.swift`. Use `StoredFTPSnapshot.resolved(for:snapshots:)` to get the FTP value in effect for any historical workout date. Default 200W when no snapshot exists.
- **7-day forecast** — `Views/Recovery/ReadinessForecastChart.swift` + `ReadinessRepository.compute7DayForecast()`. Requires 14 days of `StoredDailyScore`.
- **Workout load calculation** — `Services/Analytics/PredictiveReadinessService.calculateWorkoutLoad()` uses three-path priority: zone-weighted power → NP/avg-power TSS → duration × sport multiplier.
- **Strain sensitivity** — `CardiovascularStrainService.compute(sensitivityOffset:)`. Offset read from `UserDefaults["strainSensitivityOffset"]` (range −0.2 to +0.2, default 0.0). Normalization constant is 70.0.
- **HeuristicIntentClassifier** — power-zone path takes priority over HR for cycling when `powerZoneSeconds` stream data is present. Only classifies workouts owned by the user (not third-party HealthKit sources).
- **WorkoutAuditView** — debug view in Settings → Today's Workouts showing all stored workouts with source, FTP, and zone data.

## Known Compiler Patterns

### SourceKit "Cannot find X in scope" — always noise
SourceKit reports false "Cannot find type/member in scope" errors throughout this project because it analyzes files in isolation without the full module graph. These are **not real build errors**. Only trust errors that appear in an actual Xcode build (`xcodebuild`) or from the Swift compiler directly.

### "Compiler unable to type-check expression in reasonable time" — `body` too large
When a SwiftUI `body` triggers this error, decompose it into:
- `private var mainView: some View` — owns the top-level container + background
- `@ToolbarContentBuilder private var toolbarItems: some ToolbarContent` — owns toolbar items
- Keep `body` as a thin modifier chain only

Applied to: `ReadinessView.swift`, `RecoveryDashboardView.swift`

### `.foregroundStyle(.tokenName)` type inference failures
In batch-compile contexts Swift sometimes fails to resolve shorthand `.tokenName` for custom `Color` extensions. Always use explicit `Color.tokenName` form (e.g. `Color.accent`, `Color.statusOptimal`) — never the dot-shorthand.

### `ForEach` with named tuple arrays — `Binding<C>` overload always wins
iOS 26.2 SwiftUI's compiler picks `ForEach.init<C>(_ data: Binding<C>, ...)` over `RandomAccessCollection` when named tuples are involved, regardless of input type. Fix: define a local `struct … : Identifiable` inside the View and use `ForEach(array) { item in }`.

Applied to: `InsightsView.swift` → `DataCollectionCard.ActivitySummary`

## Recovery Science Model

This section defines the physiological constraints for all recovery and strain calculations.
Do not deviate from these decisions without explicit user approval.

### Guiding principle
The app targets weekend warriors who feel their body but don't have a sports scientist.
Coaching language should reflect lived experience ("you're still paying off yesterday's ride"),
not raw numbers. Always translate scores into plain-English guidance.

### Carry-forward fatigue
Recovery is not a same-day phenomenon. A hard workout creates physiological debt —
elevated muscle damage, depleted glycogen, suppressed HRV — that persists 24–48+ hours.

- `RecoveryDecayService` must carry forward prior-day fatigue into today's baseline.
- The intra-day energy chart must start from this morning's readiness score (which already
  reflects prior-day strain), not from a neutral 100-point baseline.
- "No workout today" does not mean "fully recovered." It means fatigue is decaying passively.

### Steps and non-exercise activity load (NEAT)

**Scientific basis:**
- The 10,000-step target has no clinical foundation (1960s Japanese pedometer marketing).
- I-Min Lee (Harvard, 2019): all-cause mortality curve flattens ~7,500 steps; diminishing
  returns beyond that for sedentary-baseline populations.
- Steps represent mechanical load and metabolic expenditure that compounds with training stress.

**Threshold rule — personal baseline, not a fixed number:**
- Steps contribute to strain only above the user's 30-day rolling average daily step count.
- A person who habitually walks 12,000 steps/day is not accumulating extra stress at 12,000.
- A person who averages 4,000 steps/day and hikes 14,000 is accumulating real load.
- Never hardcode 7,500 or 10,000 as a universal goal or threshold.

**Contribution curve:**
- Ramp is non-linear: going from 18,000→20,000 steps is harder than 8,000→10,000.
- Use a mild linear ramp above threshold, capped so steps never exceed 20% of total daily strain.
- Steps are supporting load, not primary training stress. A hard interval session always dominates.

**Mechanism 1 — steps add to daily strain score:**
- Compute excess steps = max(0, today_steps − 30day_avg_steps).
- Map excess steps to fatigue points on a capped ramp (implementation details TBD).
- Feed the result into `RecoveryDecayService` alongside workout fatigue.

**Mechanism 2 — high daily movement reduces overnight recovery rate:**
- Only activates when combined load (workout strain + step excess) exceeds a threshold.
- Implemented as a percentage reduction on overnight recovery rate, not a flat points deduction.
  This preserves the relationship: 9hrs sleep > 5hrs sleep, even on high-load days.
- Has a floor: cannot reduce recovery rate below 50% of normal, regardless of step count.
- Does not activate on step excess alone — walking without training stress does not impair recovery.

**What steps do NOT do:**
- Steps do not directly set or cap the readiness score.
- Steps are never shown as a "goal to hit" in coaching language. The app does not reward
  10,000 steps. If steps are displayed, frame them as load context, not achievement.

### Energy Bank chart intent
The chart shows dynamic readiness across a full day (midnight to midnight):
- Solid line = elapsed time (actual fatigue state)
- Dashed line = projected remainder of day assuming no further workouts
- Y-axis starts from this morning's readiness baseline (carry-forward), not 100
- A rest day after a hard workout should show gradual upward slope, not a flat line

### Recovery model hierarchy (highest to lowest influence)
1. Overnight HRV and resting HR (primary recovery signal)
2. Sleep duration and quality
3. Prior-day workout strain (carry-forward fatigue)
4. Today's workout strain
5. NEAT / excess steps (supporting modifier)

## Project
iOS SwiftUI app. Target: weekend warriors who want coaching guidance, not raw data dashboards.
