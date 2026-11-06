# 7-day forecast as a personal recovery plan

Date: 2026-11-03. Owner: Craig. Status: approved 2026-11-06.

## Why

The Recovery tab's 7-day forecast is supposed to answer "what can my body take this week?" Today it doesn't work. After two short nights and a rest day it says **Rest** for all seven days, while Craig knows he can ride moderate tomorrow and likely hard the day after.

The cause is the model, not the thresholds. `ReadinessRepository.compute7DayForecast` fits a straight line through the last 14 daily recovery scores and extends it a week. Then it bends that line by today's ACWR (−3 %/day compounding above 1.3, +2 %/day below 0.8, otherwise a pull toward a fixed 75). Two bad nights tilt the line down, and the forecast treats them as a trend that keeps falling. Several things are missing from it:
- that sleep debt is temporary and a rest day recovers;
- the rider's own normal level, and how fast this rider recovers;
- how the app's real score carries fatigue forward;
- the patterns the app has already learned about the rider;
- the rider's check-ins;
- today's ride;
- the fact that the rider will train this week. It assumes no workouts at all.

The competitive analysis (`/Users/craigfaist/Desktop/weatherApp/reports/HealthAnalytics competitive landscape.md`) names a working forecast as one of the two features no competitor ships. It is worth getting right.

## What it is (Craig's words)

"The forecast is of what type of ideal workout my body can best absorb and benefit from." It is a **plan**, not a prediction of the past extended forward: for each of the next 7 days, starting today, the hardest effort the body can take and benefit from, **assuming the rider followed the plan on the days before**.

It is **personal**. Craig: "the app should use its own insights to apply to the week ahead. I'm 65 and it's very difficult to do two hard days in a row, but my 40 year old self could probably do it with a recovery day after. I just don't recover as quickly as I once did."

It is **live**. Craig: "if I ride hard today and the app imports that data, the forecast should include today's workouts so far and how it impacts upcoming forecasted days. Every time a user opens the app all info presented should be based on all info up to that very moment (not just based on past days' data). That gives a user reason to check the app."

## Scope: two releases (Craig agreed)

1. **This design: the personal plan.** It covers the rider's own normal, their learned recovery speed, today's rides counted live, and the patterns the app already detects acting as limits.
2. **Later, its own release: the hard-days-before-illness limit.** Craig: "if the app sees trends where I get sick after three hard days in a 7 day stretch it should be aware when coming up with the forecast." This is a new thing for the pattern engine to learn, so it gets its own design. Logged illnesses only started in v0.1.21, so at first it would rely on the step-count sick-day proxy. It is recorded in TODOS.md, not built here. This release leaves a clean place for it: a per-week cap on Hard days that defaults to "no cap".

## Goals

1. **Day 0 is today.** The current forecast starts tomorrow.
2. **Each day builds on the one before.** A suggested rest day lifts the next day. A suggested hard day costs the next day or more, by however much this rider needs.
3. **Judged against the rider's own normal**, never fixed numbers. Hard means clearly above your usual level, Moderate means around it, Easy means a bit below, and Rest means well below.
4. **Recovery speed is learned from the rider's history.** It sets how far the score sinks after a hard day and how long it takes to come back. A slow recoverer gets more easy days after a hard one; a fast one gets fewer.
5. **Never two hard days in a row, until the history says otherwise.** This is the default whenever the learned recovery speed has too little data (and stays the answer for Craig unless his data shows otherwise).
6. **The app's own warning signs limit the plan.** Active patterns, illness and Coach notes cap days (see "Caps").
7. **Live.** Today's workouts so far and the current in-day state feed day 0 and everything after it. The plan is rebuilt every time analysis runs (on open, on return to the app, after every sync), from everything stored up to that moment.
8. **Never seven straight days of rest**, unless something keeps the rider down (a logged illness).
9. **Plain words, no new score.** Craig: "I don't want another score, just keep simple words." Each day shows a light and one word (Rest / Easy / Moderate / Hard), in the style of TrainerRoad's red and yellow light warnings. A short reason appears when the day isn't obvious.
10. **The forecast and the Coach agree.** The Coach paragraph's "today" sentence uses the plan's word for today, and its "tomorrow" line uses day 1.

## Non-goals

- Showing a recovery score as a number on the forecast.
- Planning specific workouts (intervals, durations, routes), or a training-plan generator.
- Letting the rider enter planned rides. Craig chose "assume I follow the plan".
- The hard-days-before-illness limit (release 2).
- An LLM anywhere in this.

## Anti-goals (a failure even if it technically works)

- A week of red after an ordinary bad night or two.
- Hard two days in a row for a rider whose history (or the default) says they can't take it.
- Today or tomorrow disagreeing with the Coach paragraph.
- A forecast that ignores a ride the app has already imported today.
- A number or chart creeping back onto the forecast card.

## Display (Craig picked mockup B)

The forecast card on the Recovery tab, in the place `ReadinessForecastChart` occupies now, becomes a list of 7 rows: **Today**, then weekday names. Each row has:
- a light;
- one word;
- optionally, one short reason line in secondary text.

There is no chart, no score and no confidence band.

**Lights** (my call; use DESIGN.md status tokens, never system colors):
| Word | Light | Token |
|---|---|---|
| Rest | red | `statusWarning` (ember, the closest red the palette has) |
| Easy | yellow | `statusMonitoring` (amber) |
| Moderate | green | `statusOptimal` |
| Hard | green | `statusOptimal` |

**Reasons** come from whatever actually decided that day's effort. Show at most one reason, the strongest, and none when the day is simply what recovery allows. The wording is mine; the builder may adjust it, but it must stay short, plain and descriptive:
- "Two short nights", or "Short sleep" for one night: today's recovery is low and sleep is the main driver.
- "Low recovery": today is low for another reason (HRV or resting HR).
- "Rode hard today" / "Rode today": Today, once a workout is imported. Today's word includes today's workouts (Craig, 2026-11-06), so it drops after a ride and recovers through the day, and this line says why.
- "Bouncing back after rest": the day after a suggested rest or easy day, when it moves up a level.
- "Still recovering from <weekday>": capped because of a hard day (planned or ridden) within the rider's recovery time.
- "Load ramping fast": capped by the projected ACWR ceiling.
- "HRV dipping": the HRV-precursor pattern is active.
- "Sick" / "Easing back after illness": from the illness log.
- "Travel" / "Stress" / "Injury": an active Coach note capped the day.

Voice rule (CLAUDE.md: advisory voice only on Coach). The current forecast already puts effort labels on the Recovery tab, and this keeps that one exception. The reasons are facts, not advice, and must stay that way.

## How each day is decided

The builder owns the formulas and constants. These rules are fixed:

1. **Inputs, as of the moment analysis runs:**
   - today's current recovery state: the in-day score the Coach already uses (`intraDay.currentScore`, which includes today's workouts and steps) and this morning's score;
   - **every workout stored so far today**, plus the stored workouts and FTP history the ACWR engine already reads;
   - the rider's personal normal and day-to-day spread, from their stored daily scores over the last 28 days (my call: median and a robust spread; the 14-score minimum stays);
   - the rider's learned recovery speed (rule 3);
   - active patterns, the illness state and active Coach notes.
2. **Effort bands are relative.** A day's internal score is placed against the rider's normal in units of their own spread:
   - clearly above → Hard;
   - around normal → Moderate;
   - somewhat below → Easy;
   - well below → Rest.

   The builder sets the band edges and checks them with the scenario tests. A rider with a low normal (for example, a median under 60) therefore still gets Moderate and Hard days. This replaces the fixed 80/70/60 cut-offs.
3. **Learned recovery speed.**
   - A historical day counts as a **hard day** when its `dailyLoad` is at or above the rider's own typical hard-day load (my call: the 75th percentile of their training-day loads over the last 90 days). The same rule decides whether a ride already done today, or yesterday, was hard.
   - From each past hard day, measure how far the next mornings' scores fell below normal and how many days they took to return.
   - The rider's recovery time is the median across episodes, once there are enough of them (my call: at least 4). Below that, use the default: one non-hard day after every hard day.
   - The builder may also learn the general rate at which a deviation from normal shrinks; otherwise a documented default is used.
4. **Stepping forward**, the next day's internal score:
   - moves back toward the rider's normal at the rider's rate;
   - loses the fatigue the previous day costs. That day is either today's actual load, or a planned day's typical load. Today's cost is the larger of what was ridden so far and the effort suggested (my call), so a big ride this morning always shows up in tomorrow.

   Fatigue cost comes from the app's existing load machinery, not a second model (`PredictiveReadinessService.calculateWorkoutLoad` / `RecoveryDecayService`). Each effort level's typical load comes from the rider's own history, with documented fallbacks.
5. **Projected ACWR** for each future day includes the plan's own earlier days and today's actual load. The current code assumes zero future load. The load ceiling stays a ceiling, never a floor: ACWR > 1.5 caps at Easy, 1.3–1.5 at Moderate.
6. **Caps**, the most restrictive one winning (reuse `ForecastEffort`'s `max` ordering):
   - **Recovery time:** a day within the rider's recovery time after a hard day (planned, ridden today, or ridden in the past days) is at most Moderate. With the default, that means never two Hard days in a row.
   - **Load ceiling:** rule 5.
   - **Active patterns** (`TrainingPattern.isActive`, the existing single definition):
     - HRV precursor active: today and tomorrow at most Easy ("HRV dipping").
     - Back-to-back crash active: treated as evidence the rider recovers slowly. Use at least the default recovery time even if the learned one is shorter.
   - **Elevated injury risk** (the Coach's existing `riskAssessment`): at most Moderate while it holds.
   - **Illness:** while an illness is ongoing (`IllnessState.sick`), every day is Rest, labelled "Sick". During `.recovering` (up to 2 days after the last sick day), at most Easy, labelled "Easing back after illness". This matches what the Coach already does.
   - **Coach notes** (my call): an active Injury note caps at Easy. An active Travel or Stress note caps at Moderate. A note with no end date caps every day of the plan until it is cleared.
   - **Hard days per week:** a cap that defaults to "no cap". Release 2 fills it from the learned illness and crash history.
7. **Never seven rest days without a cause:** with no illness logged, the reversion toward the rider's normal must lift the plan out of Rest within a few days. A scenario test pins this.

## Coach agreement

- The Coach's sentence about today uses the plan's day-0 word, so the Coach paragraph and the forecast card can't disagree. Today the Coach has two bands: 60–79 gives "enough for moderate work". Its after-ride intra-day note must not contradict day 0. For example, after a hard ride day 0 can read Rest with "Rode hard today", and the Coach says to rest for the remainder of the day.
- The Coach's "tomorrow" line reads day 1. Keep the `ForecastEffort.label` strings that `MasterCoachEngine.StateVector.nextDayForecast` consumes, or update the Coach consistently.
- Coach wording still lives once, in `generateHeuristicMessage`.

## Live recompute

Nothing new is scheduled, but a cached analysis older than 15 minutes is not reused, so today's word follows the in-day score (Craig: "a reason to check the app throughout the day"). The plan is computed inside `performFullAnalysis`, which already runs:
- on launch;
- on return to the foreground (`scenePhase` active);
- after every sync's `DataSyncCompleted`;
- after pattern runs;
- after illness and Coach-note changes.

Because the fingerprint cache already invalidates when workouts or the calendar day change, an imported ride produces a new plan. The builder must confirm that every input in rule 1 is covered either by the fingerprint or by the cache key (`canReuseCachedAnalysis`), and add any that aren't. Otherwise a cached plan could outlive a change.

## What changes in the code (for orientation; the builder decides)

- **`compute7DayForecast`:** replaced. The comment that rejects intra-forecast simulation ("turns a flat history into a sawtooth") is now wrong, and the alternating week it rejected is the intended behaviour. Remove it.
- **`ReadinessForecastDay`:** drops `predictedReadiness` and the confidence fields from what the view uses, and gains the effort and a reason.
- **`ReadinessForecastChart`:** becomes the list in "Display" (it can be renamed).
- **Coach:** the today sentence and the tomorrow line, as above.
- **Existing forecast tests in `PredictiveIntelligenceTests`** pin the old contract (band widening, drift to 75, compounding ACWR decay, clamps, the 80/70/60 labels). They are replaced, not kept green.
- **CLAUDE.md's "7-day forecast" bullet** is rewritten to the new contract.
- **TODOS.md** gains release 2 (the hard-days-before-illness limit).

## How we'll know it works

**Scenario tests** (in-memory store, as for the existing forecast tests). Each is a named rider history with the expected week:
- **Craig's week:** a steady normal, two low-sleep nights pushing today well below it, no ride today. Expected: Today Rest; tomorrow Moderate (or Easy); and by the day after, nothing blocks Hard. That means no cap applies, and the relative band reaches Hard once the plan's rest days lift the score above normal. Never Rest for all 7.
- **Slow recoverer:** history where scores take about 2 days to return after hard days. Expected: at least 2 non-hard days after each Hard.
- **Fast recoverer:** history where scores return the next day. Expected: one non-hard day between Hards is enough. A rider with too few episodes gets the default.
- **Low-normal rider:** median under 60. Expected: Moderate and Hard still appear.
- **Rode hard this morning:** a hard workout stored today. Expected: Today's word drops and shows "Rode hard today", tomorrow is capped by the recovery time, and the projected ACWR includes it.
- **Overloaded rider (ACWR > 1.5):** near-term days capped at Easy, with the cap relaxing later only as the plan's lighter days lower the projected ACWR.
- **Active patterns:** HRV precursor caps today and tomorrow at Easy. Back-to-back crash forces at least the default recovery time.
- **Sick:** all Rest with "Sick". After "I'm better": up to 2 days of at most Easy, then normal.
- **Poor recovery on a well-loaded rider:** the load ceiling never upgrades a low-recovery day.
- **Coach agreement:** the Coach's today sentence matches day 0's word, and its tomorrow line equals day 1.
- **Cache:** a workout stored after an analysis produces a different plan on the next refresh.

**On-device check (my call): Settings → Forecast Check.** This is a small read-only screen next to Background Pass. For each of the last 60 days that has a score row, it replays the plan as it would have stood that morning from stored data and compares day 1's suggestion with the effort that the next day's real score allowed. It shows the hit rate, counting the same level or one step off, plus the recent misses, and the rider's learned recovery time. This is how Craig judges it on his own data. The builder can drop it if replaying history needs data the store doesn't keep. If so, say so, and the scenario tests and Craig's daily use become the judge.

## Left to the builder

- The band edges, the reversion rate, how effort turns into fatigue, the typical load per effort level and the fallbacks.
- The type and field names, file layout, and whether the chart view is renamed.
- The exact reason wording, within the rules above.
- How the Forecast Check replays history.
