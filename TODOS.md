# TODOS

## Analytics / Patterns

### BGProcessingTask Promotion: Evaluate After Phase 2a
**Priority:** P2 — gated on Phase 2a production data (≥3 months)

**What:** After Phase 2a ships, evaluate whether `BGProcessingTask` fires reliably enough for most users to promote it from "opportunistic" to "primary" trigger for pattern analysis. If BGTask fires consistently (> 80% of users trigger it within 24h of app backgrounding), flip the architecture: BGTask becomes primary, `InsightsView.onAppear` becomes display-only (no analysis trigger).

**Why:** Current design: InsightsView.onAppear is primary, BGTask is opportunistic. This adds analysis latency on every tab open (7-day staleness check + async analysis). If BGTask is reliable in practice, background analysis means patterns are ready when the user opens the tab.

**How to apply:** Monitor `UserDefaults["lastPatternAnalysisDate"]` vs. BGTask `lastFireDate` in production (via logging). If BGTask fires within 24h for most users, the architecture flip is a net win.

**Effort:** S (human: ~2h / CC+gstack: ~10min)

**Depends on / blocked by:** Phase 2a must ship. Then 3 months of production data.

### Phase 2b: Manual Illness Log
**Priority:** P2 — dependent on Phase 2a validation

**What:** Manual illness log UI + `IllnessEvent` SwiftData model.

**Why:** `TrainingDNAAnalyzer` Phase 2a HRV precursor signature (Pattern Type 2) and sleep fragmentation correlation (Pattern Type 3) are gated on having HealthKit sick-day records for correlation. If HealthKit's passive sick-day detection (gaps in workout activity / sudden inactivity events) proves insufficient in practice, these two pattern types cannot surface reliably. The manual illness log is the fallback that guarantees the correlation data exists.

**Pros:** Unlocks HRV precursor and sleep fragmentation patterns for all users regardless of HealthKit passive detection quality.

**Cons:** Requires new log entry UI (one-tap or minimal interaction to log sick days) + `IllnessEvent` SwiftData model with date range. Adds some user friction, even if minimal.

**Context:** Phase 2a ships first and tests HealthKit passive detection in practice. If after 3+ months the HRV precursor and sleep fragmentation patterns are not surfacing for most users, implement this. The `SubjectiveCheckIn` model (Phase 3) follows a similar one-tap log pattern — design them consistently.

**Effort:** M (human) → S (CC+gstack)

**Depends on / blocked by:** Phase 2a must ship and be validated first. Do not build until passive sick-day detection has been tested for 3+ months.

### Forecast testability: inject ACWR instead of reading the shared singleton
**Priority:** P3 — improves test isolation; fix in the next Repository-touching PR

**What:** `ReadinessRepository.compute7DayForecast` reads `currentReadiness?.readinessAssessment?.acwr` from the shared singleton when no `overrideACWR` is passed. In the test host, whatever state the app's own bootstrap left in `ReadinessRepository.shared` leaks into any test that doesn't pass an override.

**Why:** Surfaced during the v0.1.10.0 ship (2026-07-08): tests currently pass only because `currentReadiness` happens to be nil in the fresh-simulator test host. If the host app ever completes a real analysis mid-test-run, the no-override forecast tests become order/state-dependent. The repository→StateVector wiring in `performFullAnalysis` also has no test harness.

**How to apply:** Pass the ACWR (or the assessment) as an explicit parameter from `performFullAnalysis`, or make the repository injectable for tests. Follow the `dataProvider` injection pattern from `TrainingDNAAnalyzer`.

**Effort:** S (human: ~2h / CC+gstack: ~15 min)

## Coach

### MasterCoachEngine copy duplicated across LLM and heuristic paths
**Priority:** P3 — deferred from /ship review 2026-07-08

**What:** Every coaching sentence exists in two parallel copies — the mocked LLM path `synthesizeWithLLM` and the fallback `generateHeuristicMessage`. The v0.1.10.0 Recovery rename had to apply the identical copy rewrite twice.

**Why:** Any future copy edit must be made in lockstep in both functions or the two paths drift apart silently. Both paths now have direct test coverage (v0.1.10.0), which catches drift in the covered branches but not in new copy.

**How to apply:** Extract the shared sentences into private static helpers (e.g. `injuryRiskSentence(_:)`, `baselineSentence(score:patterns:)`) consumed by both paths.

**Effort:** S (human: ~2h / CC+gstack: ~15 min)

## Views

### Delete deprecated ReadinessView.swift
**Priority:** P3 — deferred from /ship review 2026-07-08

**What:** `ReadinessView` is self-described as deprecated ("analysis is now driven entirely by ReadinessRepository") and its only instantiation is its own `#Preview`. The v0.1.10.0 copy sweep still had to maintain renamed strings in it.

**How to apply:** Delete the file after relocating the shared `ScoreBreakdownCard` it defines (still used by `RecoveryTabView`). Until then, exclude it from copy sweeps.

**Effort:** S (human: ~1h / CC+gstack: ~10 min)

## Science

### Citation Versioning / Staleness Review
**Priority:** P3 — time-based trigger, not urgent

**What:** Periodic process for reviewing `ScienceCitation` constants in `CitationDatabase.swift` when new research supersedes existing thresholds.

**Why:** `lastVerified: Int` field was added to `ScienceCitation` for exactly this purpose. When the current year exceeds `lastVerified` by >2, citations should be reviewed. E.g., Gabbett has published follow-up ACWR work since 2016 — thresholds may have refined.

**Pros:** Keeps the app's scientific credibility intact over time.

**Cons:** Requires keeping up with sports science literature — low ongoing burden but real.

**Context:** Citations in Phase 1 will be verified at code time (2026). The first review is due ~2028. Flag in code with `// lastVerified: 2026 — review by 2028`.

**Effort:** S per citation (human: ~1 day research / CC+gstack: ~1 hour)

## Design

### Light Mode Token Sweep: TrainingSignatureCard
**Priority:** P4 — blocked on light mode phase (not scoped)

**What:** When the light mode phase begins (per DESIGN.md roadmap), sweep `TrainingSignatureCard.swift` and `SpaghettiPlot` to verify all token-based colors render correctly in light mode. The Visual Spec section in the design plan uses dark-mode token values only.

**Why:** All color tokens in the Visual Spec (e.g., `Color.surface` = `#1C1915`, `Color.surfaceRaised` = `#262118`) are specified as dark-mode hex values. Light mode requires `#FFFFFF` / `#F0EDE8` equivalents. If the token extension is updated correctly for light mode, the card should work automatically — but the spaghetti plot SVG line opacities and chart background may need review since they're tuned for dark contrast.

**Pros:** Ensures the card doesn't look broken in light mode when that phase ships.

**Cons:** Requires producing data-driven light mode designs for the spaghetti plot (terracotta on light gray may need opacity adjustment). Low priority until light mode phase is scoped.

**Context:** Design review 2026-04-05. All elements use DESIGN.md tokens, so the sweep should be lightweight — verify tokens, check chart line contrast ratios, done.

**Effort:** S (human: ~2h / CC: ~10 min)

**Depends on / blocked by:** Light mode design system phase. DESIGN.md must define light mode token values first.

## Completed

- **P3 — Strain Sensitivity Calibration UI** — **Completed:** v0.1.0.0 (2026-04-20). `StrainSensitivityCard` in `SettingsView`; `CardiovascularStrainService.compute(sensitivityOffset:)`; normalization 90.0 → 70.0; ±20% slider with reset and live preview.
- **P3 — InsightsViewModel GEMINI.md Mandate Violation** — **Completed:** 2026-03-27. `analyzeData()` gutted 370 → 78 lines; all 9 service calls moved to `ReadinessRepository.performFullAnalysis()`; `UnifiedReadiness` gained 11 fields; `stepData` bug fixed.
- **P3 — Design System (DESIGN.md)** — **Completed:** v0.1.7.0 (2026-05-03). Warm Signal replaced with Signal Indigo: `#09090E` background, `#7C5CFC` accent, cool-cast text tokens.
- **P2 — ReadinessViewModel Coaching Instruction Violation** — **Completed:** 2026-03-27. `CoachingService` is a private dependency of `ReadinessRepository`; `UnifiedReadiness.dailyInstruction` consumed via Combine.
- **P2 — ReadinessViewModel Architecture Violation** — **Completed:** 2026-03-24 (Phase 2). `PerformancePredictor` + `EnhancedIntentAwareReadinessService` moved into `ReadinessRepository` sub-services.
- **P1 — ConfidenceBadge Design Token Violation** — **Completed:** (already implemented). System colors swapped for `statusOptimal`/`statusRest`/`statusWarning` tokens.
- **P1 — Morning/Evening Navigation Mode (UX Architecture)** — **Completed:** 2026-03-24. Two-mode contextual toggle replacing 5-tab navigation (superseded by later five-tab IA in v0.1.9.0).
- **P1 — ResearchThresholdBar Boundary Tests** — **Completed:** (already implemented). ACWR 1.3 boundary, sleep >9h, HRV +20% cases covered.
- **P2 — Analysis Error Surfacing** — **Completed:** 2026-03-24. `@Published var analysisError: String?` on `ReadinessRepository`; views branch on nil/error/success.
- **Phase 2a — Training DNA Pattern Engine** — **Completed:** 2026-03-27. `TrainingPattern` model, `TrainingDNAAnalyzer` (`@ModelActor`), notifications, cards, timeline, `runPatternAnalysis`, BGTask registration.
- **P2 — ResearchThresholdBar Exhaustive Switch** — **Completed:** 2026-03-27. `zone(for:)` uses explicit cases; new `SignalType` is a compile error.
- **P3 — Pattern Confirmation: Graduate from Vote-Based to Pearson at n ≥ 10** — **Completed:** 2026-04-13. Combined gate in `detectBackToBackReadinessCrash()` + 4 unit tests.
- **P3 — Dead Code Sweep: Delete Unused Swift Files** — **Completed:** 2026-04-30. 5 dead ML-experiment orphans deleted from `ML-Components/`; live services retained.
- **P2 — Intelligence Tab: Coach Message → Pattern Deep-Link (E3)** — **Completed:** v0.1.6.0 (2026-05-03). `TabCoordinator` env object, `InsightBox` navigation params, `ScrollViewReader` deep-link, 4 tests.
- **P3 — Intelligence Tab: Pattern Confidence Badge (E4)** — **Completed:** v0.1.7.0 (2026-05-03). Consistent/Mixed/Tentative pill on `TrainingDNACard` with accessibility label.
- **P3 — InsightBox Design Token Sweep** — **Completed:** v0.1.7.0 (2026-05-03). Tokens throughout `GaugeStyleComponents.swift`; Signal Indigo consistent across tabs.
- **P3 — E3 Deep-Link: Cold-Tap Loading Affordance** — **Completed:** v0.1.6.1 (2026-05-03). Context-aware loading overlay message ("Opening [Pattern Name]...").
