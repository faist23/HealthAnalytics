//
//  PredictiveReadinessService.swift
//  HealthAnalytics
//
//  Provides ACWR and readiness calculations for ML training
//

import Foundation
import HealthKit

class PredictiveReadinessService {
    
    struct ReadinessAssessment {
        let acwr: Double              // Acute:Chronic Workload Ratio
        let chronicLoad: Double       // 28-day average
        let acuteLoad: Double         // 7-day average
        let trend: Trend
        
        enum Trend {
            case building    // ACWR > 1.3
            case optimal     // 0.8-1.3
            case detraining  // < 0.8
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
        referenceDate: Date = Date()
    ) -> ReadinessAssessment {

        // Combine all workouts
        let allWorkouts = healthKitWorkouts

        // Sort by date
        let sorted = allWorkouts.sorted { $0.startDate > $1.startDate }

        // Calculate training loads
        let chronicLoad = calculateChronicLoad(workouts: sorted, ftpSnapshots: ftpSnapshots, referenceDate: referenceDate)
        let acuteLoad = calculateAcuteLoad(workouts: sorted, ftpSnapshots: ftpSnapshots, referenceDate: referenceDate)
        
        // Calculate ratio
        let acwr = chronicLoad > 0 ? acuteLoad / chronicLoad : 1.0
        
        // Determine trend
        let trend: ReadinessAssessment.Trend
        if acwr > 1.3 {
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
    
    // MARK: - Load Calculations

    /// Calculate chronic load (28-day rolling average) as of `referenceDate`.
    /// Window is `[referenceDate - 28 days, referenceDate]` and the daily average
    /// divides by 28 regardless of how many workouts actually fall in the window.
    private func calculateChronicLoad(workouts: [WorkoutData], ftpSnapshots: [StoredFTPSnapshot], referenceDate: Date) -> Double {
        let calendar = Calendar.current

        guard let twentyEightDaysAgo = calendar.date(byAdding: .day, value: -28, to: referenceDate) else {
            return 0
        }

        let recentWorkouts = workouts.filter { $0.startDate >= twentyEightDaysAgo && $0.startDate <= referenceDate }

        guard !recentWorkouts.isEmpty else { return 0 }

        let totalLoad = recentWorkouts.reduce(0.0) { sum, workout in
            sum + calculateWorkoutLoad(workout, ftpSnapshots: ftpSnapshots)
        }

        // Daily average over 28 days
        return totalLoad / 28.0
    }

    /// Calculate acute load (7-day rolling average) as of `referenceDate`.
    /// Window is `[referenceDate - 7 days, referenceDate]` and the daily average
    /// divides by 7 regardless of how many workouts actually fall in the window.
    private func calculateAcuteLoad(workouts: [WorkoutData], ftpSnapshots: [StoredFTPSnapshot], referenceDate: Date) -> Double {
        let calendar = Calendar.current

        guard let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: referenceDate) else {
            return 0
        }

        let recentWorkouts = workouts.filter { $0.startDate >= sevenDaysAgo && $0.startDate <= referenceDate }

        guard !recentWorkouts.isEmpty else { return 0 }

        let totalLoad = recentWorkouts.reduce(0.0) { sum, workout in
            sum + calculateWorkoutLoad(workout, ftpSnapshots: ftpSnapshots)
        }

        // Daily average over 7 days
        return totalLoad / 7.0
    }

    /// Zone weights: exponential scaling so Z5/Z6 cost reflects actual physiological demand.
    /// A 2hr ride with 30% Z5/Z6 + 60% Z1 scores ~3x higher than NP alone would suggest.
    static let zoneWeights: [Double] = [0.5, 1.0, 2.0, 3.5, 5.5, 8.0, 10.0]

    /// Calculate training load for a single workout.
    /// Priority: zone-weighted (power stream) > NP-based TSS > duration × sport multiplier.
    func calculateWorkoutLoad(_ workout: WorkoutData, ftpSnapshots: [StoredFTPSnapshot]) -> Double {
        let durationHours = workout.duration / 3600.0

        // PATH 1: Zone distribution available (most accurate — uses actual time at each intensity)
        if let zoneSecs = workout.powerZoneSeconds, workout.workoutType == .cycling {
            let load = zip(zoneSecs, PredictiveReadinessService.zoneWeights).reduce(0.0) { sum, pair in
                sum + (pair.0 / 3600.0) * pair.1
            }
            #if DEBUG
            let total = zoneSecs.reduce(0, +)
            let pcts = zoneSecs.map { String(format: "%.0f%%", total > 0 ? $0/total*100 : 0) }
            print("⚡️ Zone load: \(workout.title ?? "Ride") Z1=\(pcts[0]) Z2=\(pcts[1]) Z3=\(pcts[2]) Z4=\(pcts[3]) Z5=\(pcts[4]) Z6=\(pcts[5]) Z7=\(pcts[6]) → load=\(String(format: "%.2f", load))")
            #endif
            return load
        }

        // PATH 2: NP or avg watts available (better than duration but misses interval structure)
        if let np = workout.normalizedPower ?? workout.averagePower, np > 0,
           workout.workoutType == .cycling {
            let effectiveFTP = ftpSnapshots.isEmpty
                ? PredictiveReadinessService.resolvedFTP()
                : StoredFTPSnapshot.resolved(for: workout.startDate, snapshots: ftpSnapshots)
            let intensityFactor = np / effectiveFTP
            let tss = intensityFactor * intensityFactor * durationHours
            let powerLabel = workout.normalizedPower != nil ? "NP" : "avg"
            #if DEBUG
            print("⚡️ Power load: \(workout.title ?? "Ride") \(powerLabel)=\(Int(np))W FTP=\(Int(effectiveFTP))W IF=\(String(format: "%.2f", intensityFactor)) TSS=\(String(format: "%.2f", tss)) [no stream yet]")
            #endif
            return tss
        }

        // PATH 3: No power data — duration × sport multiplier
        let multiplier = sportMultiplier(for: workout.workoutType)
        return durationHours * multiplier
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

