# TODOS

## P3 — Strain Sensitivity Calibration UI (Phase 3)

**What:** A user-adjustable sensitivity slider in Settings for the cardiovascular strain score. Maps to a ±20% offset on the normalization constant in `CardiovascularStrainService`. Range: "Less sensitive" → "More sensitive." No hex values exposed to user.

**Why:** The "transparent science" positioning means target users (who have read Gabbett 2016) will notice when their strain score doesn't match their perceived effort. Allowing calibration is an act of trust — and trust is the moat. The current normalization (70.0) is calibrated for a hard 60-min zone 4-5 effort. Athletes with higher fitness base or unusual HR profiles may need adjustment.

**Implementation notes:**
- `UserDefaults["strainSensitivityOffset"]` → Double in range [-0.2, +0.2], default 0.0
- `normalization` in `CardiovascularStrainService` becomes `70.0 * (1.0 - offset)` — higher offset = higher sensitivity = higher strain scores
- `ReadinessViewModel.computeCardiovascularStrain()` reads `UserDefaults` at compute time
- SettingsView gets a `Slider` row: "Strain Sensitivity" with labels "Lower" / "Higher"
- Show a preview: "Your hard workout would score: ~15 → ~16" as offset changes

**Effort:** S (human: ~2h / CC+gstack: ~10 min)

**Priority:** P3 — after strain tab is fully validated in production (3+ months). Not blocking Phase 2b or 2c.

---

## ~~P3 — InsightsViewModel GEMINI.md Mandate Violation~~ ✅ DONE 2026-03-27

`InsightsViewModel.analyzeData()` gutted from 370 → 78 lines. All 9 service calls (`CorrelationEngine`, `NutritionCorrelationEngine`, `BiologicalAgingService`, `ActionableRecommendations`, `PredictiveReadinessService`, `TrainingLoadCalculator`, `TrendDetector`, `InjuryRiskCalculator`, `TrainingLoadVisualizationService`) moved to `ReadinessRepository.performFullAnalysis()`. `UnifiedReadiness` gained 11 new fields. `InsightsViewModel.analyzeData()` now delegates to `ReadinessRepository.shared.refreshIfNecessary(modelContext:)` and assigns from `currentReadiness`. `InsightsView` unchanged. `weightData` fetch added to Repository; `trends` bug fix (was passing `stepData: []`, now passes real step data).

---

## ~~P3 — InsightsViewModel GEMINI.md Mandate Violation (ARCHIVED)~~

**What:** `InsightsViewModel.analyzeData()` calls `CorrelationEngine`, `BiologicalAgingService`, `PredictiveReadinessService`, and other services directly, bypassing `ReadinessRepository` entirely. The GEMINI.md mandate requires all readiness/insights logic to flow through `ReadinessRepository`.

**Why:** This is a latent architecture violation. The same pattern that was fixed for `PerformancePredictor` (moved from ViewModel → Repository in 2026-03-24 Phase 2 refactor) still exists in `InsightsViewModel`. If left unaddressed, new insights services added to Phase 2+ will have two competing integration points.

**How to apply:** Move `CorrelationEngine`, `BiologicalAgingService`, `PredictiveReadinessService` calls out of `InsightsViewModel.analyzeData()` and into `ReadinessRepository` as sub-services. Follow the `InjuryRiskCalculator` sub-service pattern exactly. `InsightsViewModel` subscribes via Combine like all other fields. Phase 2's `ReadinessRepository.runPatternAnalysis` is the correct integration point — extend it or add a sibling `runInsightsAnalysis()` method.

**Effort:** M (human: ~1 day / CC+gstack: ~20 min)

**Priority:** P3 — not blocking Phase 2a. Fix after Phase 2a ships and validates.

**Depends on / blocked by:** Phase 2a must ship first so the full ReadinessRepository call graph is stable before the InsightsViewModel refactor.

---

## P2 — BGProcessingTask Promotion: Evaluate After Phase 2a

**What:** After Phase 2a ships, evaluate whether `BGProcessingTask` fires reliably enough for most users to promote it from "opportunistic" to "primary" trigger for pattern analysis. If BGTask fires consistently (> 80% of users trigger it within 24h of app backgrounding), flip the architecture: BGTask becomes primary, `InsightsView.onAppear` becomes display-only (no analysis trigger).

**Why:** Current design: InsightsView.onAppear is primary, BGTask is opportunistic. This adds analysis latency on every tab open (7-day staleness check + async analysis). If BGTask is reliable in practice, background analysis means patterns are ready when the user opens the tab.

**How to apply:** Monitor `UserDefaults["lastPatternAnalysisDate"]` vs. BGTask `lastFireDate` in production (via logging). If BGTask fires within 24h for most users, the architecture flip is a net win.

**Effort:** S (human: ~2h / CC+gstack: ~10min)

**Priority:** P2 — gated on Phase 2a production data (≥3 months)

**Depends on / blocked by:** Phase 2a must ship. Then 3 months of production data.

---

## P2 — Phase 2b: Manual Illness Log

**What:** Manual illness log UI + `IllnessEvent` SwiftData model.

**Why:** `TrainingDNAAnalyzer` Phase 2a HRV precursor signature (Pattern Type 2) and sleep fragmentation correlation (Pattern Type 3) are gated on having HealthKit sick-day records for correlation. If HealthKit's passive sick-day detection (gaps in workout activity / sudden inactivity events) proves insufficient in practice, these two pattern types cannot surface reliably. The manual illness log is the fallback that guarantees the correlation data exists.

**Pros:** Unlocks HRV precursor and sleep fragmentation patterns for all users regardless of HealthKit passive detection quality.

**Cons:** Requires new log entry UI (one-tap or minimal interaction to log sick days) + `IllnessEvent` SwiftData model with date range. Adds some user friction, even if minimal.

**Context:** Phase 2a ships first and tests HealthKit passive detection in practice. If after 3+ months the HRV precursor and sleep fragmentation patterns are not surfacing for most users, implement this. The `SubjectiveCheckIn` model (Phase 3) follows a similar one-tap log pattern — design them consistently.

**Effort:** M (human) → S (CC+gstack)

**Priority:** P2 — dependent on Phase 2a validation

**Depends on / blocked by:** Phase 2a must ship and be validated first. Do not build until passive sick-day detection has been tested for 3+ months.

---

## P3 — Citation Versioning / Staleness Review

**What:** Periodic process for reviewing `ScienceCitation` constants in `CitationDatabase.swift` when new research supersedes existing thresholds.

**Why:** `lastVerified: Int` field was added to `ScienceCitation` for exactly this purpose. When the current year exceeds `lastVerified` by >2, citations should be reviewed. E.g., Gabbett has published follow-up ACWR work since 2016 — thresholds may have refined.

**Pros:** Keeps the app's scientific credibility intact over time.

**Cons:** Requires keeping up with sports science literature — low ongoing burden but real.

**Context:** Citations in Phase 1 will be verified at code time (2026). The first review is due ~2028. Flag in code with `// lastVerified: 2026 — review by 2028`.

**Effort:** S per citation (human: ~1 day research / CC+gstack: ~1 hour)

**Priority:** P3 — time-based trigger, not urgent

---

## ~~P3 — Design System (DESIGN.md)~~ ✅ DONE 2026-03-23

`DESIGN.md` created by `/design-consultation`. Warm Signal direction: `#0F0D0B` background, `#E8885A` terracotta accent, SF Pro Rounded for numerals, semantic status colors warm-shifted. See `DESIGN.md`.

---

## ~~P2 — ReadinessViewModel Coaching Instruction Violation~~ ✅ DONE 2026-03-27

**What:** Move `generateDailyInstruction()` from `ReadinessViewModel` into `ReadinessRepository`. Also: dedup `predictiveReadinessService.calculateReadiness()` (was called twice), remove redundant ViewModel DB count fetch + `lastDataFingerprint` guard, remove debug HR audit prints, remove `ReadinessViewModel.DailyInstruction` wrapper struct.

**Done:** `CoachingService` is now a private dependency of `ReadinessRepository`. `UnifiedReadiness.dailyInstruction: CoachingService.DailyInstruction?` — ViewModel subscribes via Combine like all other fields. GEMINI.md violation resolved.

---

## ~~P2 — ReadinessViewModel Architecture Violation~~ ✅ DONE 2026-03-24 (Phase 2)

**What:** Move `PerformancePredictor.train()` / `.predictWithUncertainty()` and `EnhancedIntentAwareReadinessService` out of `ReadinessViewModel` and into `ReadinessRepository` as sub-services.

**Why:** `ReadinessViewModel.swift:462,520` calls `PerformancePredictor.train()` and `.predictWithUncertainty()` as static methods directly, and holds an `EnhancedIntentAwareReadinessService` instance. GEMINI.md mandate: *"all readiness logic lives in ReadinessRepository."* This bypasses the `DataFingerprint` caching pattern and breaks separation of concerns.

**Pros:** Restores architecture integrity. Ensures ML training respects the same cache/fingerprint invalidation as all other readiness analysis. Enables ReadinessRepository to be the single source of truth for all readiness-related computation.

**Cons:** Refactor touches ReadinessViewModel (removes ML logic) and ReadinessRepository (adds two new sub-service calls). Risk of subtle behavioral change in caching.

**Context:** Surfaced during `/plan-eng-review` 2026-03-23. Pre-existing violation, not introduced by Phase 1. Fix pattern: follow `InjuryRiskCalculator` sub-service pattern exactly — `PerformancePredictor` becomes a private sub-service called within `ReadinessRepository.refreshIfNecessary()`.

**Effort:** human: ~1 day / CC+gstack: ~20 min

**Priority:** P2 — fix in a dedicated ReadinessRepository refactor PR

**Depends on / blocked by:** Nothing. Can be done independently.

---

## ~~P1 — ConfidenceBadge Design Token Violation~~ ✅ DONE (already implemented)

**What:** Fix `PredictionInsightCard.swift:107-128` `ConfidenceBadge` — swap hardcoded `Color.green`, `Color.blue`, `Color.orange` to design tokens `statusOptimal`, `statusRest`, `statusWarning`.

**Why:** CLAUDE.md QA mandate: *"flag any code that uses system default colors (Color.green, Color.orange, Color.blue)."* On the warm-dark background (`#0F0D0B`), system `.green` and `.orange` will look visually inconsistent with the rest of the app's warm-shifted semantic palette.

**Pros:** Consistent visual appearance. QA-clean. Trivial change.

**Cons:** None.

**Context:** Surfaced during `/plan-eng-review` 2026-03-23 badge color audit. Natural to fix in the same PR as the Phase 1 Science/Estimate badge work since we're already touching badge patterns.

**Effort:** CC+gstack: ~5 min

**Priority:** P1 — fix in the Phase 1 Science badges PR (ScienceBadgeType work)

---

## ~~P1 — Morning/Evening Navigation Mode (UX Architecture)~~ ✅ DONE 2026-03-24

**What:** Replace the current 5-tab navigation with a two-mode contextual toggle: **Morning** (readiness + today's decision + sleep summary) and **Evening** (training log + nutrition ring + tomorrow forecast + recovery action).

**Why:** Weekend warriors checking the app at 6:45am don't want to navigate 5 tabs. They want one answer. The current tab bar makes every screen feel equally weighted — but readiness is the 80% use case. Morning/Evening mode removes navigation friction entirely.

**Design direction:** Two segmented options in the bottom bar. Morning mode = Today + Readiness content merged. Evening mode = Training + Nutrition content merged. Settings accessible from both via toolbar icon.

**Pros:** Dramatically reduces cognitive load at the primary use-case moments (morning check-in, evening log). Strongest UX differentiator from WHOOP/Garmin/Oura. Independent design voice (Claude subagent) flagged this as the biggest opportunity in the space.

**Cons:** Significant architecture change — all 5 tabs need to be remapped into two contextual views. May feel constraining to power users who switch tabs frequently.

**Context:** Risk C from the `/design-consultation` session (2026-03-23). Both design voices agreed this is the right long-term direction. Deferred because it's UX architecture, not just a design token change. Implement after the color/type system from `DESIGN.md` is applied first.

**Effort:** L (human: ~1 week / CC+gstack: ~2-3 hours)

**Priority:** P1 — promoted from P2 by `/plan-ceo-review` 2026-03-24. Color/typography token sweep ships in the Phase 1 Science PR. This is next.

---

## ~~P1 — ResearchThresholdBar Boundary Tests~~ ✅ DONE (already implemented)

**What:** Add 3 missing boundary-condition unit tests to `ResearchThresholdBarTests`:
1. ACWR exactly at 1.3 — is it `optimal` or `monitoring`? (upper bound inclusive/exclusive)
2. Sleep above 9h (e.g., 10.0h) — should be `monitoring`, not `optimal`
3. HRV +20% above baseline — outside ±15% → should be `insufficient` or `monitoring`?

**Why:** These are the "hostile QA" boundary cases most likely to catch a threshold logic bug. The current 15 tests cover happy paths and the danger zone but miss the upper-bound seams.

**Pros:** 3 tests catch domain-specific bugs. Compiles and runs in seconds. Zero risk.

**Cons:** None.

**Context:** Surfaced by `/plan-ceo-review` outside voice 2026-03-24. The `zone(for:)` function is correct for known inputs but boundary inclusive/exclusive semantics have not been verified by tests.

**Effort:** S (human: ~30 min / CC+gstack: ~5 min)

**Priority:** P1 — tests are cheap; fix before the next person touches threshold logic.

**Depends on / blocked by:** Nothing. Add in any PR touching `ResearchThresholdBarTests`.

---

## ~~P2 — Analysis Error Surfacing~~ ✅ DONE 2026-03-24

**What:** Add `@Published var analysisError: String?` to `ReadinessRepository`. Set it in the `catch` block of `performFullAnalysis`. Clear it on successful analysis. Let views branch on `nil` (no data yet) vs error vs success.

**Why:** When `readinessAnalyzer` returns nil (new user with insufficient data) or a SwiftData fetch fails, `currentReadiness` stays nil and `isAnalyzing` drops to false. The UI shows a blank state with no explanation. Users think the app is broken.

**Pros:** New users get "Add some workouts to get started" instead of a blank screen. Errors get "Something went wrong — try again." Dramatically improves first-run experience.

**Cons:** Requires view-layer changes to branch on the new property.

**Context:** Surfaced by `/plan-ceo-review` 2026-03-24. Pre-existing gap, not introduced by Phase 1. `ReadinessRepository` is the single point of analysis failure — this is the right place to surface it.

**Effort:** M (human: ~4h / CC+gstack: ~20 min)

**Priority:** P2 — not blocking Phase 1, but important for first-run experience.

**Depends on / blocked by:** Nothing.

---

## ~~Phase 2a — Training DNA Pattern Engine~~ ✅ DONE 2026-03-27

**What:** Full Phase 2a implementation: `TrainingPattern` SwiftData model, `PatternType` enum, `TrainingDNAAnalyzer` (`@ModelActor`), `PatternNotificationService`, `TrainingDNACard`, `TrainingPatternTimelineView`, `InsightsView` Training DNA section (5-state machine), `ReadinessRepository.runPatternAnalysis`, `SettingsView` HRV source picker, `HealthAnalyticsApp` `.backgroundTask` + notification auth.

**Done:** All 9 files created/modified. `BGTaskSchedulerPermittedIdentifiers` in Info.plist. Bogus `com.apple.developer.background-task` entitlement removed. `@ModelActor` pattern: no custom init, use `var dataProvider: any PatternDataProvider = LivePatternDataProvider()`. `nonisolated` applied to `StatisticalValidator.bootstrapConfidenceInterval`, `PatternType.citationKey`, `LivePatternDataProvider.init()` to fix `-default-isolation=MainActor` actor isolation errors.

---

## ~~P2 — ResearchThresholdBar Exhaustive Switch~~ ✅ DONE 2026-03-27

**What:** Replace `default:` case in `ResearchThresholdBar.zone(for:)` with explicit `case .trainingBalance, .biologicalAge:`. (The `segments` and `markerFraction` switches were already exhaustive from the Phase 1 PR.)

**Done:** `zone(for:)` at `ResearchThresholdBar.swift:56` now uses explicit cases — adding a new `SignalType` is a compile error.

---

## P3 — Pattern Confirmation: Graduate from Vote-Based to Pearson at n >= 10

**What:** `detectBackToBackReadinessCrash()` starts with threshold-vote confirmation (drop > 10 points = Yes-vote; confirm if Yes-rate >= 60% and n >= 4). When the user accumulates n >= 10 back-to-back sequences in the 90-day window, the algorithm should automatically graduate to using Pearson r as the primary gate (r >= 0.55) for more rigorous confirmation.

**Why:** Pearson correlation at n=5 is statistically uninterpretable (p≈0.33 at r=0.55, df=3). Vote-based confirmation is more robust at low n. Pearson is the right tool once there's enough variance to compute a meaningful r.

**How to apply:** Add a conditional in `detectBackToBackReadinessCrash()`: if `sequences.count < 10`, use vote-based gate; otherwise use Pearson gate. Display lagCorrelation (Pearson r) in the detail sheet at all times as contextual data, but only use it as the decision variable at n >= 10.

**Effort:** S (human: ~2h / CC: ~10 min)

**Priority:** P3 — deferred to Phase 4 (Post-Mortem Coach sprint). Current sprint ships with vote-based confirmation only.

**Depends on / blocked by:** detectBackToBackReadinessCrash() must ship and accumulate real user data first.

---

## P4 — Light Mode Token Sweep: TrainingSignatureCard

**What:** When the light mode phase begins (per DESIGN.md roadmap), sweep `TrainingSignatureCard.swift` and `SpaghettiPlot` to verify all token-based colors render correctly in light mode. The Visual Spec section in the design plan uses dark-mode token values only.

**Why:** All color tokens in the Visual Spec (e.g., `Color.surface` = `#1C1915`, `Color.surfaceRaised` = `#262118`) are specified as dark-mode hex values. Light mode requires `#FFFFFF` / `#F0EDE8` equivalents. If the token extension is updated correctly for light mode, the card should work automatically — but the spaghetti plot SVG line opacities and chart background may need review since they're tuned for dark contrast.

**Pros:** Ensures the card doesn't look broken in light mode when that phase ships.

**Cons:** Requires producing data-driven light mode designs for the spaghetti plot (terracotta on light gray may need opacity adjustment). Low priority until light mode phase is scoped.

**Context:** Design review 2026-04-05. All elements use DESIGN.md tokens, so the sweep should be lightweight — verify tokens, check chart line contrast ratios, done.

**Effort:** S (human: ~2h / CC: ~10 min)

**Priority:** P4 — blocked on light mode phase (not scoped)

**Depends on / blocked by:** Light mode design system phase. DESIGN.md must define light mode token values first.
