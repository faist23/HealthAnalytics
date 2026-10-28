//
//  RecentDailyLoadRefresh.swift
//  HealthAnalytics
//
//  Re-derives the last week's StoredDailyScore dailyLoad and workoutCount from
//  StoredWorkout. `backfillHistoricalScores` fills only missing days, so a row written
//  mid-afternoon (or before a Strava upload arrived) kept that day's partial load. Only
//  load and count move: readinessScore and dailyStrain (ACWR) are never rewritten, today
//  stays owned by `upsertDailyScore`, and no row is ever inserted.
//

import Foundation

enum RecentDailyLoadRefresh {
    /// Complete days re-derived on every refresh: a ride syncing late lands within a week.
    nonisolated static let recentLoadRecomputeDays = 7
    /// One-time pass on upgrade, matching the backfill horizon: rows the old backfill
    /// wrote mid-day on any of those days get their full load once. Only-raise: before
    /// the app's first sync the backfill counted HealthKit workouts that were never stored
    /// as StoredWorkout, and a stored-only recompute would wrongly lower those days.
    nonisolated static let upgradeLoadRecomputeDays = 90
    nonisolated static let upgradeDoneKey = "dailyLoadRecomputeV1Done"

    struct DayLoad: Equatable, Sendable {
        var dailyLoad: Double
        var workoutCount: Int
    }

    struct Pass: Equatable, Sendable {
        let days: Int
        let onlyRaise: Bool
    }

    /// The passes one refresh runs, in order: the one-time 90-day only-raise pass until
    /// it has run, then always the exact 7-day pass (the sync stores every HealthKit
    /// workout in that range, so a lower stored load there is the truth).
    nonisolated static func passes(upgradeDone: Bool) -> [Pass] {
        let recent = Pass(days: recentLoadRecomputeDays, onlyRaise: false)
        return upgradeDone ? [recent] : [Pass(days: upgradeLoadRecomputeDays, onlyRaise: true), recent]
    }

    /// The `count` complete calendar days before today, oldest first, each at its start
    /// of day. Never today. Calendar-day arithmetic, so a 23h or 25h DST day is one day.
    nonisolated static func completeDays(count: Int, now: Date, calendar: Calendar = .current) -> [Date] {
        guard count > 0 else { return [] }
        let today = calendar.startOfDay(for: now)
        return (1...count).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
    }

    /// Load and workout count per day in `days` (every day gets an entry, zero when it
    /// had no workout). A workout belongs to the calendar day it started on.
    nonisolated static func loads(
        days: [Date], workouts: [WorkoutData], calendar: Calendar = .current, load: (WorkoutData) -> Double
    ) -> [Date: DayLoad] {
        var result = Dictionary(uniqueKeysWithValues: days.map { (calendar.startOfDay(for: $0), DayLoad(dailyLoad: 0, workoutCount: 0)) })
        for workout in workouts {
            let day = calendar.startOfDay(for: workout.startDate)
            guard result[day] != nil else { continue }
            result[day]!.dailyLoad += load(workout)
            result[day]!.workoutCount += 1
        }
        return result
    }

    /// Writes `dailyLoad` and `workoutCount` onto every row (duplicate twins included)
    /// whose day has an entry in `loads` and whose values differ. With `onlyRaise`, each
    /// field moves only upward (the one-time pass). Rows on any other day are untouched;
    /// readinessScore and dailyStrain are never written. Returns the number of rows changed.
    static func apply(_ loads: [Date: DayLoad], to rows: [StoredDailyScore], calendar: Calendar = .current, onlyRaise: Bool = false) -> Int {
        var changed = 0
        for row in rows {
            guard let target = loads[calendar.startOfDay(for: row.date)] else { continue }
            let load = onlyRaise ? max(row.dailyLoad, target.dailyLoad) : target.dailyLoad
            let count = onlyRaise ? max(row.workoutCount, target.workoutCount) : target.workoutCount
            guard row.dailyLoad != load || row.workoutCount != count else { continue }
            row.dailyLoad = load
            row.workoutCount = count
            changed += 1
        }
        return changed
    }
}
