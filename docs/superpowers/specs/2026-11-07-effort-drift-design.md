# How rides feel tells the plan how well the body is absorbing work

Date: 2026-11-07. Owner: Craig. Status: approved 2026-11-07. Craig asked for a draft without questions, so every choice below not quoted from him is my call. They are listed at the end for him to check.

## Why

Craig: "If I do the same workout on two different days and one day it feels moderate and the other day it feels hard, I would conclude my body is having trouble with some kind of stress to make workouts feel harder than they should. In that case, adjustments should be made in future planned workouts to try to get more recovery."

This catches stress the plan can't see today. HRV, resting heart rate and sleep can look normal while the body is fighting something, carrying life stress, or under-fuelled. How hard a known amount of work felt is a direct read of that.

Craig, on the draft: "the self rating should help with how my body is adapting at that time. HRV may indicate similar idea, how my body can absorb workouts." So the rating is not a one-off alarm. It is a running read of absorption, alongside HRV: rides of the same work feeling harder than usual means the body is absorbing less right now, and feeling easier means it is adapting.

Effort Check (v0.1.25.0) confirmed the data exists: Craig rates his rides on Apple Watch (confirmed 2026-11-07), and Apple also stores its own heart-rate estimate.

## What it is

Each rated ride gets a **felt difference**: its rating minus what Craig usually rates rides of the same work. The recent felt differences form an **absorption trend**. A trend toward harder lowers the plan's coming days; a trend toward easier lifts them. It acts on the plan the way recovery does, through the day-to-day stepping, not as a one-day switch. A ride rated as usual, or not rated, adds nothing.

## Goals

1. **Compare against Craig's own ratings**, never a fixed scale. "Hard" for one rider is "moderate" for another.
2. **"The same workout" means similar work**, measured by the app's load engine, not by name or route.
3. **Both directions.** Rides feeling harder lowers the plan; rides feeling easier lifts it.
4. **A trend, not one ride.** Recent rides count more and older ones fade, so one odd rating moves the plan a little and a run of them moves it more.
5. **Live.** A rating entered after a ride counts as soon as the app next syncs, like a ride itself.
6. **Silent when there isn't enough history.** No comparison, no effect.

## Non-goals

- Asking for ratings inside the app. Craig rates on the Watch.
- Using Apple's estimated score as the feeling. It comes from heart rate, which is the thing being compared against.
- A Coach sentence of its own. The Coach already uses the plan's word, so it follows.
- Runs and other sports. Rides only, for now.

## Anti-goals (a failure even if it works)

- Ordinary rating noise of one point moving the plan.
- A plan that reacts to a ride whose rating belongs to another app.
- One odd rating swinging the plan as much as a week of them.
- A felt-easier trend overriding a limit: it never lifts a day past an illness, Coach-note, HRV-warning, load or recovery-time cap.
- A ride with no rating reading as "felt fine" or as "felt hard".

## How a ride is judged (my calls; the builder may tune the numbers with tests)

1. **The rating.** The newest `workoutEffortScore` related to the ride's Apple Watch workout, written by an Apple source (bundle identifier starting `com.apple.`). Any other writer is ignored.
2. **The work.** The ride's load per hour from `PredictiveReadinessService.calculateWorkoutLoad`, with duration. When the same ride is also stored from Strava, the Strava copy's load is used, since it has the power data. `WorkoutMatcher` already pairs the two.
3. **Comparable rides.** Craig's other rated rides in the last 90 days with duration within 30% and load per hour within 20%.
4. **Expected rating.** The median rating of the comparable rides, once there are at least 3 of them. Fewer than 3: no judgement.
5. **Felt difference** = rating − expected rating, in rating points. Differences of one point or less count as zero (normal noise in a 1–10 rating).

## What it does to the plan

- **Absorption trend:** a weighted mean of the felt differences from the last 14 days, with each ride's weight halving every 4 days, so last week's rides count most. Builder's call after review: the mean is shrunk toward 0 by one imagined as-usual ride, so a single odd rating doesn't reach the full shift.
- **Effect:** the trend shifts tomorrow's starting point (`z` in `ForecastPlanner`, after today's step) by −0.5 spread per point of trend, clamped to ±1 spread. Harder lowers it, easier lifts it, and the plan's own stepping carries the effect forward and lets it fade toward normal. A trend of +2 (rides feeling two points harder) is worth about one band.
- **Alongside HRV, not instead of it.** HRV, resting heart rate and sleep already set the recovery score the plan starts from; the absorption trend is added on top. When they agree, the effect is larger; when they disagree, the felt signal can catch stress HRV misses. No extra weighting rule: they simply add.
- **Today's ride** feeds the trend from tomorrow on. Today's word already reflects the ride.
- **Reasons:** "Rides feeling harder than usual" or "Rides feeling easier than usual", shown when the trend moved that day by a band, under the existing one-reason rule. A cap's reason still wins.
- **Limits still win.** Every existing cap stays a ceiling; a lift can raise a day only up to it.

## Where the data lives

- `StoredWorkout` gains `effortRating: Double?`, written for the Strava copy when one exists, otherwise the Watch copy. This is a lightweight SwiftData migration (an optional field).
- Every foreground sync re-reads ratings for the last 14 days of rides, because a rating can arrive after the ride was stored.
- The forecast's input signature includes ratings, so a new rating rebuilds the plan on the next open.
- Effort Check gains each ride's expected rating and felt difference, and the current absorption trend, so Craig can sanity-check the comparison before trusting it.

## How we'll know it works

Scenario tests, in the style of the forecast tests:
- A run of rides rated 2 above their comparable median lowers the plan's next days; a run rated 2 below lifts them.
- One such ride moves the plan less than several, and its effect fades over the 14 days.
- A one-point difference does nothing.
- A felt-easier trend never lifts a day past an illness, note, HRV, load or recovery-time cap.
- Fewer than 3 comparable rides: no effect.
- A rating from another app is ignored. An unrated ride adds nothing.
- The Strava copy's load is used when a Watch-Strava pair exists.
- A rating arriving after the ride was stored rebuilds the plan.

On device: Effort Check's new column against Craig's memory of which recent rides felt off.

## Left to the builder

The numbers above (30%, 20%, 3 rides, the one-point dead band, 14 days, 4-day half-life, 0.5 spread per point, the ±1 clamp), checked with the scenario tests, plus where the comparison code lives, field names, and how the sync re-read is batched.

## My calls for Craig to check

1. The trend uses the last 14 days, with each ride's weight halving every 4 days.
2. A one-point difference is noise and counts as zero.
3. The trend's effect is capped at about one band either way, so feel can't outvote HRV and sleep on its own.
4. Rides only, compared on duration and load per hour, 90 days of history, at least 3 comparable rides.
5. Only ratings written by Apple count.
