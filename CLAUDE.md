# HealthAnalytics — Claude Code Instructions

## Design System
Always read `DESIGN.md` before making any visual or UI decisions.
All colors, typography, spacing, and aesthetic direction are defined there. Do not deviate without explicit user approval.

In QA mode, flag any code that uses hardcoded hex values, system default colors (`Color.green`, `Color.orange`, `Color.blue`, `Color.red`, `Color.purple`, `Color.yellow`, `Color.pink`, `Color.cyan`, `Color.gray.opacity(...)`), or inline font sizes instead of the design tokens defined in `DESIGN.md`.

Note: `MainTabView.swift` uses a legacy `AppColors` struct and is intentionally excluded from the token sweep until the tab system is refactored.

The primary design direction is **Signal Indigo**: cool dark surfaces (`#09090E` background), electric violet accent (`#7C5CFC`), SF Pro Rounded for hero numerals, SF Pro Text for coaching voice, SF Pro Mono exclusively for raw data/chart annotations.

## Architecture
See `GEMINI.md` for the full engineering mandate. Key rules:
- All readiness logic lives in `ReadinessRepository` — never in ViewModels
- Use `DataFingerprint` caching to prevent score drift
- ACWR sweet spot: 0.8–1.3

### Key extension points (v0.1.9.0)
- **Five-tab IA** (v0.1.9.0; Recovery rename 2026-07-08). The tabs are Coach (0) / Recovery (1) / Load (2) / Patterns (3) / Labs (4). Each answers exactly one question and Phase 2.4's voice rule still holds: Coach is the only tab with advisory voice (Master Coach paragraph); Recovery / Load / Patterns / Labs are descriptive dashboards. **Coach** = "what should I do today?" **Recovery** = "how recovered is my body and why?" **Load** = "am I building or breaking down?" **Patterns** = "what has my body been doing lately?" **Labs** = "what experimental signal is the app studying?" When adding new content, name the tab whose question it answers — don't dump it where it'll be seen. The `Labs` tab is intentional exploration, not a graveyard for unfinished work; only ship features there you actively want users to evaluate.
- **"Recovery" vs "readiness" vocabulary** (2026-07-08 rename). The score is a *recovery* measure (HRV, RHR, sleep, carry-forward fatigue) and all user-facing copy must call it "recovery" / "recovery score". "Ready"/"readiness" verdict language is allowed ONLY in Coach-tab prose (MasterCoachEngine output), as a conclusion drawn from recovery + load together. Internal identifiers (`UnifiedReadiness`, `ReadinessRepository`, `ReadinessViewModel`, `morningReadinessScore`, UserDefaults keys, notification names) intentionally keep the old name — do not rename symbols, and do not let internal names leak into UI strings. Folding ACWR into the score to make "readiness" literal was considered and rejected (pollutes the physiological measure, breaks the recovery-model hierarchy).
- **Tab indices** are defined in `TabCoordinator` (`coachTab`/`readinessTab`/`loadTab`/`patternsTab`/`labsTab`) and must match `.tag(N)` in `MainTabView`. `readinessTab` is the Recovery tab (internal constant keeps the old name). The `intelligenceTab` alias points to `patternsTab` for one release cycle; remove after v0.2.0.
- **Patterns tab affordances** (v0.1.9.0). Active pattern count is surfaced as a numeric `.badge(N)` on the Patterns tab icon (`MainTabView` queries `TrainingPattern` directly) AND as a plain header strip at the top of the tab. Two consumers of the same signal — keep them in sync if you change the active-pattern window from 7 days. The Patterns tab owns the only `ScrollView` on its surface; `InsightsView` is a pure content producer (`VStack`, no `NavigationStack`/`ScrollView`/`ScrollViewReader`). Don't re-introduce a nested `ScrollView` in either view — the `ScrollViewReader.proxy.scrollTo(patternType)` cross-tab deep-link relies on the single-ScrollView guarantee.
- **Repository-driven data flow** (v0.1.8.0 architecture refactor — see `REFACTOR_PLAN.md`). `ReadinessRepository.shared.bootstrap()` is called once from `HealthAnalyticsApp.swift` and subscribes to `DataSyncCompleted` centrally — **views never listen for sync, never call `analyze()`, never fetch SwiftData**. Each app-lifecycle sync trigger (`.task` on launch, `.onChange(scenePhase)` on scene-active, Strava OAuth callback) explicitly calls `ReadinessRepository.shared.refreshIfNecessary(modelContext:)` after `SyncManager.performSmartSync()` to cover the 30-min throttled-sync path where no notification fires. `UnifiedReadiness` carries every value a view could need (including per-tab data like `cardiovascularStrain`, `holisticMetrics`, `todayWorkouts`, `todaySteps`, and the raw chart arrays `hrvData`/`rhrData`/`sleepData`/`stepCountData`/`workouts`/`weightData`). `ViewModels` are Combine subscribers — they observe `$currentReadiness`, `$analysisError`, `$isAnalyzing` and republish. **Do not add SwiftData fetching to a ViewModel or a view; add the field to `UnifiedReadiness` and compute it inside `performFullAnalysis`.**
- **Refreshes requested mid-analysis are coalesced, never dropped** (2026-08-05). `performFullAnalysis` still guards on `isAnalyzing` (concurrent runs interleave SwiftData writes), but it now sets `pendingRefreshRequested` and re-calls `refreshIfNecessary` on the way out. A run is slow (ML training, `MasterCoachEngine`, HealthKit reads) and a workout finishing sync lands inside that window — the old bare `return` discarded the `DataSyncCompleted` refresh, leaving the published snapshot describing pre-ride data until an unrelated trigger came along. The re-entry re-fingerprints, so it's a no-op unless the store actually moved.
- **User-initiated sync** bypasses both throttling layers. `SyncManager.performSmartSync(force: true)` skips the 30-minute throttle; `ReadinessRepository.forceRefresh(modelContext:)` skips the fingerprint cache. Use both together on any user-initiated refresh affordance (pull-to-refresh, toolbar refresh button) so a deliberate tap always does visible work. Background and lifecycle triggers should use the default (un-forced) paths.
- **Historical ACWR calls `calculateReadiness(..., referenceDate:)`** with the date being asked about — not `Date()`. The default `referenceDate: Date()` keeps current-assessment callers behavior-stable; historical callers (the ACWR trend chart, `PerformancePredictor` training rows) must pass an explicit reference date or the inner methods will window `[today-7, today]` / `[today-28, today]` regardless of the workout-filter intersection.
- **Cardio Load gauge has no synthetic fallback** (v0.1.8.0). When `viewModel.cardiovascularStrain` is `nil`, the gauge shows an explicit "needs watch data" empty state. **Never reinstate the `acwr * 10` fallback** that previously fabricated a strain value from training-load ratio — it presented an authoritative-looking number with no physiological basis.
- **Coaching voice lives only on the Coach tab** (v0.1.8.0). The Master Coach paragraph (`UnifiedReadiness.coachAdvice`) renders only via `DashboardViewModel.readinessRecommendation` on `CoachTabView`. Recovery and Load show descriptive captions of their own state (`readinessDescription(for:)` in `RecoveryTabView`, `loadDescription` in `StrainTabView`) — facts, not advice. Intelligence's `InsightsView` "Today's Signal" card shows pattern counts. **Don't add another consumer of `coachAdvice` outside Coach** without re-opening that decision. The rule extends to `TrainingLoadCalculator.recommendation` / `LoadVisualizationData.LoadSummary.recommendation`: both are advisory ("Add recovery days regardless of how you feel"), and as of 2026-08-05 neither renders on a Load surface — `UnifiedTrainingLoadCard` shows only its `interpretation`, and `LoadSummaryCard` (Extended Analysis) shows a `loadDescription` worded identically to `StrainTabView.loadDescription`. They still render on `METActivityCard`, `ReadinessView` (legacy), and `InsightsView`.
- **Dynamic Master Coach Engine** — `Services/Coaching/MasterCoachEngine.swift`. Generates a single, cohesive coaching paragraph. `ReadinessRepository` computes the `morningReadinessScore` by functionally omitting today's workouts, passing it to the engine to explicitly highlight intra-day fatigue deltas.
- **NEAT Mechanism 1 (excess steps add to intra-day strain)** — `RecoveryDecayService.calculateIntraDayReadiness(morningReadiness:workouts:sleepHours:todayStepExcessTSS:)` accepts a `todayStepExcessTSS` parameter. `ReadinessRepository` computes it as `min(excessSteps / 3000.0, cap)` where cap = 20% of today's workout TSS (or 2.0 on rest days). Step baseline is the 30-day rolling average daily step count; fallback `5000` when no history exists. Flows into `EnergyBankChart` via `UnifiedReadiness.todayStepExcessTSS`.
- **NEAT Mechanism 2 (overnight recovery rate modifier)** — `RecoveryDecayService.overnightRecoveryMultiplier(workoutTSS:stepExcessTSS:)` returns a [0.5, 1.0] multiplier applied to the prior-day fatigue half-life (16h → up to 32h). Only activates when combined workout strain + step excess exceeds threshold. Does not activate on step excess alone. `ReadinessRepository` derives the multiplier from yesterday's load and flows it through `UnifiedReadiness` → `ReadinessViewModel` → `EnergyBankChart`.
- **New patterns** — extend `PatternType` enum in `Models/TrainingPattern.swift`, add a `detectX()` method to `Services/Analytics/TrainingDNAAnalyzer.swift`, wire it in `upsertPatterns()`. Pattern data flows through `StoredDailyScore` snapshots (upserted after every analysis run via `ReadinessRepository.upsertDailyScore()`). `StoredDailyScore.dailyLoad` stores the total TSS-equivalent load for the day (sum of `calculateWorkoutLoad()` across all workouts). Hard-day detection in `detectBackToBackReadinessCrash()` uses `dailyLoad >= 1.0` — do not revert to `workoutCount >= 1` (warmup rides score < 0.5 TSS and must not count as training days). Sick-day proxy detection in `detectHRVPrecursor()` uses `dailyLoad >= 0.5` sourced from `StoredDailyScore` (not `fetchWorkoutDays`) — do not revert to a HealthKit workout-presence check, as it would permanently block the pattern for users who do daily warmup rides (~0.17 TSS).
- **Every pattern surface filters on `TrainingPattern.isActive`** (2026-08-08). Nothing deletes a `TrainingPattern` — `upsertPatterns()` only inserts and updates, deliberately, so `notificationSent` survives. Recency is therefore the ONLY signal that a pattern still holds, and `isActive` (detected within `TrainingPattern.activeWindowDays`, 7) is the single definition. `InsightsView` rendered the Training DNA card list unfiltered, so a taper detected once kept claiming "Taper Underway / Load down 41%" three weeks later while the tab badge and the Patterns header strip — both already filtered — read 0. Do not re-introduce a local `sevenDaysAgo` cutoff in a view; all six read sites (`MainTabView` badge, `PatternsTabView` header strip **and both deep-link `contains` checks**, `RecoveryTabView.topActivePattern`, `InsightsView` card list, and `ReadinessRepository`'s `activePatternTypes` feeding `MasterCoachEngine`) read `isActive` so the window moves in one place. The `PatternsTabView` deep-link checks matter separately: only active patterns get an `.id(patternType)` in the hierarchy, so a `contains` hit on a stale row makes `proxy.scrollTo` fire at a missing ID and skips the stash-and-retry branch. **`activeWindowDays` (10) MUST stay strictly greater than the 7-day analysis cadence in `runPatternAnalysis`** — at exactly 7 they coincided and patterns expired at the instant their refresh became eligible. **Known, not fixed: the Coach tab still lags the Patterns tab by up to a day.** `activePatternTypes` is baked into `UnifiedReadiness.coachAdvice` inside `performFullAnalysis`, and the fingerprint cache holds that for the calendar day, so the paragraph can outlive the card. Anchoring on `Date()` instead of `startOfDay(today)` narrowed nothing here — don't claim it did. `TrainingSignatureCard` intentionally reads `.backToBackCrash` unfiltered — it describes a long-lived trait, not a this-week signal. Covered by `TrainingDNAAnalyzerTests` "Pattern Staleness".
- **Taper detection corroborates intent with intensity** (2026-08-09). Volume down + HRV up cannot distinguish a taper from injury, illness, or a week of work travel. `detectTaperUnderway` therefore gates on `taperIsCorroborated(referenceDate:)`, which reads `StoredWorkout` over the same 28-day window in two tiers. **Tier 1** (every user, no sensors needed): at least `taperMinimumRecentSessions` (1) workout in the last 7 days — you cannot taper by not training, and this is what catches the crashed rider. **Tier 2** (only when both windows contain a workout with real power/HR): mean intensity over the last 7 days must hold at `taperIntensityRetention` (0.85) of the days 8–28 baseline; volume and intensity falling together is a stoppage, not a taper. Intensity comes from `TrainingLoadVisualizationService.estimateIntensity` — now non-private specifically for this reuse. **Do not reimplement intensity in the analyzer**; duplicated load math is how this project ended up with two disagreeing ACWR engines. `hasIntensitySignal` lives beside `estimateIntensity` and MUST track its fallback chain — comparing a measured window against neutral-5.0 placeholders would fabricate a difference from missing data. Users with no power/HR get Tier 1 only, deliberately: blocking the pattern outright for thin-data users repeats the sick-day-proxy mistake. Analyzer test containers need `StoredWorkout` + `StoredFTPSnapshot` in the schema, and any test asserting a taper FIRES must seed workouts (`seedIntensityHeldWorkouts`) — a load drop alone is no longer sufficient.
- **Taper copy describes the measurement and never asserts intent** (2026-08-09). `detectTaperUnderway` fires on volume down ≥30% AND a positive 7-day HRV slope — which is equally the signature of injury, illness, or a week of work travel, since HRV rises on rest either way. The detector has no intent signal, so no taper-facing string may claim one. `PatternType.tapering.displayName` is "Load Dropping" (not "Taper Underway"); `evidenceSummary` leads with "Volume down N% and HRV recovering" and hedges the Mujika & Padilla peak-form projection on "If this is a planned taper"; `coachingResponse` and both `MasterCoachEngine` taper branches (score ≥80 and ≥60, duplicated across the LLM and heuristic paths — four strings) address the involuntary case too. Banned phrases: "Taper Underway", "taper is underway", "Trust the process", "fitness is locked in". Pinned by `testTaperCopyDescribesTheObservationRatherThanAssertingATaper`, `testTaperUnderway_emittedCopyIsConditional`, and the `MasterCoachEngineTests` banned-phrase assertions. Adding an intensity-corroboration signal (intensity held while volume falls ⇒ deliberate) is the open follow-up in TODOS.md — until then the copy carries the ambiguity rather than resolving it wrongly.
- **Taper detection bands on `dailyLoad`, never `dailyStrain`** (2026-08-08). `detectTaperUnderway` compares mean `StoredDailyScore.dailyLoad` (actual TSS/day) over the last 7 days vs days 8–28. It previously compared `dailyStrain` (the ACWR *ratio*), which decays toward 1.0 on its own for ~28 days after any increase in training while the 28-day chronic denominator catches up. Simulated over 10 load histories that metric got 5 verdicts wrong: it fired "Load down 41%" at riders who had merely resumed training or stepped up a block and then held it flat (0% real change, Load tab correctly reading ACWR ~1.0), and it MISSED a genuine 50% volume cut (only a 24% ratio move). The load metric got 0 wrong. `taperBaselineLoadThreshold` (0.25 mean daily load over the 21-day baseline) blocks firing when there was no training block to taper from — including pre-migration rows where every `dailyLoad` is 0.0, which would otherwise read as a 100% drop. The test fixture `makeTaperScores` pins `dailyStrain` to a constant so reconnecting the detector to it goes red.
- **FTP history** — `Models/StoredFTPSnapshot.swift`. Use `StoredFTPSnapshot.resolved(for:snapshots:)` to get the FTP value in effect for any historical workout date. Default 200W when no snapshot exists.
- **7-day forecast** — `Views/Recovery/ReadinessForecastChart.swift` + `ReadinessRepository.compute7DayForecast()`. Requires 14 days of `StoredDailyScore`. The HARD/MED/EASY/REST label is `max(byRecovery, byLoad)` over `ForecastEffort` (ordered least → most restrictive), **not** the recovery score alone — a well-recovered athlete mid-ramp was told "Hard effort OK" while the Load tab said to take rest days. The load ceiling is computed **per forecast day** by asking `calculateReadiness(referenceDate: end of that day)` with only existing workouts: the forecast assumes no further training, so the acute window empties and the ceiling relaxes across the horizon (ACWR>1.5 → ceiling `.easy`; 1.3–1.5 → `.moderate`). Load is a **ceiling, never a floor** — it must not upgrade a poor-recovery day. This label also feeds `MasterCoachEngine.StateVector.nextDayForecast`. Test-fixture gotcha: forecast day 1 is *tomorrow* and its window closes at the end of tomorrow, so the oldest acute day has already rolled off — a ramp needs ~3h/day to clear ACWR 1.5 there, not 2h.
- **Workout load calculation** — `Services/Analytics/PredictiveReadinessService.calculateWorkoutLoad()` uses three-path priority: zone-weighted power → NP/avg-power TSS → duration × sport multiplier.
- **One ACWR engine** (v0.1.10.0). Every Load surface must get its ACWR and per-workout load from `PredictiveReadinessService` (`calculateReadiness` / `calculateWorkoutLoad`). `TrainingLoadVisualizationService` delegates to it and holds no load math of its own — a duration-only `hours × 100` TSS there once made "Extended Analysis" report ACWR 1.80/Overreaching while the Load tab said 1.33/Building. The status thresholds live in two switches (`ReadinessAssessment.Trend` and `TrainingLoadVisualizationService.loadStatus(for:)`) that MUST stay in lockstep: detraining `<0.8` / optimal `0.8–1.3` / building `1.3–1.5` / overreaching(danger) `>1.5`. `Trend` has four cases — adding a fifth is a compile error across `UnifiedTrainingLoadCard`, `ACWRTrendCard`, `InsightsView`.
- **`TrainingLoadCalculator` bands on the canonical ACWR, not `ewmaRatio`** (2026-08-05). Its TSS / EWMA / monotony / strain metrics are its own, but `status` and `recommendation` come from `PredictiveReadinessService.calculateReadiness(...).acwr`. Banding on `ewmaRatio` made the Load Details card print "Training load is elevated" (canonical ACWR 1.3–1.5) directly above the lightbulb line "Training load is optimal and recovery is good" (EWMA ≤1.3) on the same screen — the two ratios sit a full band apart in practice (ACWR 1.40 → EWMA banded it *overreaching*). `ewmaRatio` stays on the struct as a display value; don't reconnect it to band selection. Covered by `testLoadSummaryStatusAgreesWithAssessmentTier`.
- **A day's ACWR window closes at the END of that day** (2026-08-05). Every daily ACWR point goes through `PredictiveReadinessService.windowEnd(for:now:)` — past days close at the following midnight, today closes at `now`. Passing `startOfDay(day)` closes the window *before* that day's training: the 7-day trend chart's last point ignored today's ride (rendering exactly 1.0 for a steady-load user) while the assessment printed beside it included it, and every earlier point was shifted a day late. The 7-day trend (`ReadinessRepository.calculateImprovedACWRTrend`) and the 90-day series (`TrainingLoadVisualizationService.generateTimeSeriesData`) both delegate to it — don't reintroduce a local reference-date rule in either. Test gotcha: `TrainingLoadACWRConsistencyTests.workout(daysAgo:)` offsets by `daysAgo − 0.5` *days from now*, so it does NOT land on calendar day `today − daysAgo` — any assertion about which day a workout falls in must build its date from `startOfDay(today)` explicitly.
- **ACWR history chart cold-start** (v0.1.10.0). `TrainingLoadVisualizationService.generateTimeSeriesData` trims the series to `earliestWorkout + 28 days` — a day whose 28-day chronic window predates the data fabricates `(acute/7)/(chronic/28) = 4.0`. `ReadinessRepository` reads **118 days** of workouts (`loadHistoryWorkoutDescriptor`, 90-day window + 28-day lead-in) for the visualization so the trimmed chart fills a full 90 days, not 62. Do not narrow this read back to 90 or the chart loses a month. Consequence for tests: any fixture that asserts on `timeSeriesData`/`summary.currentStatus` needs **>28 days of history before today** (`TrainingLoadACWRConsistencyTests.fixture` carries a 29–56-day lead-in) — exactly 28 days rounds the first valid chart day to *tomorrow* and yields an empty series ("Unknown" status), a wall-clock-date flake.
- **Intent breakdown joins on `originalId`, not `WorkoutData.id`** (2026-07-09). `WorkoutData(from:)` derives `id` via `WorkoutData.stableID(from:)`: HealthKit ids (already UUID strings) pass through unchanged; non-UUID Strava ids get a deterministic RFC 4122 v5 UUID (namespace `1B4E28BA-2FA1-11D2-883F-0016D3CCA427`). `originalId` (== `StoredWorkout.id`) is the authoritative key for any join against `StoredIntentLabel` or stored data — `TrainingLoadVisualizationService.calculateIntentBreakdown` MUST key on it. The old `id.uuidString` join minted a throwaway UUID per Strava workout and silently dumped ≈79% of load into `.other`/"Unclassified". Do not add new joins on `WorkoutData.id`. (`EnhancedIntentAwareReadinessService` is safe — it operates on `[StoredWorkout]`.)
- **Load-by-intent intensity is signal-derived, never duration** (2026-07-09). `TrainingLoadVisualizationService.estimateIntensity` scores 1–10 from power-zone-weighted IF → NP/avg-power ÷ FTP → HR ÷ 185 → neutral 5.0 (no fabrication when signal is absent). Do NOT revert to the old duration heuristic (`4 + hours×1.5`) — it reported every ~1h ride as ~5.x regardless of effort. Anchors: IF 0.40→1, 1.20→10; HR 50%→1, 100%→10.
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

**Mechanism 1 — steps add to intra-day strain curve:**
- Compute excess steps = max(0, today_steps − 30day_avg_steps). Baseline fallback when no history: 5000 steps.
- Convert: `todayStepExcessTSS = min(excessSteps / 3000.0, cap)` where cap = 20% of today's workout TSS, or 2.0 on rest days.
- Pass `todayStepExcessTSS` to `RecoveryDecayService.calculateIntraDayReadiness` — it adds directly to the intra-day fatigue accumulation alongside workout TSS.

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

## Skill routing

When the user's request matches an available skill, ALWAYS invoke it using the Skill
tool as your FIRST action. Do NOT answer directly, do NOT use other tools first.
The skill has specialized workflows that produce better results than ad-hoc answers.

Key routing rules:
- Product ideas, "is this worth building", brainstorming → invoke office-hours
- Bugs, errors, "why is this broken", 500 errors → invoke investigate
- Ship, deploy, push, create PR → invoke ship
- QA, test the site, find bugs → invoke qa
- Code review, check my diff → invoke review
- Update docs after shipping → invoke document-release
- Weekly retro → invoke retro
- Design system, brand → invoke design-consultation
- Visual audit, design polish → invoke design-review
- Architecture review → invoke plan-eng-review
- Save progress, checkpoint, resume → invoke checkpoint
- Code quality, health check → invoke health

## gstack (REQUIRED — global install)

**Before doing ANY work, verify gstack is installed:**

```bash
test -d ~/.claude/skills/gstack/bin && echo "GSTACK_OK" || echo "GSTACK_MISSING"
```

If GSTACK_MISSING: STOP. Do not proceed. Tell the user:

> gstack is required for all AI-assisted work in this repo.
> Install it:
> ```bash
> git clone --depth 1 https://github.com/garrytan/gstack.git ~/.claude/skills/gstack
> cd ~/.claude/skills/gstack && ./setup --team
> ```
> Then restart your AI coding tool.

Do not skip skills, ignore gstack errors, or work around missing gstack.

Using gstack skills: After install, skills like /qa, /ship, /review, /investigate,
and /browse are available. Use /browse for all web browsing.
Use ~/.claude/skills/gstack/... for gstack file paths (the global path).
