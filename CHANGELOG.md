# Changelog

All notable changes to HealthAnalytics are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]


## [0.1.13.0] - 2026-08-08

The phantom taper release. Training DNA was showing "Taper Underway — Load down 41%" while the Load tab showed perfectly normal training. Two separate things were wrong: the card never went away, and the thing that put it there was measuring the wrong number.

### Fixed
- **Pattern cards go away when the pattern does.** Nothing ever removed a Training DNA card once it appeared, and the card list — unlike the tab badge and the "patterns active" strip above it — never checked whether the pattern was still happening. So a taper detected once kept announcing itself weeks later, quoting a load drop from a month ago, while the badge beside it read 0. Cards now clear when the pattern stops showing up in your data, and every surface reads the same cutoff.
- **Patterns no longer go dark for a week after a mistimed tap.** Pattern analysis runs at most once a week, but it was marking itself "done" before doing the work — so opening the Patterns tab and immediately swiping away cancelled the run, and nothing looked again for another seven days. Combined with cards expiring on exactly the same seven-day clock, that could blank every pattern surface, including the early-illness warning on Coach, with nothing on screen to say why. The run now records itself only after it finishes, and cards stay up for ten days so they don't vanish at the moment a refresh comes due.
- **The taper card stopped always looking like the app's strongest signal.** Its confidence pill was computed from a field that, for taper only, holds a percentage rather than a count — so the arithmetic always came out above the top threshold and every taper rendered green and "Consistent", including the weakest one that barely qualified. A 30% drop now reads "Tentative" and only an emphatic cut reads "Consistent".
- **The early-illness warning is no longer pushed below a taper card.** The Training DNA list was ordered by that same percentage field, which put "Taper Underway" above every other pattern. Tapping "See HRV Precursor in Patterns" from Recovery landed you on a taper card with the warning you asked for further down. The list now follows the app's own priority order, illness first.
- **A duplicated day in stored history can't invent a taper.** If the same calendar day ended up saved twice — a partial write, an upgrade — the extra copy was counted as an extra day, and an empty duplicate dragged the recent average down far enough to trip the taper threshold on its own. Days are now collapsed before they're compared.
- **"Taper Underway" now means your training actually went down.** The detector was watching your acute:chronic ratio rather than your actual training load. That ratio drifts back toward normal on its own for about a month after you raise your training, with no change in what you're doing — so coming back from a break, or stepping up a block and holding it, registered as a 34–58% "load drop." Across ten simulated training histories the old measure got five verdicts wrong; the new one got none. It also used to miss a genuine 50% volume cut entirely.
- **A taper needs training to taper from.** A quiet stretch with almost no riding could register as a large drop from nearly nothing. There's now a floor on the baseline, which also covers older stored days that never had a load recorded.
- **The taper card stopped printing "seen in 41 of 30 taper."** Every other pattern counts occurrences ("seen in 4 of 6 blocks"); taper was putting a percentage in that slot. It now reads "load down 41% (30% threshold)". The other five cards are unchanged.

### Changed
- Recovery, Patterns, Coach, and the tab badge now share one definition of an active pattern, so they can't drift apart again.
- The Patterns header no longer says "this week" — the window is ten days, and the copy now matches.
- When there are no active patterns, the app says so plainly instead of concluding that nothing in your training stands out. It also surfaces an analysis failure rather than showing that same reassuring line when it simply couldn't look.

### Known issues
- The Coach paragraph can still mention a pattern for up to a day after its card disappears from Patterns. The advice is composed once per day and cached, so it outlives the card. Tracked for a follow-up.


## [0.1.12.0] - 2026-08-07

### Changed
- **The last research citation that could rot unnoticed is now covered.** The Cycling Compound Score card carried its citation inline, so the test that checks every "View source" link couldn't see it. It has moved in with the other five and is now pinned the same way. It was also mis-tagged internally as the biological-age signal, which meant the app was reasoning about it as the wrong kind of measurement. No change to what you see on the card.


## [0.1.11.0] - 2026-08-07

The receipts release. Every "View source" link under a health signal now opens the paper it claims to cite — two of them opened a dead page, two opened somebody else's study, and Training Balance was citing research about a metric this app doesn't even measure. Plus the load-consistency work from the last cycle.

### Fixed
- **"View source" opens the actual research paper now.** Tapping a health signal on the Coach tab shows a RESEARCH BASIS card with a link. Two of those links (HRV, Training Balance) went to a "DOI Not Found" page, and two more (Sleep, Training Load) quietly opened a *different* study than the author printed above them. All five now resolve to the paper named on screen.
- **Training Balance was citing the wrong subject entirely.** The card measures how your training splits between endurance, strength, and mobility — but the research underneath it described periodisation and training monotony, which the app doesn't measure anywhere. It now cites Momma 2022, a meta-analysis of 16 studies on exactly what the card is about: what combining strength work with aerobic work does for you.
- **Training load now updates the moment your ride lands.** Every daily ACWR point was measured as of midnight *before* that day — so the trend chart under "Training Load Balance" ignored the ride you'd just done, sat below the number printed next to it, and didn't move when that number did. A steady-load rider saw a flat 1.00 on the chart while the headline read 1.29. Every point on the 7-day and 90-day charts now closes at the end of its own day.
- **A workout that finished syncing mid-analysis no longer gets ignored.** Analysis takes a while, and any refresh requested while it was running was silently thrown away — so the Load tab could keep describing a day that didn't include your ride until something unrelated nudged it. Those requests are now queued and re-checked.
- **The Load Details card stopped contradicting itself.** It printed "Training load is elevated" directly above "Training load is optimal and recovery is good" — two sentences banded on two different ratios. Status and recommendation now come from the same ACWR as every other Load surface (an ACWR of 1.40 was being called *overreaching* by the other one).
- **The 7-day forecast now accounts for training load.** It read your recovery score and nothing else, so it happily said "Hard effort OK" for tomorrow while the Load tab was telling you to take rest days. Load now caps the label — and because the forecast assumes you don't train, the cap eases across the week as your acute window clears. It can only make a day more conservative, never less.

### Changed
- **The app no longer claims more than the research shows.** Six screens said combining cardio and strength "reduces mortality more than either alone." The study behind it only compares doing both against doing neither — it never establishes that the combination beats either one on its own. Every one of those screens now says what the evidence actually supports.
- Overload periods in Extended Analysis are listed newest first.
- Load surfaces describe, they don't instruct. The lightbulb "recommendation" line is gone from both the Load Details card and the Extended Analysis header; Extended Analysis now carries the same plain-English load sentence the Load tab uses.


## [0.1.10.0] - 2026-07-09

The vocabulary release. The score formerly labeled "Readiness" measures how recovered your body is — so now it says so. "Recovery" everywhere, and the only place you'll see "ready" is the Coach's verdict, where it belongs. Plus the Coach now actually warns you when your training load is risky, the 7-day forecast stopped hallucinating sawtooth workouts you never planned, and the Load tab now tells one consistent story about your ACWR instead of three contradictory ones.

### Changed
- The Readiness tab is now the **Recovery** tab — same battery icon, honest name. Score cards, gauges, charts, onboarding, and explainer sheets all say "Recovery" / "Recovery Score".
- Coach messages speak plain English about recovery ("You're 69% recovered — enough for moderate work") instead of score-speak; "ready" verdict language now appears only on the Coach tab.
- Load tab captions describe what your training-load ratio means ("You've done far more in the last week than your body is conditioned for") instead of issuing commands — advice stays with the Coach.
- Recovery tab summary no longer overclaims "well-recovered across the board"; it reports what the recovery signals actually show.
- The ACWR explainer sheet is titled "Training Load Explained" (it explains load, not readiness).

### Fixed
- The Coach's injury-risk warning now fires: when your recovery looks fine but your training load spikes into high-risk territory, the Coach says so ("You're 69% recovered, but injury risk is elevated from load spikes") instead of recommending moderate training. A type mismatch had silently disabled this branch in production.
- The 7-day forecast no longer oscillates: a simulated-workout feedback loop could turn a flat recovery history into a sawtooth (75 → 65 → 84 → 53) prediction. The forecast is back to a smooth trend from your actual history plus your current load ratio.
- The test target compiles again (a stale tab-constant reference had broken it since v0.1.9.0), and 21 new tests cover both Master Coach message paths, the injury-risk levels, and the forecast's clamp/homeostasis behavior.
- The Load tab now reports one ACWR everywhere. The main tab, "Load details", and "Extended Analysis" used to disagree (1.33 "Building" vs 1.80 "Overreaching") because Extended Analysis ran its own crude duration-only load math that ignored power, zones, and today's workout. Every surface now uses the same training-load model, and "Overreaching" is a real status tier (ACWR above 1.5) instead of everything above 1.3 reading as "Building".
- The ACWR trend chart no longer opens with a fake spike to 4.0. Early days whose 28-day baseline predated your data were fabricating that ratio by construction; the chart now begins once a real baseline exists. The Extended Analysis chart also reads a full 118 days of history so its "90-day" view actually shows 90 days rather than 62.
- New users with under four weeks of training history see a "Building Your Load History" message on the load chart instead of a blank plot.
- Overload-period cards in Extended Analysis are readable again — white text now sits on a dark card instead of a light-gray wash.

## [0.1.9.0] - 2026-06-07

The Intelligence redesign. Renamed the tab, killed clutter that didn't earn its slot, added a 5th tab (Labs) for experimental signals so they're discoverable without competing for primary attention. Plus a round of ACWR chart corrections and UX repairs that surfaced during the redesign.

### Added

- **5th tab: Labs.** Experimental signals get a dedicated home instead of cluttering primary surfaces or hiding in Settings. Initial residents: biological aging (`AgingAlphaCard`) and cycling compound score (`CyclingCompoundScoreCard`). Empty state shown when neither has enough data yet. Future Labs additions should announce themselves as exploration — this tab is intentional, not a graveyard.
- **Patterns tab icon badge.** Numeric count of patterns detected in the past 7 days. Driven by `@Query` directly in `MainTabView`; `.badge(0)` hides when there's nothing to see.
- **"Patterns active this week: N" header strip** at the top of the Patterns tab. Plain text — no card chrome.
- **Collapsible "Data sources" footer** at the bottom of Patterns. The `DataCollectionCard` (formerly an always-on row in the dashboard) is now a `DisclosureGroup` collapsed by default.
- **Pull-to-refresh on Coach and Patterns.** Both gestures force a sync and a force repo refresh so a deliberate pull always does visible work.

### Changed

- **Intelligence tab renamed to Patterns.** Tells the user what's inside before they tap. The previous "Intelligence" label was about the engine, not the user-visible content.
- **Performance Audit relocated** from the top of the old Intelligence tab to the bottom of Load (`StrainTabView`). Load retrospective belongs with the other load-historical content (`TSSChartCard`, `StrainRecoveryBalancePlot`).
- **"What's changed" section** consolidates the prior "Your Health Trends" + "Trends" duplication into one section using the `SimpleInsightCard` design. Dedupe by metric domain: HRV/RHR/Sleep Duration/Steps/Weight/Training Frequency come from `MetricTrend` (with explicit "7-day average. Up 19% vs your 21-day baseline (29.8 ms)." language); Sleep Consistency stays as a `SimpleInsight` and renders adjacent to Sleep Duration. Every card names both its averaging window and its baseline window.
- **"Correlations" card** collapses 5 prior sections (Sleep & Performance, HRV & Performance, Protein & Recovery, Protein & Performance, Carbs & Performance) into one card with a segmented control (Sleep / HRV / Protein / Carbs). Empty segments show a plain-English placeholder ("Log a few weeks of nutrition data to see protein patterns") instead of being absent. The card defaults to the first non-empty segment.
- **`SyncManager.performSmartSync`** now takes a `force: Bool = false` parameter that bypasses the 30-minute throttle. User-initiated refreshes (Coach toolbar button + both pull-to-refresh gestures) pass `force: true`.
- **Coach toolbar refresh button** now calls `ReadinessRepository.forceRefresh` (bypasses fingerprint cache) so the LoadingOverlay always fires on tap.

### Fixed

- **ACWR chart Monday point no longer plots at ~0.** `PredictiveReadinessService.calculateReadiness` hardcoded `Date()` as the windowing reference; the historical-trend caller filtered workouts to `<= targetDate` but the inner methods still windowed `[today-7, today]` / `[today-28, today]`. For Monday's perspective the intersection collapsed to "Monday only" — empty on rest days, yielding ACWR = 0/N = 0. Added an optional `referenceDate: Date = Date()` parameter; historical callers (the trend chart, `PerformancePredictor` training rows) now pass the date they're asking about. Default keeps current-assessment callers behavior-stable.
- **ACWR sweet-spot band extends through the full week.** The band's `xEnd` was bounded by `trend.last.date` = `startOfDay(today)` while `LineMark` used `unit: .day` (renders dots mid-day-bucket). The band ended at Saturday's column visually. Extended `xEnd` by one day so the band covers the full last bucket.
- **ACWR chart line no longer dips below the y-domain at endpoints.** Replaced `.catmullRom` interpolation (synthesises phantom control points by reflection, overshoots at endpoints) with `.monotone`.
- **Recovery → Patterns deep link** now lands on the right tab and auto-scrolls to the matching Training DNA card. Two interlocking bugs:
  - `TabCoordinator.intelligenceTab` was `= 4` but Intelligence sat at tag `3`; tap fell back to tag `0` (Coach). Constants renamed and corrected.
  - PatternsTabView had a nested-ScrollView issue (outer ScrollView embedded `InsightsView`'s inner one); `ScrollViewReader.proxy.scrollTo` fired against a non-scrolling inner view, so even when the right tab was reached, no scroll happened. Collapsed to a single ScrollView in PatternsTabView (R.6).
- **Recovery tab's pattern deep-link label** said "See <pattern> in Intelligence →" after the rename. Now says "Patterns".
- **Loading overlay reappears during repo re-analysis.** `ReadinessViewModel` and `DashboardViewModel` now forward `ReadinessRepository.$isAnalyzing` to their own `isLoading` via a Combine subscription. Previously `isLoading` was `@Published` but nothing flipped it after `analyze()`/`loadData()` were deleted in v0.1.8.0; the screen looked frozen during repo recomputes.
- **"What's changed" cards** no longer show conflicting values for the same metric. HRV and RHR previously rendered twice with different precision (36 vs 36.2) and different baseline windows, in two different card designs. Dedupe by metric domain — `MetricTrend` wins on shared domains, `SimpleInsight` covers the rest.

### Removed

- **Today's Signal card** from the old Intelligence/Patterns tab. Patterns aren't a today concept; the count now surfaces on the tab icon badge + the header strip.
- **Recommendations section** (`RecommendationCard` list). Advisory voice on a non-Coach tab violated the Phase 2.4 IA rule. The underlying `ActionableRecommendations` engine still runs; its output just no longer renders.
- **"Coming Soon: Optimal Training Windows" tile.** Don't ship coming-soon tiles in production.
- **AgingAlphaCard from `InsightsView`** (moved to Labs).
- **Two duplicate trend sections** ("Your Health Trends" + "Trends") merged into "What's changed".
- **Five duplicate correlation sections** merged into one segmented `CorrelationsCard`.

## [0.1.8.0] - 2026-06-06

### Added
- **Phase 4: Structured Ontology** — `CoachMemoryNote` now supports anatomical tagging (e.g., "Lower Body: Knee") for injuries. Added `SmartRoutingEngine` to dynamically filter workout recommendations based on active injuries (e.g., zeroing out "Running" readiness for a knee injury while preserving "Upper Body Strength"). Exposed `activityReadiness` through the `ReadinessRepository`'s `UnifiedReadiness` state.
- **Phase 5: Generative AI Integration** — Transformed `MasterCoachEngine` to support asynchronous LLM handoff for dynamic synthesis of the athlete's physiological state. The coaching paragraph is now generated dynamically using a `StateVector` encompassing readiness, load, injury risk, active patterns, memory notes, and forecasts. Migrated associated tests to `async/await`.
- **ACWR trend chart inline on Load tab** — the acute:chronic workload ratio chart is now the Load tab's hero card, rendered above the strain scale instead of buried behind an invisible sheet. A "More load detail" `NavigationLink` pushes the full `UnifiedTrainingLoadCard` for users who want the deeper view.
- **Honest "needs watch data" empty state on Load** — when `CardiovascularStrainService` has no Apple Watch HR samples to work with, the Cardio Load gauge now says so plainly instead of fabricating a strain value.
- **`REFACTOR_PLAN.md`** — architectural plan and decision log for the Phase 1–3 refactor, checked into the repo.

### Changed
- **`ReadinessRepository` is now the single source of truth.** The repository owns the `DataSyncCompleted` subscription, the analysis trigger, and all per-tab computations (cardiovascular strain, holistic metrics, today's workouts, raw chart arrays). ViewModels reduced to thin subscribers. Tab views no longer fetch SwiftData, no longer trigger analysis, no longer listen for sync completion. Coach and Readiness can no longer show divergent readiness scores because there is exactly one engine producing the number.
- **Coaching voice consolidated to the Coach tab only.** Recovery and Load now show factual descriptive captions of their respective metrics (e.g., "Your readiness is 73/100 — in the optimal range. Recovery 28/40 · autonomic 22/30 · fatigue 23/30") instead of MasterCoachEngine advisory prose. Intelligence's "Today's Signal" card shows pattern counts. The full coaching paragraph lives only on the Coach tab.
- **Settings gear icon unified to push-navigation across all tabs.** Previously bound to `.constant(false)` on Readiness and Load — taps did nothing. Now matches the existing Coach/Intelligence pattern (`NavigationLink { SettingsView() }`).
- **Granular Cardio Load Zones** — The Strain tab's Time-in-Zone metrics (Zones 1-3 vs 4-5) are now calculated using exact granular heart rate samples from `CardiovascularStrainService` instead of an inaccurate estimate based on the workout's overall average heart rate.
- **7-Day Forecast Homeostasis** — Rewrote the 7-day readiness forecast in `ReadinessRepository` to simulate cumulative fatigue and natural recovery. Instead of a flatline projection, the forecast now exhibits mean-reversion homeostasis, pulling the readiness toward a baseline of 75 while correctly compounding simulated fatigue on days a "Hard" or "Moderate" workout is recommended.

### Fixed
- **Startup sync race condition (root-cause fix)** — the prior workaround used per-view `.onReceive(DataSyncCompleted)` listeners that each re-triggered `analyze()`, so the data only got refreshed on whichever tab the user happened to be on. The repository now listens for sync completion centrally and republishes once; every tab observes the same `UnifiedReadiness` state. No more "switch tabs to make the data update."
- **Tab-switch spinner thrash** — tabs no longer re-run their own analyze pass on appear. After the first cold launch, switching between Coach / Readiness / Load / Intelligence is instant; the previous architecture lazily instantiated each tab's ViewModel and ran a fresh `.task { analyze() }` per tab.
- **"EXPLORE MY LOAD" button went nowhere** — the button tried to present a sheet whose body was gated on `readinessAssessment != nil && !acwrTrend.isEmpty`. When either guard failed, SwiftUI presented an empty modal and the user perceived the tap as broken. The button is gone; the ACWR chart it was supposed to lead to is now inline above it.
- **Lie-of-omission Cardio Load fallback** — the gauge silently displayed `acwr * 10` (capped at 21) as a fake strain value when watch data was missing. Users saw a number that looked authoritative but had no relationship to actual cardio load. Removed; honest empty state shown instead.
- **Missing LoadingOverlay during re-analysis** — `ReadinessViewModel` and `DashboardViewModel` now forward `ReadinessRepository.shared.$isAnalyzing` to their own `isLoading` published state. Without this, the overlay never appeared after the initial cold load, so pull-to-refresh and post-sync recomputes looked frozen.
- **MasterCoachEngine paragraph leaked onto Intelligence** — `InsightsView`'s "Today's Signal" card rendered `readiness.coachAdvice` when patterns were active, putting advisory prose on what should be a dashboard surface. Replaced with a descriptive pattern count.

### Removed
- **`ContentView.swift`** — 748 lines, unreachable from `@main`, dead code from a pre-`MainTabView` era. The `ErrorView` struct and `TimePeriod.xAxisStride` extension that live UI still consumed were extracted to dedicated locations.
- **`ReadinessViewModel.analyze()` / `configure()` / `computeCardiovascularStrain()` / `resolvedMaxHR()`** — analysis logic moved into `ReadinessRepository.performFullAnalysis`. View `.task` blocks calling `analyze()` removed across `CoachTabView`, `RecoveryTabView`, `StrainTabView`.
- **`DashboardViewModel.loadData()` and `holisticMetrics` computed property** — the latter was re-deriving ACWR/MET/training balance from its own fetched data, bypassing the repository's already-computed values. Both removed; `holisticMetrics` is now a `@Published` field populated via the repo subscription.
- **Unused `@Published` vars on `ReadinessViewModel`** — `performanceWindows`, `optimalTimings`, `workoutSequences` had zero consumers (grep-verified) but were being computed on every analyze pass. Net result: less wasted CPU and a smaller VM surface.
- **Per-view `.onReceive(NSNotification.Name("DataSyncCompleted"))` listeners** — replaced by a single subscription inside the repository. The `// Without this, the initial .task races with performSmartSync()` comment that documented the old workaround is gone along with the workaround itself.

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
