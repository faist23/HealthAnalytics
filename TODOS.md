# TODOS

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

## P1 — ConfidenceBadge Design Token Violation

**What:** Fix `PredictionInsightCard.swift:107-128` `ConfidenceBadge` — swap hardcoded `Color.green`, `Color.blue`, `Color.orange` to design tokens `statusOptimal`, `statusRest`, `statusWarning`.

**Why:** CLAUDE.md QA mandate: *"flag any code that uses system default colors (Color.green, Color.orange, Color.blue)."* On the warm-dark background (`#0F0D0B`), system `.green` and `.orange` will look visually inconsistent with the rest of the app's warm-shifted semantic palette.

**Pros:** Consistent visual appearance. QA-clean. Trivial change.

**Cons:** None.

**Context:** Surfaced during `/plan-eng-review` 2026-03-23 badge color audit. Natural to fix in the same PR as the Phase 1 Science/Estimate badge work since we're already touching badge patterns.

**Effort:** CC+gstack: ~5 min

**Priority:** P1 — fix in the Phase 1 Science badges PR (ScienceBadgeType work)

---

## P2 — Morning/Evening Navigation Mode (UX Architecture)

**What:** Replace the current 5-tab navigation with a two-mode contextual toggle: **Morning** (readiness + today's decision + sleep summary) and **Evening** (training log + nutrition ring + tomorrow forecast + recovery action).

**Why:** Weekend warriors checking the app at 6:45am don't want to navigate 5 tabs. They want one answer. The current tab bar makes every screen feel equally weighted — but readiness is the 80% use case. Morning/Evening mode removes navigation friction entirely.

**Design direction:** Two segmented options in the bottom bar. Morning mode = Today + Readiness content merged. Evening mode = Training + Nutrition content merged. Settings accessible from both via toolbar icon.

**Pros:** Dramatically reduces cognitive load at the primary use-case moments (morning check-in, evening log). Strongest UX differentiator from WHOOP/Garmin/Oura. Independent design voice (Claude subagent) flagged this as the biggest opportunity in the space.

**Cons:** Significant architecture change — all 5 tabs need to be remapped into two contextual views. May feel constraining to power users who switch tabs frequently.

**Context:** Risk C from the `/design-consultation` session (2026-03-23). Both design voices agreed this is the right long-term direction. Deferred because it's UX architecture, not just a design token change. Implement after the color/type system from `DESIGN.md` is applied first.

**Effort:** L (human: ~1 week / CC+gstack: ~2-3 hours)

**Priority:** P1 — promoted from P2 by `/plan-ceo-review` 2026-03-24. Color/typography token sweep ships in the Phase 1 Science PR. This is next.

---

## P1 — ResearchThresholdBar Boundary Tests

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

## P2 — ResearchThresholdBar Exhaustive Switch

**What:** Replace `default:` case in `ResearchThresholdBar.segments` with explicit `case .trainingBalance, .biologicalAge:`. Use `@unknown default:` (or no default) to get compiler exhaustiveness checking on future `SignalType` additions.

**Why:** Currently, adding a new `SignalType` enum case without updating `ResearchThresholdBar` silently renders the generic 3-zone bar. The compiler cannot catch this. An explicit exhaustive switch makes missing cases a compile error.

**Pros:** Compile-time safety. Zero runtime cost. Future `SignalType` additions are forced to handle the bar explicitly.

**Cons:** Trivial maintenance burden.

**Context:** Surfaced by `/plan-ceo-review` 2026-03-24. The `default:` fallback is reasonable now (only 6 `SignalType` cases) but will silently fail as the signal catalog grows.

**Effort:** S (human: ~5 min / CC+gstack: ~2 min)

**Priority:** P2 — do in any PR that touches `ResearchThresholdBar`.

**Depends on / blocked by:** Nothing.
