//
//  ScoreRowFinalization.swift
//  HealthAnalytics
//
//  Which stored StoredDailyScore days must be recomputed. `backfillHistoricalScores`
//  skips days that already have a row, so a row written mid-afternoon on the user's
//  last open kept that partial load forever — including after an evening ride.
//

import Foundation

enum ScoreRowFinalization {
    /// Matches the backfill horizon (`backfillHistoricalScores` covers 90 days).
    nonisolated static let maxRecomputeDays = 90

    /// Days to recompute: from the day after `finalizedThrough` through yesterday, never
    /// today, at most `maxRecomputeDays` back. Nil when nothing is due, including a
    /// `finalizedThrough` in the future. With no marker yet (an upgrading user) the whole
    /// horizon is due once: the old backfill froze any mid-day row it wrote, on any of
    /// those days, and only a full pass can find them.
    nonisolated static func recomputeRange(
        finalizedThrough: Date?,
        now: Date,
        calendar: Calendar = .current
    ) -> ClosedRange<Date>? {
        let today = calendar.startOfDay(for: now)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
              let horizon = calendar.date(byAdding: .day, value: -maxRecomputeDays, to: today)
        else { return nil }

        var start = horizon
        if let finalizedThrough {
            let finalizedDay = calendar.startOfDay(for: finalizedThrough)
            guard finalizedDay < yesterday,
                  let next = calendar.date(byAdding: .day, value: 1, to: finalizedDay)
            else { return nil }
            start = max(next, horizon)
        }
        return start...yesterday
    }

    /// Whether a backfill actually looked at the user's history: HRV or resting HR came
    /// back non-empty. A locked device or missing permission reads nothing. Sleep is not
    /// required: a user who doesn't track sleep still has HRV/RHR, and requiring it kept
    /// their marker unset, so every run recomputed the whole horizon.
    nonisolated static func readBiometrics(hrvCount: Int, restingHRCount: Int) -> Bool {
        hrvCount > 0 || restingHRCount > 0
    }
}
