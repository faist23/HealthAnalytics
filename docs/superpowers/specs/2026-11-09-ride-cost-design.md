# A ride that costs more than it should

Date: 2026-11-09. Owner: Craig. Status: draft for Craig's approval, with his answers on heart rate and indoor rides. It replaces the comparison in `2026-11-07-effort-drift-design.md`. Choices not quoted from Craig are my calls and are listed at the end.

## Why

Craig, on what v0.1.26–27 got wrong: "you are comparing to the forecasted schedule, while i am comparing how hard that ride felt vs how it should have felt for my fitness level. if i have what should be a moderate intensity ride and my heart rate is much higher than it should be for a moderate ride something is impacting my health."

The idea: every ride has a price your current fitness says it should cost. When a ride costs more than that, something is weighing on the body: stress, illness coming on, poor sleep, under-fuelling. It can show up in a ride before HRV or sleep shows it.

What shipped instead compares a ride's effort rating with Craig's past ratings on rides of similar length and load. "Should have felt" comes from old ratings, not from fitness, and heart rate is ignored. Forecast Check (v0.1.27.0) then tested that signal against the 7-day plan, which answers a different question.

Asked what should happen when a ride costs too much, Craig answered: "both, flag the ride and ease the coming days." On where the flag shows: "coach's tab. get rid of forecast check".

On heart rate: "all rides on strava should have heart rate--i always where a heart strap." On indoor riding: "many rides indoors using TrainerRoad or Zwift most of the time. i've riding indoors most of this year. if there is a gps route, it's an outdoor ride."

## What it is

Each ride with power and heart rate gets a **ride cost**, in two parts, both judged against what the ride's intensity should cost Craig at his current fitness:

1. **Heart rate cost.** Average heart rate compared with what that intensity normally costs him: his recent rides at the same intensity (normalized power relative to his FTP on that date). This part is the core of Craig's idea.
2. **Feel cost.** His Apple Watch effort rating compared with what he normally rates rides at that intensity. It is used when the ride has a rating.

A ride whose heart rate runs well above normal, or that felt harder than its intensity, is **flagged** on the Coach tab. Recent ride costs also **ease the coming days** of the 7-day plan, replacing the current felt-difference trend.

## Goals

1. **"Should cost" comes from current fitness.** Intensity is normalized power ÷ FTP on the ride's date, so a rise in FTP makes the same watts cheaper.
2. **Heart rate is the main signal.** The feel adds to it when there is a rating; a ride with no rating is still judged on heart rate.
3. **Judged against Craig's own normal,** not population tables: his own heart rate and his own ratings at that intensity.
4. **Flag the ride.** The Coach tab names the ride and says plainly what was off, in numbers: "Heart rate 11 bpm above your normal for this effort; felt hard for a moderate ride."
5. **Ease the coming days.** Rides costing more than they should lower the plan from tomorrow on. Rides costing less lift it, never past a limit.
6. **A trend for the plan, one ride for the flag.** A single costly ride is flagged, but it moves the plan only a little. A run of them moves it more.
7. **Silent without enough history,** both for the flag and for the plan.

## Non-goals

- Rides without power. Without watts there is no intensity to price the ride against. The feel-only comparison is dropped with this change (see Craig's calls below).
- Runs and other sports.
- Heart rate drift within a ride, or any heart rate stream. Average heart rate is what every stored ride already has: Craig always wears a chest strap, so every Strava ride carries it.
- Explaining the cause. Heat, caffeine, a new bike fit or a dying chest strap all raise heart rate, and the app can't tell which. The flag says the ride cost more, never why.
- Forecast Check. It is removed (see below).

## Anti-goals (a failure even if it works)

- A flag reading as a diagnosis ("you're getting sick").
- Normal day-to-day heart rate noise (a few beats) flagging rides.
- One odd ride swinging the plan as much as a week of them.
- A ride costing less than usual lifting a day past an illness, Coach-note, HRV-warning, load or recovery-time cap.
- A ride from another app's rating, or a ride with no heart rate, being judged as if it had one.
- An indoor ride judged against outdoor rides, or the reverse. Heart rate runs higher on a trainer at the same watts (heat, no airflow), so mixing them would flag every trainer ride in winter.

## How a ride is priced (my calls; the builder tunes the numbers with tests)

1. **Which rides.** Cycling, at least 20 minutes, known to be indoor or outdoor (below), with average heart rate, normalized power (average power when NP is missing) and a real FTP snapshot dated on or before the ride. `StoredFTPSnapshot.resolved` falls back to 200 W when there is none, and a made-up FTP would make the intensity meaningless, so such rides aren't priced. Effort Check shows how many recent rides weren't priced, and why, so a silent feature is visible. When a ride is stored from both the Watch and Strava, the Strava copy is used: it has the power. That is the copy that already carries `effortRating`.
2. **Intensity.** Normalized power ÷ FTP on that date.
3. **Comparable rides.** Craig's other priced rides in the 90 days before this one, in the same setting (indoor with indoor, outdoor with outdoor), with intensity within ±0.05 and duration within 30%. At least 3 are needed, or the part is not judged.
4. **Heart rate cost** = average heart rate − median average heart rate of the comparable rides, in beats per minute. 4 bpm or less counts as zero.
5. **Feel cost** = rating − median rating of the comparable rides that have a rating, needing 3 of them. One point or less counts as zero. This is the v0.1.26 comparison, re-keyed from load per hour to intensity relative to FTP.
6. **Ride cost**, in rating-point units so the plan math carries over: heart rate cost ÷ 4 bpm (so 8 bpm high is worth 2 points) plus the feel cost when the ride has one. Positive means the ride cost more than it should.
7. **Low heart rate never cancels a hard feel.** Heart rate running low at a given power while the ride feels hard is a known sign of overreaching, not of a cheap ride. So when the feel cost is positive, a negative heart rate cost counts as zero. A ride counts as cheaper than usual only when neither part is positive.
8. **Indoor or outdoor.** Craig's rule: "if there is a gps route, it's an outdoor ride." One exception, my call: Zwift uploads carry a virtual GPS route (Watopia and the like) and arrive as Strava type `VirtualRide`. So a ride is indoor when Strava's type is `VirtualRide` or its `trainer` flag is set, and otherwise outdoor when it has a GPS route (`map.summary_polyline` not empty), indoor when it has none. That covers TrainerRoad (no route) and Zwift (VirtualRide).

## The flag on the Coach tab

- A card under the coaching paragraph, shown when a ride in the last 3 days has a heart rate cost of 8 bpm or more, or a feel cost of 2 points or more (the newest such ride).
- It names the ride (day and title) and states each part that was off: "Heart rate 11 bpm above your normal for this effort" and, when rated, "felt hard (8) where rides like it feel moderate (5)". When the plan was eased, one more line says so: "The coming days are eased."
- The wording describes the ride and never guesses a cause. Coach voice is allowed here: this is the Coach tab.
- No card when no recent ride crosses the line. Rides that cost less than usual are not flagged.

## What it does to the plan

Same mechanics as v0.1.26, fed by ride cost instead of the felt difference:
- The trend is the weighted mean of ride costs over the last 14 complete days, each ride's weight halving every 4 days, shrunk toward 0 by one imagined as-usual ride.
- It shifts tomorrow's starting point by −0.5 spread per point, clamped to ±1, applied after today's step. Today's word never moves, and every limit stays a ceiling.
- The reason line reads "Rides costing more than usual" or "Rides costing less than usual" on days it changed the word.

## What changes elsewhere

- **Forecast Check is removed:** the Settings entry, `ForecastCheckView`, `ForecastPlanner.replay`, `ForecastCheckResult`, `loadRatedRides` and their tests, plus the CLAUDE.md sentences about them. My reading of "get rid of forecast check" is the whole screen (it predates v0.1.27), not only the "How rides feel" section added last release.
- **Effort Check's "How rides feel" section** shows each priced ride's intensity, heart rate against its normal, rating against its normal, and the trend, so Craig can check the pricing against his memory of rides.
- **Data:** one new stored field, `StoredWorkout.isIndoor: Bool?` (nil = not known, so the ride isn't priced). Heart rate, power, zones and ratings are already there. The Strava list the sync already reads includes `trainer`, `sport_type` and `map.summary_polyline`; `StravaActivity` decodes them and every upsert sets `isIndoor`. The regular sync only re-reads about a week, so a one-time fill re-reads Strava's activity list back 120 days (90 days of comparison plus the 30 days Effort Check shows) and sets `isIndoor` on rides already stored, like the power-zone backfill: once, and again if it fails. An optional field needs no migration step in SwiftData. The forecast's input signature already includes every workout's load and rating, and must also include average heart rate and power so a corrected ride rebuilds the plan.

## How we'll know it works

Scenario tests, in the style of the forecast tests:
- A ride at a usual intensity with heart rate 10 bpm above its comparable median flags and lowers the plan's coming days; at the median, it does neither.
- A ride that felt 2 points harder with heart rate 8 bpm low costs 2 points (the feel alone), not 0.
- A ride dated before Craig's first FTP snapshot is not priced.
- An indoor ride compares only with indoor rides: ten outdoor rides at the same intensity with lower heart rate don't flag it. A Zwift ride with a route is indoor; an outdoor ride with a route is outdoor; a ride with no route is indoor; a ride whose setting isn't known is not priced.
- A higher FTP makes the same watts a lower intensity, so it compares against different rides.
- A rated ride that felt 3 points harder at normal heart rate flags on feel alone; heart rate and feel high together cost more than either.
- A ride without power, heart rate or FTP is not priced. Fewer than 3 comparable rides: no judgement.
- One costly ride moves the plan less than several, and its effect fades.
- A ride costing less never lifts a day past a cap.
- The Coach card shows for a flagged ride in the last 3 days, names what was off, and is absent otherwise.
- Forecast Check is gone: the Settings entry, the code and its tests.

On device: the Coach card and Effort Check against Craig's memory of which recent rides felt off.

## Left to the builder

The numbers above (20 minutes, ±0.05 intensity, 30% duration, 90 days, 3 rides, the 4 bpm and one-point dead bands, 4 bpm per point, the 8 bpm and 2-point flag lines, 3 days for the card), checked with the scenario tests. Also where the pricing code lives (replacing `EffortAbsorption`'s comparison), the card's layout within DESIGN.md's tokens, and names.

## My calls for Craig to check

1. **Rides without power aren't judged at all,** and the old rating-only comparison is dropped. Your idea prices a ride by its intensity, and without watts there is none.
2. **The flag line:** heart rate 8 bpm above your normal for that effort, or a rating 2 points above your normal for it.
3. **Heart rate counts as much as feel at 4 bpm per rating point,** so 8 bpm high counts the same as a ride feeling 2 points harder.
4. **Rides that cost less than usual lift the plan** (as before, never past a limit), but they are not flagged. A ride is cheaper only when neither part is high: low heart rate with a hard feel counts as the feel alone.
5. **The whole Forecast Check screen goes,** not just last release's section.
6. **Rides need a real FTP snapshot on or before their date,** never the 200 W default.
7. **Zwift counts as indoor** even though it has a route: a Strava `VirtualRide` or a ride marked as on a trainer is indoor, whatever its route says.
8. **Indoor and outdoor are never compared,** so the first outdoor rides next spring may go unjudged until there are 3 comparable outdoor rides in 90 days.
