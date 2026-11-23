# Hard days: age sets the start, the rider's response moves it

Date: 2026-11-10. Owner: Craig. Status: draft for Craig's approval, revised four times the same day: after his corrections, the research he asked for, and his direction that the app learn each rider's response. Choices not quoted from Craig are my calls and are listed at the end. This is release 2 of `2026-11-03-forecast-plan-design.md`.

## Why

Craig, on the first draft of this design, which set no limit until the app had learned one from his illnesses: "at my age 65 my body can't absorb three hard days in one week. it could 20 years ago and maybe even 10 years ago. a prescribed hard day should be followed by an easy day or recovery day (which is even easier than easy day)."

The plan today breaks both halves of that:

- **It can schedule 3 or 4 Hard days in a week.** The only spacing rule is the recovery time after each hard day (`recoveryDays`, 1 by default), so the plan can alternate Hard and not-Hard all week. The weekly cap exists in the planner (`ForecastPlanInput.hardDaysPerWeekCap`) but nothing fills it.
- **The day after a Hard day can read Moderate.** The recovery-time cap holds that day to "at most Moderate", not Easy.

The first draft made the app prove a limit from illness history before applying one. That history is thin (logging began 2 November 2026), so the plan would have kept offering weeks Craig knows he can't absorb. He has already said what the limit is. The plan starts from it, and the history can only make it stricter.

Craig, on the second draft, which gave every rider the limit of 2: "the app needs to take age of user into account. the #1 rule applying to every rider is wrong. as a body ages, less stress can be absorbed in a short amount of time."

The app already reads the rider's age from Apple Health (`HealthKitManager.getUserAge()`, used by the Aging Alpha card and the max heart rate fallback). The plan has never used it.

Craig, on the research-based rules: "good. let's use this data as a beginning but the app should learn over time how an athlete is responding to training stimuli." So the age rules are where every rider starts, and each rider's own history moves them. The research points the same way: fitness and training history explain part of what gets blamed on age.

His earlier ask is one case of that learning: "if the app sees trends where I get sick after three hard days in a 7 day stretch it should be aware when coming up with the forecast."

## What it is

**Part 1: two rules, from day one, no history needed.**

1. **A limit on Hard days in any 7, set by the rider's age.** Hard days ridden and Hard days planned both count. Once the 6 days before a day hold the limit, that day is at most Moderate, with the reason "Enough hard days this week".

   | Age | Hard days in any 7 | Days after a Hard day before the next |
   |---|---|---|
   | under 60 | 3 | at least 1 |
   | 60 and over | 2 | at least 2 |

   See "What the research says" for where these come from and how firm they are.
2. **The day after a Hard day is at most Easy.** It reads Easy, or Rest when recovery is low (Craig: a recovery day "is even easier than easy day"). This holds for a planned Hard day, a hard ride today, and a hard ride yesterday.
3. **From 60, a second day stays below Hard.** The pattern is Hard, Easy or Rest, at most Moderate, then Hard is possible again. Under 60 the minimum stays one day. In Part 1 the rider's learned recovery time can lengthen either, never shorten it.

**Part 2: the app learns how this rider responds, and moves both numbers.** Age is the start, not the answer. From the rider's own history the app learns how they come back after hard days and what follows their heavier weeks, and it shifts the weekly limit and the spacing one step at a time, in either direction. Tightening takes less evidence than loosening.

## What the research says

Searched 2026-11-10. The evidence is thin, mostly small studies of trained men, and none gives a number of hard days per week by age. What it does support:

- **Older athletes take longer to recover full power from hard intervals.** Men of about 62 needed 5 days to recover peak leg power after one interval session; men of about 22 needed 3 (Herbert et al. 2015, as reported in Knowles et al. 2015). The same group concluded that three interval sessions a week is too fatiguing for older men and trained them once every 5 days. One later sprint-interval study found both ages ready again after 3 days, so the gap is not settled.
- **The repair process is slower.** Masters triathletes built muscle protein more slowly than younger ones across three days of hard training (Doering et al. 2016; 5 and 6 athletes). After a trail race, strength came back more slowly in masters runners (Easthope et al. 2010).
- **Trained masters cyclists can repeat the performance but feel worse doing it.** Over three straight days of 30-minute time trials, and for 48 hours after sprint intervals, cyclists in their 40s and 50s matched the younger riders' power but reported more soreness and fatigue and less recovery (Fell et al. 2006, 2008; Borges et al. 2018).
- **Two reviews say an age effect on recovery is likely but under-studied,** and that fitness and training history explain part of what gets blamed on age (Fell & Williams 2008; Borges et al. 2016).
- **Coaching practice for masters:** two or three hard sessions a week, some coaches one or two every 7 to 10 days. Opinion, not trials.

What that means here:

- The studies compare about 22 with about 55 to 62. Nothing locates a change by decade, so the first draft's three bands claimed more than anyone knows. Two bands is as fine as the evidence goes, and the line at 60 comes from the Herbert age group and Craig's own account ("maybe" at 55, not at 65).
- Recovery of 5 days at about 62 puts the ceiling for that age at one to two hard sessions a week, which agrees with Craig's 2. Even the young men needed 3 days, so 4 a week for anyone was too loose; under 60 is now 3.
- The clearest age finding is about spacing, not weekly count. So age also sets the minimum gap after a Hard day, which the previous draft left out.
- Masters feel the cost before their power shows it. That supports what ride cost already does with heart rate and the effort rating; no change needed.
- Fitness matters as well as age. The rider's own learned recovery time and illness history stay in, and can only tighten.

Sources: Fell & Williams 2008, J Aging Phys Act 16:97-115 (pubmed.ncbi.nlm.nih.gov/18268815); Borges et al. 2016, J Aging Phys Act 24:149-157; Borges et al. 2018, Exp Aging Res; Fell et al. 2006 and 2008, J Sports Med Phys Fitness; Doering et al. 2016, Med Sci Sports Exerc; Easthope et al. 2010, Eur J Appl Physiol; Knowles et al. 2015, Age 37:25 (pmc.ncbi.nlm.nih.gov/articles/PMC4359174), citing Herbert et al. 2015. Read at abstract level except Knowles; the builder does not need them, and none is shown in the app.

## Goals

1. **The plan never offers a week the rider's age says they can't absorb.** For Craig at 65, no third Hard day in 7, whatever the recovery score says.
   - **Age comes from Apple Health** and moves the limit on its own as the rider crosses a band.
2. **A Hard day is always followed by an Easy or Rest day.**
3. **Both rules are ceilings.** They lower a day; they never raise one and never override a stricter cap (illness, HRV dipping, load ramping).
4. **The rider's response moves the start.** Both numbers can tighten or loosen from the age start as the history shows how this rider absorbs hard days. One step at a time, and more evidence to loosen than to tighten.
5. **One definition of an illness and of a hard day.** The illness list the HRV precursor uses (`IllnessLog.sickWindowStarts`), and the plan's own hard-day line (`ForecastProfile.hardLoad`).
6. **He can see what the history shows,** including when it shows nothing, and why.

## Non-goals

- More than 3 hard days a week, or two Hard days in a row, for anyone. Learning moves the numbers inside those bounds.
- A setting for the limit, or for age. Age is whatever Apple Health holds.
- Using age anywhere else in the plan (band edges, how far a hard day sinks the score).
- Changing the recovery score or the Coach paragraph's wording. The Coach already speaks from the plan's words for today and tomorrow.
- A notification for the learned pattern.

## Anti-goals

- Any path by which thin or missing data loosens the rules. Only a clear record of absorbing more does.
- A second, slightly different rule for what a sick day or a hard day is.

## Part 1: the two rules in the planner

- `hardDaysPerWeekCap` stops being optional-and-empty: it is the age limit from the table, unless Part 2 has lowered it. The planner's cap code and its reason already exist. The age-to-limit rule is a pure function.
- `recoveryDays` gets an age floor: 1 under 60, 2 from 60. The learned value applies when it is longer (still at most 3).
- **Age unknown** (no birth date in Apple Health, or the read is refused): use the last age the app read successfully, which it now remembers. If it has never read one, use the under-60 rules. A failed read must not loosen a limit the app has already applied.
- The recovery-time cap becomes: the **first** day after a hard day is at most Easy; any further learned recovery days (`recoveryDays` of 2 or 3) stay at most Moderate, as now. The reason stays "Still recovering from <weekday>".
- "Rode hard today" still caps today itself at Moderate; that is the same day, not the day after.
- Nothing else in the stepping changes. The Hard day's cost to the next morning (`dip`) already tends to put the next day in the Easy band; the cap makes it a rule, not a tendency.

Existing tests that pin "at most Moderate" on the day after a hard day are updated, not kept green. The Coach's tomorrow line follows day 1 and needs no change.

## Part 2: learning the rider's response

This part gets its own short design before it is built, after Part 1 has been in use: what counts as "responded badly" has to be checked against Craig's real weeks first. What is fixed now:

**What the app watches.** All three signals exist today; none is new.

- **Recovery after hard days:** how far the recovery score falls and how many days it takes to return to the rider's normal (`ForecastProfile`'s learned recovery time and dip).
- **Ride cost:** rides costing more than their intensity should, in heart rate and feel (`RideCost`).
- **Illness:** logged illnesses and low-step sick windows, one list (`IllnessLog.sickWindowStarts`).

**What it learns from them.**

1. **Spacing** (days after a Hard day before the next). The learned recovery time already lengthens it. New: it is measured from the age start, and it can shorten by one day below the age start when the rider's hard days are consistently followed by a return to normal within the shorter time and rides aren't costing more than usual. Never under 1.
2. **The weekly limit.** For each past week, count the hard days and look at what followed: an illness, a run of low recovery beyond the usual day or two, or rides costing more than usual.
   - **Tighten by one** when weeks at the rider's limit are followed by those outcomes clearly more often than lighter weeks are. Craig's case is the illness form of this: "if the app sees trends where I get sick after three hard days in a 7 day stretch it should be aware".
   - **Loosen by one** when the rider has ridden weeks above their limit, repeatedly, and they were followed by none of those outcomes. Never past 3.
3. **Compared with the rider's ordinary weeks.** An outcome that follows heavy weeks no more often than light ones is not evidence. This is what keeps a coincidence from moving a number.
4. **Asymmetric and slow.** One step at a time, re-judged as history accumulates. Tightening needs a handful of clear cases; loosening needs more of them over a longer stretch, and none of the bad outcomes.
5. **A failed read or thin history changes nothing.** The numbers stay where they were.

**Step one of Part 2 is read-only.** Before any learned number moves the plan, a Settings screen shows the evidence: the rider's age start, each recent week's hard-day count and what followed it, the recovery time measured after hard days, and what the app would conclude. Craig checks it against his own memory, as he did with Effort Check before ride cost. The learned numbers go live in the release after.

**Where it lives.** The spacing lesson stays in `ForecastProfile.learn`, beside the recovery time it extends. The weekly-limit lesson is a pure function over days, outcomes and the age start; whether it also appears as a pattern card is for Part 2's design.

## What Craig sees

- **Forecast card:** for Craig, no more than 2 Hard days in the week, each followed by Easy or Rest. A day held back by the weekly limit shows "Enough hard days this week".
- **Settings (Part 2):** a read-only screen with the age start, the numbers in use, and the weeks and outcomes behind them, including when nothing has been learned and why.

## Constraints

- Store reads follow the existing rule: complete days ending yesterday, never `Date()` as the upper bound (logged onsets keep their documented exception).
- A failed read gives no result. It never reads as "no illnesses" or "no bad weeks", and it never moves a number.
- The Part 2 screen shows the last analysis result; the view does no fetching or analysis of its own.

## How we'll know it works

Planner scenarios (pure):
- **Age to limit:** 59 gives 3 a week and 1 day between; 60 and 65 give 2 a week and 2 days between; unknown with a remembered age uses that age; never known gives the under-60 rules.
- **Spacing at 65:** after a Hard day, the next day is Easy or Rest, the day after is at most Moderate, and Hard is possible on the third.
- **Fresh and well recovered all week, age 65:** exactly 2 Hard days in the 7, never 3, each followed by Easy or Rest.
- **Same week, age 45:** 3 Hard days, each followed by Easy or Rest.
- **Two hard rides already this week, age 65:** no Hard day until the older one is 7 days back; the reason reads "Enough hard days this week".
- **Rode hard today:** tomorrow is at most Easy.
- **Rode hard yesterday:** today is at most Easy.
- **Slow recoverer (`recoveryDays` 2):** day after Hard at most Easy, the day after that at most Moderate.
- **Stricter cap wins:** sick, HRV dipping and load ramping still override.

Part 2's scenarios are written with its design. The ones already known: a rider whose heavy weeks precede illness tightens by one; a rider who always trains at the limit with ordinary outcomes doesn't; too few cases changes nothing; a rider of 62 with a long record of absorbing three hard days a week loosens to 3; a failed read changes nothing.

On device: the forecast card over a normal week.

## Order of work

1. **Part 1: the age rules.** A small planner change that fixes the plan Craig sees today. Ship on its own.
2. **Part 2a: the read-only evidence screen.**
3. **Part 2b: the learned numbers move the plan,** after Craig has checked 2a against his own weeks.

## Left to the builder

Part 1: names, where the remembered age is kept, and the wording of test names. Part 2's constants and outcome definitions belong to its own design.

Also in Part 1's change: TODOS.md replaces the release 2 entry with Part 2 as described here, moves the superseded "same workout feeling harder" entry to Completed with its open leftovers kept, and corrects the P4 line about `PredictionCache` (`PredictionCache.DataFingerprint` is live). CLAUDE.md's forecast bullet (which says the weekly cap is nil and the day after is Moderate) and the recovery-time floor are updated.

## My calls for Craig to check

1. **Two age bands, split at 60:** under 60 gives 3 hard days a week, 60 and over gives 2. The research compares riders of about 22 with riders of about 55 to 62 and can't place the change more finely; 60 matches the one study with day-by-day recovery and your own account.
   - **From 60, two days pass before the next Hard day,** not one. This is new since the last draft and comes from the 5-day recovery finding. For you a week can read Hard, Easy, Moderate, Hard, then no Hard until the first is 7 days back.
   - **Nothing tightens by age alone past 60.** I found no studies of riders in their 70s and 80s to set it from; the illness history and your learned recovery time are what tighten it.
   - **The easy day after a Hard day applies at every age.**
   - **With no age in Apple Health and none ever read,** the under-60 rules apply.
2. **Only the first day after a Hard day is held to Easy.** If your learned recovery time is 2 or 3 days, the later ones stay at most Moderate, as now.
3. **The day you ride hard still reads at most Moderate for what remains of it** ("Rode hard today"), unchanged.
4. **Learning works in both directions,** and loosening takes more evidence than tightening. You said the app should learn how an athlete responds; I read that as able to give a fit rider more as well as hold a struggling one back. For you it would loosen only if your own record showed weeks of three hard days absorbed cleanly.
5. **Hard bounds that learning can't cross:** never more than 3 hard days a week, never two Hard days in a row, never under 1 day of spacing.
6. **Low-recovery runs and costly rides count as a bad response,** alongside illness. An earlier draft used illness only.
7. **Low-step sick windows count as illnesses** when no logged illness covers them. Adding the illnesses you remember from the past year in Settings → Illness Log makes this accurate.
8. **Part 2 starts as a read-only screen,** and moves the plan only in the release after you've checked it.
9. **Ship Part 1 on its own first.**
