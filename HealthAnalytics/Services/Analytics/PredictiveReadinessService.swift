//
//  PredictiveReadinessService.swift
//  HealthAnalytics
//
//  Provides ACWR and readiness calculations for ML training
//

import Foundation
import HealthKit

/// Pure load and readiness math, `nonisolated` so the pattern actor (`TrainingDNAAnalyzer`)
/// and the background pass call it without hopping to the main actor.
nonisolated class PredictiveReadinessService {
    
    struct ReadinessAssessment {
        let acwr: Double              // Acute:Chronic Workload Ratio
        let chronicLoad: Double       // 28-day average
        let acuteLoad: Double         // 7-day average
        let trend: Trend
        
        enum Trend {
            case overreaching // ACWR > 1.5 — injury-risk zone
            case building     // ACWR 1.3-1.5
            case optimal      // 0.8-1.3
            case detraining   // < 0.8
        }
    }
    
    /// Calculate readiness metrics from workout history.
    /// `ftpSnapshots` is the full FTP history for time-aware power-zone calculations.
    /// `referenceDate` is the "now" for window calculations (default `Date()`).
    /// Pass an explicit date to compute ACWR as-of a historical day — the chart
    /// trend and ML training rows both do this so each row's acute/chronic
    /// windows align to that row's day, not today.
    /// Currently only HealthKit workouts are processed; Strava power path is wired but
    /// not yet active (stravaActivities is passed as [] from all call sites).
    func calculateReadiness(
        stravaActivities: [StravaActivity],
        healthKitWorkouts: [WorkoutData],
        ftpSnapshots: [StoredFTPSnapshot] = [],
        referenceDate: Date = Date(),
        plannedDailyLoads: [Date: Double] = [:]
    ) -> ReadinessAssessment {

        // Combine all workouts
        let allWorkouts = healthKitWorkouts

        // Sort by date
        let sorted = allWorkouts.sorted { $0.startDate > $1.startDate }

        // Calculate training loads
        let chronicLoad = calculateChronicLoad(workouts: sorted, ftpSnapshots: ftpSnapshots, referenceDate: referenceDate, plannedDailyLoads: plannedDailyLoads)
        let acuteLoad = calculateAcuteLoad(workouts: sorted, ftpSnapshots: ftpSnapshots, referenceDate: referenceDate, plannedDailyLoads: plannedDailyLoads)
        
        // Calculate ratio
        let acwr = chronicLoad > 0 ? acuteLoad / chronicLoad : 1.0
        
        // Determine trend — thresholds match TrainingLoadVisualizationService.LoadStatus
        // so every surface labels the same ACWR identically.
        let trend: ReadinessAssessment.Trend
        if acwr > 1.5 {
            trend = .overreaching
        } else if acwr > 1.3 {
            trend = .building
        } else if acwr < 0.8 {
            trend = .detraining
        } else {
            trend = .optimal
        }
        
        // Debug logging removed to prevent console spam during Extended Analysis
        
        return ReadinessAssessment(
            acwr: acwr,
            chronicLoad: chronicLoad,
            acuteLoad: acuteLoad,
            trend: trend
        )
    }
    
    // MARK: - Daily Trend

    /// The instant a day's ACWR window closes.
    ///
    /// A day's ACWR has to include that day's own training — "what was my ACWR
    /// on Saturday?" means *after* Saturday's ride, not before it. Past days
    /// therefore close at the following midnight; the current day closes at
    /// `now`, because the rest of it hasn't happened yet.
    ///
    /// Passing `startOfDay(day)` instead is what made every point on the trend
    /// charts lag the headline assessment by a day and left today's ride
    /// invisible until tomorrow.
    static func windowEnd(for day: Date, now: Date = Date()) -> Date {
        let calendar = Calendar.current
        let nextMidnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: day)) ?? day
        return min(nextMidnight, now)
    }

    /// Daily ACWR series ending today, one point per calendar day.
    /// Each point windows to the close of its own day (see `windowEnd(for:now:)`),
    /// so the final point is by construction identical to the assessment returned
    /// by `calculateReadiness` for the same workouts.
    func calculateACWRTrend(
        stravaActivities: [StravaActivity] = [],
        healthKitWorkouts: [WorkoutData],
        ftpSnapshots: [StoredFTPSnapshot] = [],
        days: Int = 7,
        referenceDate: Date = Date()
    ) -> [ACWRDataPoint] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: referenceDate)
        var points: [ACWRDataPoint] = []

        for dayOffset in (0..<days).reversed() {
            guard let day = calendar.date(byAdding: .day, value: -dayOffset, to: today) else { continue }
            let assessment = calculateReadiness(
                stravaActivities: stravaActivities,
                healthKitWorkouts: healthKitWorkouts,
                ftpSnapshots: ftpSnapshots,
                referenceDate: Self.windowEnd(for: day, now: referenceDate)
            )
            points.append(ACWRDataPoint(date: day, value: assessment.acwr))
        }

        return points
    }

    // MARK: - Load Calculations

    /// Calculate chronic load (28-day rolling average) as of `referenceDate`.
    /// Window is `[referenceDate - 28 days, referenceDate]` and the daily average
    /// divides by 28 regardless of how many workouts actually fall in the window.
    private func calculateChronicLoad(workouts: [WorkoutData], ftpSnapshots: [StoredFTPSnapshot], referenceDate: Date,
                                      plannedDailyLoads: [Date: Double] = [:]) -> Double {
        let calendar = Calendar.current

        guard let twentyEightDaysAgo = calendar.date(byAdding: .day, value: -28, to: referenceDate) else {
            return 0
        }

        let totalLoad = windowLoad(workouts: workouts, ftpSnapshots: ftpSnapshots, from: twentyEightDaysAgo,
                                   through: referenceDate, plannedDailyLoads: plannedDailyLoads)

        // Daily average over 28 days
        return totalLoad / 28.0
    }

    /// Calculate acute load (7-day rolling average) as of `referenceDate`.
    /// Window is `[referenceDate - 7 days, referenceDate]` and the daily average
    /// divides by 7 regardless of how many workouts actually fall in the window.
    private func calculateAcuteLoad(workouts: [WorkoutData], ftpSnapshots: [StoredFTPSnapshot], referenceDate: Date,
                                    plannedDailyLoads: [Date: Double] = [:]) -> Double {
        let calendar = Calendar.current

        guard let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: referenceDate) else {
            return 0
        }

        let totalLoad = windowLoad(workouts: workouts, ftpSnapshots: ftpSnapshots, from: sevenDaysAgo,
                                   through: referenceDate, plannedDailyLoads: plannedDailyLoads)

        // Daily average over 7 days
        return totalLoad / 7.0
    }

    /// Everything in `[start, end]`: stored workouts, plus the forecast's planned days (keyed by start of day).
    private func windowLoad(workouts: [WorkoutData], ftpSnapshots: [StoredFTPSnapshot], from start: Date, through end: Date,
                            plannedDailyLoads: [Date: Double]) -> Double {
        let ridden = workouts.filter { $0.startDate >= start && $0.startDate <= end }.reduce(0.0) { sum, workout in
            sum + calculateWorkoutLoad(workout, ftpSnapshots: ftpSnapshots)
        }
        let planned = plannedDailyLoads.filter { $0.key >= start && $0.key <= end }.values.reduce(0, +)
        return ridden + planned
    }

    /// Representative intensity factor (fraction of FTP) at the middle of each power zone Z1–Z7.
    /// Shared with `TrainingLoadVisualizationService.estimateIntensity`.
    static let zoneIntensityFactors: [Double] = [0.40, 0.65, 0.83, 0.98, 1.13, 1.35, 1.60]

    /// TSS for an hour whose intensity is unknown (no power): scored as endurance riding
    /// (an hour in Z2 is ~42, tempo ~69). `sportMultiplier` scales it per sport.
    static let unknownIntensityTSSPerHour = 50.0

    /// Training load for one workout, in TSS: the app's one load unit (100 = an hour at FTP).
    ///
    /// Every path returns TSS, so rides scored different ways add up on one scale. They
    /// didn't before: zone time was weighted 0.5–10 per hour while NP gave IF² per hour, and a
    /// ride waiting for its Strava stream scored about a quarter of what it scored once the
    /// stream landed (median 3.9× across 1,290 real rides). That made a new ride's day read as
    /// detraining.
    ///
    /// Priority: NP (the standard TSS, and it arrives with the Strava activity, so the score
    /// doesn't move when the stream is backfilled) → zone time (IF² at each zone's midpoint)
    /// → average power (reads low on variable rides) → duration × sport rate.
    func calculateWorkoutLoad(_ workout: WorkoutData, ftpSnapshots: [StoredFTPSnapshot]) -> Double {
        let durationHours = workout.duration / 3600.0

        if workout.workoutType == .cycling {
            let ftp = ftpSnapshots.isEmpty
                ? PredictiveReadinessService.resolvedFTP()
                : StoredFTPSnapshot.resolved(for: workout.startDate, snapshots: ftpSnapshots)

            // PATH 1: normalized power (standard TSS = IF² × hours × 100).
            if let np = workout.normalizedPower, np > 0, ftp > 0 {
                return Self.tss(intensityFactor: np / ftp, hours: durationHours)
            }
            // PATH 2: time in each power zone (stream backfilled, no NP).
            if let zoneSecs = workout.powerZoneSeconds {
                return zip(zoneSecs, Self.zoneIntensityFactors).reduce(0.0) { sum, pair in
                    sum + Self.tss(intensityFactor: pair.1, hours: pair.0 / 3600.0)
                }
            }
            // PATH 3: average power (a HealthKit-only ride).
            if let avg = workout.averagePower, avg > 0, ftp > 0 {
                return Self.tss(intensityFactor: avg / ftp, hours: durationHours)
            }
        }

        // PATH 4: no power — an hour of unknown effort, scaled per sport.
        return durationHours * Self.unknownIntensityTSSPerHour * sportMultiplier(for: workout.workoutType)
    }

    static func tss(intensityFactor: Double, hours: Double) -> Double {
        intensityFactor * intensityFactor * hours * 100.0
    }

    /// Current FTP from UserDefaults. Used when no snapshot history is available.
    /// Returns 200W as a fallback — console warning fires so it's visible during analysis.
    internal static func resolvedFTP() -> Double {
        let stored = UserDefaults.standard.integer(forKey: "strava_ftp")
        if stored > 0 { return Double(stored) }
        #if DEBUG
        print("⚠️ FTP not set — defaulting to 200W. Go to Settings → Training Zones and tap Sync.")
        #endif
        return 200.0
    }

    /// Sport-specific intensity multipliers
    private func sportMultiplier(for type: HKWorkoutActivityType) -> Double {
        switch type {
        case .running:
            return 1.2  // Running is more taxing per hour
        case .cycling:
            return 1.0  // Baseline
        case .swimming:
            return 1.3  // Very demanding
        case .functionalStrengthTraining, .traditionalStrengthTraining:
            return 1.1  // Moderate impact
        case .walking:
            return 0.5  // Low intensity
        default:
            return 1.0  // Default
        }
    }
}

