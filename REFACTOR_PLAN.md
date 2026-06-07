# HealthAnalytics Refactor Plan

**Status: ✅ SHIPPED in v0.1.8.0** (PR #7, merged 2026-06-06 as squash commit `0c4768f`). Phases 1.1–1.4, 2.2–2.4, and 3 landed. Phase 2.5 (Intelligence redistribution) deferred. File preserved as historical record of the architectural reasoning behind the change.

Two intertwined refactors landed in three phases. Each phase is independently shippable.

## Why

Two symptoms triggered this:
1. **Tab-switch spinners and data disagreement.** Coach loads with one number; switching to Readiness shows a different number; switching back to Coach updates it to match. Each tab independently fetches and analyzes data, races against `SyncManager.performSmartSync()`, and uses a `DataSyncCompleted` notification as a band-aid in the view layer.
2. **Insight repetition across tabs and buried charts.** The same scientific concept (ACWR, fatigue carry-forward, coaching advice) renders on three surfaces in three voices. The actual ACWR trend chart exists but is hidden behind a tap on a row that doesn't look tappable.

Underneath both: the `ReadinessRepository` was built as the single source of truth, but the ViewModels were never trimmed back. The migration is ~70% done.

## Decisions locked

| # | Decision |
|---|----------|
| 1 | `holisticMetrics` becomes a field on `UnifiedReadiness`; `ContentView.swift` is deleted (confirmed dead — unreachable from `@main`, only consumer in `CoachTabView` will pull from the repo) |
| 2 | Tab names unchanged (Coach / Readiness / Load / Intelligence). Defer renames. |
| 3 | Intelligence tab content redistribution planned (Patterns → Recovery, Performance Audit → Load) but **deferred** before shipping — no usage data to justify disturbing the tab. See Phase 2.5 below. |
| 4 | No in-flight conflicting branches. `feat/intelligence-tab` is a stale already-merged branch. |
| 5 | `DashboardViewModel` kept as thin adapter (4 published fields + repo subscription). |

---

## Phase 1 — Data architecture foundation (~1 day) — ✅ SHIPPED

**Goal**: `ReadinessRepository` owns the analysis trigger. Views become pure subscribers. Tab switches stop spinning. Data stops disagreeing between tabs.

### 1.1 Move sync trigger into the repository (~30 min) — ✅ `bebc4f5`
- Add `NotificationCenter` subscription for `DataSyncCompleted` in `ReadinessRepository`
- Add `ReadinessRepository.shared.bootstrap(modelContext:)` called once from `HealthAnalyticsApp.swift:28` after sync
- On notification fire: repo calls `refreshIfNecessary` with stored context
- Idempotent: calling `bootstrap` twice does not double-subscribe
- **Risk**: context lifecycle through `Settings → resetAllData()` (`SettingsView.swift:270`). Re-bootstrap after reset.

### 1.2 Move per-tab computations into `UnifiedReadiness` (~half day) — ✅ `eb6bd74`
Scope adaptation when implemented: `dailyTSSData` stayed in `ReadinessViewModel` because it depends on user-changeable `selectedPeriod`. The repo provides raw `workouts` + `stepCountData`; the VM derives the period-aware slice on every publish.

Add to `UnifiedReadiness`, compute inside `performFullAnalysis`:
- `cardiovascularStrain: CardiovascularStrainService.Result?` (from `ReadinessViewModel.computeCardiovascularStrain`, line 297)
- `dailyTSSData: [DailyTSSData]` (from `calculateDailyTSS`, line 390)
- `todayWorkouts: [WorkoutData]` (currently filtered inline at `ReadinessViewModel.swift:271`)
- `todaySteps: Int` (currently summed inline at lines 272–275)
- `holisticMetrics: HealthMetrics?` (mapping currently in `DashboardViewModel.holisticMetrics`, lines 132–253)
- Chart-source arrays (`hrvData`, `rhrData`, `sleepData`, `stepCountData`, `workouts`, `weightData`) — already fetched at `ReadinessRepository.swift:257–262`; just expose them

### 1.3 App launch kicks the repo, not the views (~15 min) — ✅ `96e45e7`
- `HealthAnalyticsApp.swift:30/59/92` already runs `SyncManager.performSmartSync()` — after each, also call `ReadinessRepository.shared.refreshIfNecessary(modelContext:)`
- Repo now driven by app lifecycle and sync events. Views never trigger analysis.

### 1.4 Strip the ViewModels (~3 hours, mostly deletion) — ✅ `82b1ab7`
Discovered during execution: `ContentView.swift` was hosting `ErrorView` and `TimePeriod.xAxisStride` that live UI still consumed. Both extracted to dedicated locations (`Views/ErrorView.swift`, `Models/TimePeriod.swift`) before the file deletion. Also discovered `ReadinessViewModel.performanceWindows/optimalTimings/workoutSequences` had zero live consumers — removed.

- **Delete `ContentView.swift` entirely** (748 lines, dead code)
- `ReadinessViewModel.analyze()` → delete (lines 134–288)
- `ReadinessViewModel.configure(container:)` → delete (line 127)
- `DashboardViewModel.loadData()` → delete (lines 54–128)
- `DashboardViewModel.holisticMetrics` → delete (lines 132–253) — now sourced from `UnifiedReadiness`
- `DashboardViewModel` itself → keep as thin adapter
- All `.task { await viewModel.analyze(...)/loadData() }` in tab views → delete
- All `onReceive(DataSyncCompleted)` in views → delete
- `CoachTabView.swift:62` continues to read `viewModel.holisticMetrics` because the adapter publishes the field sourced from `UnifiedReadiness`

**Phase 1 ships when**: cold launch → single sync → single repo analysis → all tabs render same data instantly on switch. No per-tab spinners after first load. No re-analyze on `DataSyncCompleted` ping-pong.

---

## Phase 2 — IA reorganization (~2–3 days) — ✅ SHIPPED (except 2.5)

**Goal**: Each tab has one job. Charts surface. Coaching voice lives in one place.

### 2.2 ACWR chart inline as Load hero (~half day) — ✅ `b679707`
In `StrainTabView`:
- Replace `TRAINING LOAD` row + sheet with `ACWRTrendCard` rendered inline at top of load section
- Delete `showStrainDetails` state (line 14) and `.sheet(isPresented: $showStrainDetails)` (lines 99–122)
- Delete `showACWRDetail` state (line 14) and `.sheet(isPresented: $showACWRDetail)` (lines 77–98)
- Delete the "EXPLORE MY LOAD" button in `insightSection` (lines 339–348). Option C from earlier discussion: kill the sheet, surface the chart.
- The `UnifiedTrainingLoadCard` content either goes inline below the chart, or to a `NavigationLink`-pushed detail view (matches settings push-navigation pattern from `8c7e5f9`)

### 2.3 Kill the Cardio Load gauge fallback (~30 min) — ✅ `b679707`
- `StrainTabView.swift:192`: replace `let strainValue = cvStrain?.strain ?? min((viewModel.readinessAssessment?.acwr ?? 0) * 10.0, 21.0)` with: if `cvStrain == nil` show "Wear your watch longer for an accurate strain score" placeholder; do not invent a strain value from ACWR.

### 2.4 MasterCoachEngine only on Coach (~half day) — ✅ `70e5cc1` + `fdd5843`
The `fdd5843` follow-up patched a Phase 2.4 leak: `InsightsView.swift:159` (embedded inside `IntelligenceTabView`) was still rendering the coach paragraph. Now shows pattern count instead.

- Audit consumers of `coachAdvice` and `dailyInstruction` fields on `UnifiedReadiness`
- `RecoveryTabView.swift:91–100` — replace `InsightBox` advisory text with descriptive caption only (what the score *is*, not what to *do*)
- `StrainTabView.swift:339` `insightSection` — same treatment; describe the load, don't prescribe action
- Coach tab keeps the full coaching paragraph
- **Single highest-leverage change for the "app repeats itself" complaint**

### 2.5 Redistribute Intelligence — **DEFERRED**
Reason: the consultant's own caveat — "I am assuming Intelligence has low engagement; if Pattern detections are your highest-rated insights in user feedback, killing the tab is wrong." We have no usage data. Phase 1 + 2.2/2.3/2.4 already deliver the bulk of the IA wins (single source of truth, ACWR surfaced, coaching voice deduped). Test the current state on device before deciding whether to disturb Intelligence.

Plan was: pattern detections → Recovery (inline list, expanding the existing `coordinator.navigate(to: intelligenceTab, scrollTo:)` link at `RecoveryTabView.swift:95-98`), Performance Audit → Load.

---

## Phase 3 — Audit and polish (~1 day) — ✅ SHIPPED `fdd5843`

Three regressions surfaced and fixed:
1. `isLoading` was `@Published` on both VMs but nothing flipped it to true after Phase 1.4 deleted `analyze()`/`loadData()`. VMs now forward `ReadinessRepository.shared.$isAnalyzing` to their own `isLoading`. LoadingOverlay reappears during repo re-analysis (post-sync, post-pull-to-refresh).
2. Phase 2.4 missed `InsightsView.swift:159` — the embedded "Today's Signal" card on the Intelligence tab still rendered the coach paragraph. Replaced with descriptive pattern count.
3. `IntelligenceTabView` had a `@State private var showSettings = false` that was never read or written (the gear icon uses `NavigationLink`). Removed.

Audit also confirmed no buttons/NavigationLinks "go nowhere" across the four live tabs.

---

## Sequencing logic

Phase 1 first → no divergence bugs during Phase 2 → bug provenance is clear if anything surfaces.

Within Phase 2: 2.2 (ACWR inline) and 2.3 (kill fallback) are highest user-visible wins, lowest risk. Then 2.4 (coaching dedupe) for highest semantic impact. 2.5 (Intelligence) last because most reversible.

## Branch / commit cadence

- All work on `feat/master-coach-engine`
- One commit per numbered step (e.g. `refactor: phase 1.1 — sync trigger into repo`)
- After each phase completes: smoke test, push
