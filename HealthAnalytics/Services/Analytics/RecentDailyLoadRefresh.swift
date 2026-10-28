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
    /// wrote mid-day on any of those days get their full load once.
    nonisolated static let upgradeLoadRecomputeDays = 90
    nonisolated static let upgradeDoneKey = "dailyLoadRecomputeV1Done"

    struct DayLoad: Equatable, Sendable {
        var dailyLoad: Double
        var workoutCount: Int
    }

    nonisolated static func daysToRefresh(upgradeDone: Bool) -> Int {
        upgradeDone ? recentLoadRecomputeDays : upgradeLoadRecomputeDays
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
    /// whose day has an entry in `loads` and whose values differ. Rows on any other day
    /// are untouched; readinessScore and dailyStrain are never written. Returns the
    /// number of rows changed.
    static func apply(_ loads: [Date: DayLoad], to rows: [StoredDailyScore], calendar: Calendar = .current) -> Int {
        var changed = 0
        for row in rows {
            guard let target = loads[calendar.startOfDay(for: row.date)],
                  row.dailyLoad != target.dailyLoad || row.workoutCount != target.workoutCount
            else { continue }
            row.dailyLoad = target.dailyLoad
            row.workoutCount = target.workoutCount
            changed += 1
        }
        return changed
    }
}
