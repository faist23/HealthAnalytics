# TODOS

## Analytics / Patterns

### BGProcessingTask Promotion: Evaluate After Phase 2a

> Note (2026-10-26): the background path is now an app-refresh task (`BGAppRefreshTaskRequest`, ~30s budget), not `BGProcessingTask`, and before then it had never fired. Any production fire-rate data that predates this fix is meaningless; re-baseline from v0.1.15.

**Priority:** P2 — gated on Phase 2a production data (≥3 months)

**What:** After Phase 2a ships, evaluate whether `BGProcessingTask` fires reliably enough for most users to promote it from "opportunistic" to "primary" trigger for pattern analysis. If BGTask fires consistently (> 80% of users trigger it within 24h of app backgrounding), flip the architecture: BGTask becomes primary, `InsightsView.onAppear` becomes display-only (no analysis trigger).

**Why:** Current design: InsightsView.onAppear is primary, BGTask is opportunistic. This adds analysis latency on every tab open (7-day staleness check + async analysis). If BGTask is reliable in practice, background analysis means patterns are ready when the user opens the tab.

**How to apply:** Monitor `UserDefaults["lastPatternAnalysisDate"]` vs. BGTask `lastFireDate` in production (via logging). If BGTask fires within 24h for most users, the architecture flip is a net win.

**Effort:** S (human: ~2h / CC+gstack: ~10min)

**Depends on / blocked by:** Phase 2a must ship. Then 3 months of production data. The Background Pass counters (Settings → Background Pass) now measure the run rate.

### Background pass throttle on battery
**Priority:** P3 — surfaced by the v0.1.16.0 adversarial review (user deferred)

**What:** HRV and workout deliveries use `.immediate` frequency, and the `.background` throttle is 5 minutes, so every delivery more than 5 minutes after the last stamp runs a full pass (HealthKit refresh, 180-day sick-day reads, the load engine over every stored workout).

**Why:** iOS can throttle background delivery for an app that spends its budget, which would delay the alerts this feature exists for.

**How to apply:** Measure on a device with Settings → Background Pass, then consider a longer background window (e.g. 1h) or `.hourly` delivery for HRV.

**Effort:** S (human: ~2h / CC+gstack: ~15min)

### A reset's Strava pull cut short loses older Strava-only rides
**Priority:** P3 — surfaced by the v0.1.22.0 review (pre-existing)

**What:** `syncAllHistoricalData` ends Strava paging on the first failed page and still reports success, so a reset whose Strava pull is cut short (a 429, a dropped connection) never refetches the older Strava-only rides. Making a failed page fail the call was tried and reverted: a persistent Strava error (the app revoked on strava.com while the token is still valid, one undecodable activity, self-sustained 429s) then re-ran the whole 10-year fetch on every sync.

**How to apply:** Track Strava's history separately: persist the oldest page reached, and resume paging from there on later syncs with a backoff and a retry cap, distinguishing transient errors (429, network) from permanent ones (401, decode).

**Effort:** S (human: ~2h / CC+gstack: ~20min)

### Forecast: learn each rider's response to hard days
**Priority:** P2. Part 2 of `docs/superpowers/specs/2026-11-10-hard-days-cap-design.md`, agreed with Craig 2026-11-10: "let's use this data as a beginning but the app should learn over time how an athlete is responding to training stimuli."

**What:** the age rules (v0.2.0.0, `HardDayRules`) are where every rider starts. From the rider's own history (recovery after hard days, ride cost, illness), move the weekly Hard limit and the spacing one step at a time, in either direction, with more evidence needed to loosen than to tighten. Never more than 3 Hard days a week, never two in a row.

**Order:** 2a is a read-only Settings screen showing each week's hard days and what followed, for Craig to check against his own memory. 2b lets the learned numbers move the plan. Each needs its own short design; what counts as "responded badly" must be checked on real weeks first.

**Why:** Craig asked for the illness case when the forecast was designed ("if the app sees trends where I get sick after three hard days in a 7 day stretch it should be aware"). Logged illnesses only started in v0.1.21, so it starts on the step-count sick-day proxy.

### Effort ratings: leftovers from the Effort Check and v0.1.26.0 reviews
**Priority:** P3. The feature itself is done (see Completed: ride cost replaced the rating-only comparison).

**What:**
- Effort Check: a lookup failure on every workout (a locked device, say) reads as "no ratings" rather than an error; a reload after an error briefly shows empty counts instead of the spinner; a cancelled load finishes as "no ratings" because the per-workout lookups swallow cancellation.
- An empty ratings read changes nothing, so deleting the only Apple rating left in the window is never synced and that rating keeps feeding ride cost. Telling "denied" from "none" needs an authorization check.
- Ratings are trusted by display name (an Apple device name); the bundle identifier (com.apple.*) is not read, and only the newest rating per workout is seen, so another app writing after Craig can hide his.

### Ride cost: known limits from the v0.1.28.0 review
**Priority:** P3. None loses data. Check against real rides in Effort Check's "Ride cost" section before changing anything.

**What:**
- **An outdoor ride recorded with GPS off reads as indoor.** It has no route, and the rule is "a GPS route means outdoor", so it is compared with trainer rides and can read as cheap. A manual entry is the same.
- **Ride length includes stops.** `mapStravaActivity` stores Strava's elapsed time, so a café stop makes a ride look longer and matches it against longer rides. Moving time would need a new stored field.
- **Rides before the first FTP on record are never priced.** No 200 W stand-in, by design. If the only snapshot is a recent Strava fetch, ride cost stays quiet until 3 comparable rides build up after it. Effort Check counts them under "No FTP on record for its date"; adding past FTPs in Settings → FTP History unlocks them.
- **The one-time indoor fill can finish on a partial list.** It stops at 50 pages (10,000 activities in 120 days), and it finishes with nothing written if every ride in Strava's list came back with no map. Its done flag (`indoorFlagFillDone`) also isn't per Strava athlete, so a later account's older rides get the flag only from the regular sync window.
- **Each analysis reads the store once more** to build the Coach card (`rideCostFlag`). Cheap at real ride counts; pass the plan's snapshot through if it ever shows up.

### Forecast plan edge cases found by the v0.1.24.0 reviews
**Priority:** P3. None loses data; all are rare or need real data to judge.

**What:**
- A failed read just after midnight shows "Forecast available after 14 days of syncing". CLAUDE.md says a failed read never reads as no history; give the card a neutral state.
- A failed notes, pattern or illness read on a cold launch still leaves the Coach paragraph and the illness cap with nothing to go on.
- The load ceiling's 4-in-28 training-day gate counts the acute week, so the fourth ride back after a layoff can flip to "Load ramping fast", and a rider training daily under load 1.0 never reaches the gate. Gate on days 8-28 and on chronic load instead, once real comebacks show what it should say.
- The injury-risk cap also says "Load ramping fast", although risk can come from trends.
- The Coach refresh spinner can end early when the tap joins a running analysis. The first-load overlay can outlast the snapshot it waited for.
- The forced score backfill's once-a-day stamp is in memory and counts a failed attempt; the unforced backfill still repeats for a rider with no sleep data.
- When the forced backfill produces the first plan, the Coach paragraph stays on the score bands until the next trigger.
- "Rode today" also labels runs and strength sessions. "Bouncing back after rest" also follows a capped Easy day.

### Backfilled score rows sit on a different scale, and the forecast's normal reads them
**Priority:** P2. Found by the forecast plan's final review. A related scale gap from the ship review belongs in the same fix: live rows keep that day's ride in their score, while the plan's start score leaves today's ride out. On a riding morning the start score can sit several points above a comparable stored row, which at the 4-point spread floor is about one band. Check it against real mornings before changing anything; a stored pre-ride score would close it.

**What:** `backfillHistoricalScores` scores each day from a two-day biometric window, so HRV and resting HR have no baseline to compare against. Fitness and fatigue also window from `Date()`, not from that row's day. Backfilled rows can therefore land well below what a live score would be, and they can't show a dip after a hard day.

**Why:** the forecast's normal and learned recovery come from these rows. For up to 28 days after an install or reset, Today can read high whatever the rider's sleep. Rows are never rewritten, and no flag separates backfilled rows from live ones.

**Fix direction:** correct the backfill's windows, or mark backfilled rows and leave them out of `ForecastProfile.learn`.

### Leftovers after the v0.1.23.0 dead-code removal
**Priority:** P4 — surfaced by the v0.1.23.0 adversarial review; none affects behavior

**What:**
- `ReadinessRepository` still reads `vo2maxData` from the stored metrics every analysis; its only consumer (`FitnessTrendAnalyzer`) was deleted.
- `PerformancePredictor` and `CoachingService` have no production callers left; `PredictionCache.store(models:)` (never called) and `ReadinessRepositoryCoachingTests` are what keep them alive. `PredictionCache.DataFingerprint` is live (the analysis cache uses it): remove the predictor types and `store(models:)`, not the fingerprint.
- `TrainingDNAAnalyzer`'s taper corroboration reads FTP snapshots with `try? … ?? []`, so a failed read scores rides at the 200 W default (pre-existing; the daily-load recompute skips instead).
- The intent-label doc comment and CLAUDE.md say nothing writes `.manual` labels; a one-day February dev build (`ActivityIntentLabelerView`, deleted in 4be4b01) could, so say "no current writer".

**Effort:** XS (human: ~1h / CC+gstack: ~10min)

## Coach

## Science

### Citation Versioning / Staleness Review
**Priority:** P3 — time-based trigger, not urgent

**What:** Periodic process for reviewing `ScienceCitation` constants in `CitationDatabase.swift` when new research supersedes existing thresholds.

**Why:** `lastVerified: Int` field was added to `ScienceCitation` for exactly this purpose. When the current year exceeds `lastVerified` by >2, citations should be reviewed. E.g., Gabbett has published follow-up ACWR work since 2016 — thresholds may have refined.

**Pros:** Keeps the app's scientific credibility intact over time.

**Cons:** Requires keeping up with sports science literature — low ongoing burden but real.

**Context:** Citations in Phase 1 will be verified at code time (2026). The first review is due ~2028. Flag in code with `// lastVerified: 2026 — review by 2028`.

**Correction (v0.1.11.0, 2026-08-07):** the "verified at code time" premise did not hold — the DOIs were never resolved, and 2 of 5 were unregistered while 2 more pointed at the wrong paper. All are now resolved against Crossref and pinned by `ScienceCitationTests.testReferenceURLsPointAtTheAttributedPaper`, so the 2028 review starts from a known-good set. Note: publisher sites 403 `curl`; use `https://doi.org/api/handles/<doi>` to check resolution.

**Update (v0.1.12.0):** six citations now, not five — the Cycling Compound Score citation moved out of `CyclingCompoundScoreCard` into the database under a new `.compoundScore` signal. It is the one link with **no registered DOI** (Journal of Science and Cycling publishes no DOI for it), so the OJS article URL is the only identifier and it carries the highest link-rot risk of the set. Check it first in 2028.

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

## Coaching Voice

### Taper detection: sharpen the intensity corroboration
**Priority:** P3 — both halves shipped in v0.1.13.0; this is tuning, not a defect

**What:** `detectTaperUnderway` fires on (volume down ≥ 30%) AND (HRV slope positive over 7 days). That is also the exact signature of stopping training involuntarily: injury, illness, a work trip, a family emergency. HRV rises on rest either way.

**Done (v0.1.13.0):** every taper-facing string now describes the measurement and hedges the projection on intent. Card headline is "Load Dropping", not "Taper Underway"; evidence reads "Volume down 41% and HRV recovering. If this is a planned taper, peak form typically lands around <date>"; the coaching line addresses both readings; both `MasterCoachEngine` branches match. Pinned by `testTaperCopyDescribesTheObservationRatherThanAssertingATaper`, `testTaperUnderway_emittedCopyIsConditional`, and the banned-phrase assertions in `MasterCoachEngineTests`.

**Also done (v0.1.13.0):** `taperIsCorroborated(referenceDate:)` gates detection on two tiers — at least one session in the last 7 days (universal, no sensors needed), and intensity retained at ≥85% of the days 8–28 baseline when both windows carry real power/HR. Reuses `TrainingLoadVisualizationService.estimateIntensity`.

**Still open — tuning, not correctness:**
- `taperIntensityRetention` (0.85) and `taperMinimumRecentSessions` (1) are reasoned defaults with no field validation. Real tapers vary a lot by discipline and event length; a 3-day crit taper and a 2-week ironman taper don't look alike.
- Users with no power meter and no HR strap get Tier 1 only, so "rode easy every day for a week after getting sick" still reads as a taper for them. Deliberate — blocking the pattern outright for thin-data users repeats the sick-day-proxy mistake — but revisit if it shows up in practice.
- A rider doing short, hard rehab sessions could satisfy both tiers while genuinely injured. The copy hedges, so the failure is soft.

**How to apply:** watch real detections before touching the constants. If tuning is needed, `taperIntensityRetention` is the sensitive knob.

**Effort:** S (human: ~3h / CC+gstack: ~15min)

## Completed

- **P2 — Forecast release 2, Part 1: hard days limited and spaced by age** — **Completed:** v0.2.0.0 (2026-11-10). `HardDayRules`: under 60, 3 Hard days in any 7 and 1 day between; from 60, 2 and 2; the day after a hard day is at most Easy at every age; the last age read is remembered. Part 2 (learning the rider's response) is open above.
- **P2 — Forecast: the same workout feeling harder is a stress signal** — **Completed:** v0.1.26.0 (2026-11-07), replaced by ride cost in v0.1.28.0 (2026-11-09): rides are priced by what their intensity should cost (`RideCost`), flagged on Coach and fed to the plan; Forecast Check removed. Leftovers are open above.
- **P3 — Re-key a manual intent label instead of deleting it with its HealthKit copy** — **Closed:** v0.1.23.0 (2026-11-02). Moot: nothing in the app writes a `.manual` intent label (`LabelSource.manual` has no writer), so every label is automatic and is re-derived for the Strava ride.
- **P3 — Forecast testability: inject ACWR instead of reading the shared singleton** — **Completed:** v0.1.23.0 (2026-11-02). `compute7DayForecast(modelContext:acwr:)` takes it as an argument.
- **P3 — Mark the load engine's pure functions `nonisolated`** — **Completed:** v0.1.23.0 (2026-11-02). `PredictiveReadinessService`, `StatisticalValidator`, `HeuristicIntentClassifier`, `WorkoutData` and the intensity/FTP helpers are nonisolated; zero actor-isolation warnings (about 20 before).
- **P3 — Test gaps: zero-twin insertion order and `detectedAt` renewal on commit** — **Completed:** v0.1.23.0 (2026-11-02). Reverse-order zero-twin test (the pair catches first- and last-row-wins); accept/decline commit-gate test.
- **P3 — Stale comments: `TrainingDNAAnalyzer.analyze` docstring and the `SingleFlight` header** — **Completed:** v0.1.23.0 (2026-11-02). Also the `needsFullHistoryFetch` comment and GEMINI.md's cache-key list.
- **P3 — MasterCoachEngine copy duplicated across LLM and heuristic paths** — **Completed:** v0.1.23.0 (2026-11-02). The simulated LLM path returns the heuristic paragraph; one copy of every sentence.
- **P3 — Dead analysis pipeline left behind by the ReadinessView deletion** — **Completed:** v0.1.23.0 (2026-11-02). Removed the per-refresh ML training and prediction, the intent-aware, zone, fitness and temporal analyses, the unread daily instruction, their fields, and seven orphaned files (about 4,100 lines).
- **P2 — Stored `.tapering` rows carry a numerator computed under the old ACWR metric** — **Closed:** v0.1.22.0 (2026-11-02). Self-healed: v0.1.13.0 shipped 2026-08-11, so any such row aged out of the 10-day active window in August; no migration needed.
- **P3 — Illness log follow-ups from the v0.1.21.0 review** — **Completed:** v0.1.22.0 (2026-11-02). Proxy lead widened to 2 days (`IllnessLog.proxyLeadDays`); old spells reaching into the window still absorb proxy windows; "Still sick" off defaults to `lastSickDay`; active Coach notes are in the Coach cache key (`lastActiveMemoryIDs`); FTP History's edit sheet uses `.sheet(item:)`.
- **P3 — A reset whose HealthKit fetch fails loses older history for good** — **Completed:** v0.1.22.0 (2026-11-02). `needsFullHistoryFetch` makes every sync retry the 10-year fetch until it succeeds.
- **P3 — Intent labels can be orphaned by the background workout refresh** — **Completed:** v0.1.22.0 (2026-11-02). The foreground upsert deletes a HealthKit copy's label with it.
- **P3 — Pattern and recovery errors share `ReadinessRepository.analysisError`** — **Completed:** v0.1.22.0 (2026-11-02). `patternAnalysisError`, read by the Training DNA card.
- **P3 — First-launch pattern analysis can run on pre-backfill scores** — **Completed:** v0.1.22.0 (2026-11-02). A run overlapping a backfill that inserted rows leaves the throttle unstamped (`scoreBackfillGeneration`); awaiting the backfill inside the run was rejected because it could fill rows before the Strava sync.
- **P3 — A hung analysis blocks every later pattern-analysis request** — **Completed:** v0.1.22.0 (2026-11-02). Foreground requests replace a run older than 10 minutes (`SingleFlight` `replacingRunsOlderThan`, generation-guarded).
- **P3 — Taper detection requires all 28 of the last 28 days to have a stored score** — **Completed:** v0.1.22.0 (2026-11-02). 24 of 28 days and 5 of the last 7, windows split by date.
- **P4 — `BreakdownRow` bar width is unclamped** — **Completed:** v0.1.22.0 (2026-11-02). `BreakdownRow.fillFraction`.
- **P2 — Phase 2b: Manual Illness Log** — **Completed:** v0.1.21.0 (2026-11-02). Built ahead of its 3-month data gate at the owner's call. `IllnessEvent` model, a Sick / I'm better chip in the Coach tab's "Anything I should know today?" bar, Settings → Illness Log; while sick or just recovered the Coach paragraph says rest / keep it easy (illness state in the Coach cache key); logged onsets join the HRV precursor's step-proxy sick windows (`IllnessLog.sickWindowStarts`). Sleep fragmentation never used sick days, so it is unaffected. `IllnessLogTests`, `CoachIllnessTests`.
- **P2 — A day's load is frozen at the first write** — **Completed:** v0.1.20.0 (2026-11-02). After a foreground sync's or zone backfill's `DataSyncCompleted`, when `SyncManager.mayRecomputeDailyLoads` (after a good recent sync; never on a reset's post), `ReadinessRepository.recomputeRecentDailyLoads` recomputes `dailyLoad` and `workoutCount` for existing rows of the last 7 complete days (keyed by `dateString`, sorted fetch, 0.01 tolerance, never creates rows, never touches today, recovery score or ACWR, never runs in the background pass). Store-trust prerequisites: `recentSyncWindowStart` (back to the start of the day 7 days ago), `lastSyncDate` advances only on a successful fetch, and the foreground upsert skips HealthKit rides paired with stored Strava rides and deletes their HealthKit-UUID copies. `DailyLoadRecomputeTests`.
- **P2 — A ride deleted on Strava keeps counting toward your training load** — **Completed:** v0.1.19.0 (2026-11-01). Each foreground sync tags stored Strava rides its newest page lists with the connected athlete (`StoredWorkout.stravaAthleteId`), then deletes a tagged ride the page no longer lists (with its intent label) only after Strava answers its own 404 "Record Not Found" for it (a 429 stops the checks); refused on an empty page, zero overlap or more than 10 missing; only with `activity:read_all` granted. Other accounts' and untagged rides are never candidates. `StravaDeletedRidesTests`.
- **P2 — Rides deleted on Strava can stop power zones from updating for your other rides** — **Completed:** v0.1.18.0 (2026-10-31). `StravaManager.fetchPowerZoneSeconds` throws `StravaError.activityNotFound` for a 404 (`streamsError(forStatus:)`), and the zone backfill writes `SyncManager.noPowerStreamCSV` for that ride without counting it toward the 3-error stop (`zoneCSVAfterFetchError`); rate limits and network errors still stop the pass. `ZoneBackfillDeletedActivityTests`.
- **P2 — Design the background pattern run properly** — **Completed:** v0.1.16.0 (2026-10-31). HealthKit background delivery (HRV + workouts) and app refresh both run one `BackgroundPatternPass` (HealthKit-only workout refresh, gated detection, abandon after 2 min; no score-row step in the background, missing rows are still filled only by the foreground refresh); store-based pattern checks read complete days ending yesterday; counters in Settings → Background Pass.
- **P2 — Background pattern-analysis task likely never runs** — **Completed:** v0.1.15.0 (2026-10-27). Request is now `BGAppRefreshTaskRequest` (matching the SwiftUI `.appRefresh` handler), Info.plist declares `UIBackgroundModes` `fetch` (missing entirely before, so `submit` always threw), and the handler routes through `runPatternAnalysis(container:trigger: .background)`. Verified firing on device by Craig.
- **P2 — Repository should own the pattern-analysis → Coach hand-off** — **Completed:** v0.1.15.0 (2026-10-27). `SingleFlight` owns pattern analysis (joins overlap, ignores caller cancellation, 5-min forced-run throttle) and shields `performFullAnalysis` from caller cancellation, so a tab swipe can no longer cache the heuristic Coach paragraph; `resetForTesting()` clears the cache state. `SingleFlightTests`, `ReadinessRepositoryPatternThrottleTests`.
- **P2 — Coach paragraph outlives the pattern card** — **Completed:** v0.1.14.0 (2026-10-26). Active pattern set added to the `refreshIfNecessary` cache check via `ReadinessRepository.canReuseCachedAnalysis`, and a successful `runPatternAnalysis` re-checks it so a launch-time analysis usually can't leave Coach behind; `ReadinessRepositoryCacheTests`. The remaining hand-off gaps were closed by "Repository should own the pattern-analysis → Coach hand-off" above.
- **P2 — `taperBaselineLoadThreshold` (0.25) too low** — **Closed, no change:** v0.1.14.0 (2026-10-26). The "week off reads as 100% taper" case is already rejected by the Tier 1 session-presence check from v0.1.13.0. Raising the floor to 1.0 (~7h zone-2/week) would hide the pattern from the weekend-warrior target user. Pinned by `testTaperUnderway_casualRiderGenuineTaper_confirmed` (fires at a 0.29 baseline) and `testTaperUnderway_casualRiderWeekOff_notConfirmed`.
- **P3 — Delete dead `ActivityIntentClassifier` + file/type name mismatch** — **Completed:** v0.1.14.0 (2026-10-26). Deleted; `IntentAwareReadinessService.swift` → `EnhancedIntentAwareReadinessService.swift`.
- **P3 — Delete deprecated ReadinessView.swift** — **Completed:** v0.1.14.0 (2026-10-26). `BackfillProgressView` and `ScoreBreakdownCard`/`BreakdownRow` relocated to their own files; the other 15 views in it had no callers.
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
