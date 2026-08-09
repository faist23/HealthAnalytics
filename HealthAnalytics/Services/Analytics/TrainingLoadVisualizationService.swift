//
//  TrainingLoadVisualizationService.swift
//  HealthAnalytics
//
//  Generates comprehensive training load visualizations
//  - ACWR trends over time
//  - Load breakdown by intent
//  - Weekly/monthly patterns
//  - Danger zone warnings
//

import Foundation
import SwiftUI
import HealthKit

struct TrainingLoadVisualizationService {

    /// Single source of truth for per-workout load and ACWR. This service must
    /// never grow its own load math again — a duration-only "hours × 100" TSS
    /// here once made this screen report ACWR 1.80 while the Load tab said 1.33.
    private let readinessService = PredictiveReadinessService()

    // MARK: - Data Models
    
    struct LoadVisualizationData {
        let timeSeriesData: [LoadDataPoint]
        let intentBreakdown: [IntentLoadBreakdown]
        let weeklyPattern: WeeklyLoadPattern
        let dangerZones: [DangerZone]
        let summary: LoadSummary
        
        struct LoadDataPoint: Identifiable {
            let id = UUID()
            let date: Date
            let acuteLoad: Double
            let chronicLoad: Double
            let acwr: Double
            let status: LoadStatus
            
            enum LoadStatus {
                case optimal      // 0.8-1.3
                case building     // 1.3-1.5
                case danger       // >1.5
                case detraining   // <0.8
                
                var color: Color {
                    switch self {
                    case .optimal: return Color.statusOptimal
                    case .building: return Color.statusMonitoring
                    case .danger: return Color.statusAllOut
                    case .detraining: return Color.statusRest
                    }
                }
            }
        }
        
        struct IntentLoadBreakdown: Identifiable {
            let id = UUID()
            let intent: ActivityIntent
            let totalLoad: Double
            let percentage: Double
            let avgIntensity: Double
            let workoutCount: Int
        }
        
        struct WeeklyLoadPattern {
            let weeks: [WeekData]
            let averageWeeklyLoad: Double
            let trend: Trend
            
            struct WeekData: Identifiable {
                let id = UUID()
                let weekStart: Date
                let totalLoad: Double
                let workoutCount: Int
                let highIntensityCount: Int
            }
            
            enum Trend {
                case increasing
                case stable
                case decreasing
            }
        }
        
        struct DangerZone: Identifiable {
            let id = UUID()
            let startDate: Date
            let endDate: Date
            let peakACWR: Double
            let reason: String
            let severity: Severity
            
            enum Severity {
                case warning   // ACWR 1.3-1.5
                case danger    // ACWR 1.5-2.0
                case critical  // ACWR >2.0
                
                var color: Color {
                    switch self {
                    case .warning: return Color.statusMonitoring
                    case .danger: return Color.statusWarning
                    case .critical: return Color.statusAllOut
                    }
                }
            }
        }
        
        struct LoadSummary {
            let currentACWR: Double
            let currentStatus: String
            let daysInCurrentStatus: Int
            let weeksSinceLastDanger: Int?
            let projectedLoadNextWeek: Double
            let recommendation: String
        }
    }
    
    // MARK: - Generate Visualization Data
    
    func generateLoadVisualization(
        workouts: [WorkoutData],
        labels: [StoredIntentLabel],
        ftpSnapshots: [StoredFTPSnapshot] = [],
        daysBack: Int = 90
    ) -> LoadVisualizationData {
        
        #if DEBUG
        print("📊 Generating training load visualization...")
        #endif

        let calendar = Calendar.current
        let endDate = Date()
        let startDate = calendar.date(byAdding: .day, value: -daysBack, to: endDate)!

        // Filter recent workouts
        let recentWorkouts = workouts.filter { $0.startDate >= startDate }

        #if DEBUG
        print("   Analyzing \(recentWorkouts.count) workouts over \(daysBack) days")
        #endif
        
        // 1. Generate time series data (daily ACWR)
        let timeSeriesData = generateTimeSeriesData(
            workouts: workouts,
            startDate: startDate,
            endDate: endDate,
            ftpSnapshots: ftpSnapshots
        )

        // 2. Calculate intent breakdown
        let intentBreakdown = calculateIntentBreakdown(
            workouts: recentWorkouts,
            labels: labels,
            ftpSnapshots: ftpSnapshots
        )

        // 3. Analyze weekly patterns
        let weeklyPattern = analyzeWeeklyPattern(
            workouts: recentWorkouts,
            startDate: startDate,
            ftpSnapshots: ftpSnapshots
        )
        
        // 4. Identify danger zones
        let dangerZones = identifyDangerZones(timeSeriesData: timeSeriesData)
        
        // 5. Generate summary
        let summary = generateSummary(
            timeSeriesData: timeSeriesData,
            weeklyPattern: weeklyPattern,
            dangerZones: dangerZones
        )
        
        #if DEBUG
        print("   ✅ Visualization data generated")
        print("      Time points: \(timeSeriesData.count)")
        print("      Intent types: \(intentBreakdown.count)")
        print("      Danger zones: \(dangerZones.count)")
        #endif
        
        return LoadVisualizationData(
            timeSeriesData: timeSeriesData,
            intentBreakdown: intentBreakdown,
            weeklyPattern: weeklyPattern,
            dangerZones: dangerZones,
            summary: summary
        )
    }
    
    // MARK: - Time Series Generation
    
    private func generateTimeSeriesData(
        workouts: [WorkoutData],
        startDate: Date,
        endDate: Date,
        ftpSnapshots: [StoredFTPSnapshot]
    ) -> [LoadVisualizationData.LoadDataPoint] {

        let calendar = Calendar.current
        var dataPoints: [LoadVisualizationData.LoadDataPoint] = []

        // Cold-start guard: ACWR is undefined until a full 28-day chronic window
        // is covered by data. Without this, the first days of the series compare
        // acute and chronic windows containing the SAME few workouts, which
        // yields (T/7)/(T/28) = exactly 4.0 — a fabricated spike, not real load.
        guard let earliestWorkout = workouts.map(\.startDate).min() else { return [] }
        let earliestValidDay = calendar.date(byAdding: .day, value: 28, to: calendar.startOfDay(for: earliestWorkout))!

        var currentDate = max(calendar.startOfDay(for: startDate), earliestValidDay)

        // One ACWR in the whole app: every point delegates to
        // PredictiveReadinessService.calculateReadiness (zone-weighted / NP-TSS /
        // duration×sport-multiplier load, windows [ref-7, ref] / [ref-28, ref]).
        // Window ends come from the shared `windowEnd` rule — each day closes at
        // the following midnight (today closes at `endDate`, i.e. now), so a day's
        // point includes that day's own training and the final point is identical
        // to the assessment shown on the Load tab.
        while currentDate <= endDate {
            let assessment = readinessService.calculateReadiness(
                stravaActivities: [],
                healthKitWorkouts: workouts,
                ftpSnapshots: ftpSnapshots,
                referenceDate: PredictiveReadinessService.windowEnd(for: currentDate, now: endDate)
            )

            dataPoints.append(LoadVisualizationData.LoadDataPoint(
                date: currentDate,
                acuteLoad: assessment.acuteLoad,
                chronicLoad: assessment.chronicLoad,
                acwr: assessment.acwr,
                status: loadStatus(for: assessment.acwr)
            ))

            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        }

        return dataPoints
    }

    /// Same thresholds as PredictiveReadinessService.ReadinessAssessment.Trend —
    /// the two enums must never disagree about what a given ACWR is called.
    private func loadStatus(for acwr: Double) -> LoadVisualizationData.LoadDataPoint.LoadStatus {
        switch acwr {
        case ..<0.8: return .detraining
        case 0.8...1.3: return .optimal
        case 1.3...1.5: return .building
        default: return .danger
        }
    }
    
    // MARK: - Intent Breakdown
    
    private func calculateIntentBreakdown(
        workouts: [WorkoutData],
        labels: [StoredIntentLabel],
        ftpSnapshots: [StoredFTPSnapshot]
    ) -> [LoadVisualizationData.IntentLoadBreakdown] {
        
        // Map workouts to their intents
        var intentLoads: [ActivityIntent: (totalLoad: Double, count: Int, totalIntensity: Double)] = [:]
        
        // Labels are keyed by StoredWorkout.id, which for Strava workouts is the numeric
        // activity ID — NOT a UUID. WorkoutData.id is a random UUID for those (the uuidString
        // cast fails), so joining on id.uuidString silently dropped every Strava workout into
        // .other. The real join key lives in originalId (== StoredWorkout.id).
        let labelByWorkoutId = Dictionary(labels.map { ($0.workoutId, $0) }) { first, _ in first }

        for workout in workouts {
            let workoutId = workout.originalId ?? workout.id.uuidString
            let intent = labelByWorkoutId[workoutId]?.intent ?? .other

            let load = readinessService.calculateWorkoutLoad(workout, ftpSnapshots: ftpSnapshots)
            let intensity = estimateIntensity(workout, ftpSnapshots: ftpSnapshots)
            
            let current = intentLoads[intent] ?? (0, 0, 0)
            intentLoads[intent] = (
                current.totalLoad + load,
                current.count + 1,
                current.totalIntensity + intensity
            )
        }
        
        let totalLoad = intentLoads.values.reduce(0) { $0 + $1.totalLoad }
        
        return intentLoads.map { intent, data in
            LoadVisualizationData.IntentLoadBreakdown(
                intent: intent,
                totalLoad: data.totalLoad,
                percentage: totalLoad > 0 ? (data.totalLoad / totalLoad) * 100 : 0,
                avgIntensity: data.count > 0 ? data.totalIntensity / Double(data.count) : 0,
                workoutCount: data.count
            )
        }.sorted { $0.totalLoad > $1.totalLoad }
    }
    
    // MARK: - Weekly Pattern Analysis
    
    private func analyzeWeeklyPattern(
        workouts: [WorkoutData],
        startDate: Date,
        ftpSnapshots: [StoredFTPSnapshot]
    ) -> LoadVisualizationData.WeeklyLoadPattern {
        
        let calendar = Calendar.current
        var weeks: [LoadVisualizationData.WeeklyLoadPattern.WeekData] = []
        
        var weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: startDate))!
        let endDate = Date()
        
        while weekStart < endDate {
            let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart)!
            
            let weekWorkouts = workouts.filter {
                $0.startDate >= weekStart && $0.startDate < weekEnd
            }
            
            let totalLoad = calculateLoad(workouts: weekWorkouts, ftpSnapshots: ftpSnapshots)
            let highIntensity = weekWorkouts.filter { estimateIntensity($0, ftpSnapshots: ftpSnapshots) > 7 }.count
            
            weeks.append(LoadVisualizationData.WeeklyLoadPattern.WeekData(
                weekStart: weekStart,
                totalLoad: totalLoad,
                workoutCount: weekWorkouts.count,
                highIntensityCount: highIntensity
            ))
            
            weekStart = weekEnd
        }
        
        let avgLoad = weeks.isEmpty ? 0 : weeks.reduce(0) { $0 + $1.totalLoad } / Double(weeks.count)
        
        // Determine trend
        let trend: LoadVisualizationData.WeeklyLoadPattern.Trend
        if weeks.count >= 4 {
            let recent = weeks.suffix(2).reduce(0) { $0 + $1.totalLoad } / 2.0
            let previous = weeks.prefix(weeks.count - 2).suffix(2).reduce(0) { $0 + $1.totalLoad } / 2.0
            
            if recent > previous * 1.1 {
                trend = .increasing
            } else if recent < previous * 0.9 {
                trend = .decreasing
            } else {
                trend = .stable
            }
        } else {
            trend = .stable
        }
        
        return LoadVisualizationData.WeeklyLoadPattern(
            weeks: weeks,
            averageWeeklyLoad: avgLoad,
            trend: trend
        )
    }
    
    // MARK: - Danger Zone Detection
    
    private func identifyDangerZones(
        timeSeriesData: [LoadVisualizationData.LoadDataPoint]
    ) -> [LoadVisualizationData.DangerZone] {
        
        var zones: [LoadVisualizationData.DangerZone] = []
        var currentZoneStart: Date?
        var currentZonePeak: Double = 0
        
        for point in timeSeriesData {
            if point.acwr >= 1.3 {
                // In a danger zone
                if currentZoneStart == nil {
                    currentZoneStart = point.date
                    currentZonePeak = point.acwr
                } else {
                    currentZonePeak = max(currentZonePeak, point.acwr)
                }
            } else {
                // Exited danger zone
                if let start = currentZoneStart {
                    let severity: LoadVisualizationData.DangerZone.Severity
                    let reason: String
                    
                    if currentZonePeak >= 2.0 {
                        severity = .critical
                        reason = "Critical overload - high injury risk"
                    } else if currentZonePeak >= 1.5 {
                        severity = .danger
                        reason = "Dangerous spike - consider rest"
                    } else {
                        severity = .warning
                        reason = "Building phase - monitor fatigue"
                    }
                    
                    zones.append(LoadVisualizationData.DangerZone(
                        startDate: start,
                        endDate: point.date,
                        peakACWR: currentZonePeak,
                        reason: reason,
                        severity: severity
                    ))
                    
                    currentZoneStart = nil
                    currentZonePeak = 0
                }
            }
        }
        
        // Close any open zone
        if let start = currentZoneStart, let last = timeSeriesData.last {
            let severity: LoadVisualizationData.DangerZone.Severity
            let reason: String
            
            if currentZonePeak >= 2.0 {
                severity = .critical
                reason = "ONGOING: Critical overload"
            } else if currentZonePeak >= 1.5 {
                severity = .danger
                reason = "ONGOING: High load spike"
            } else {
                severity = .warning
                reason = "ONGOING: Building phase"
            }
            
            zones.append(LoadVisualizationData.DangerZone(
                startDate: start,
                endDate: last.date,
                peakACWR: currentZonePeak,
                reason: reason,
                severity: severity
            ))
        }
        
        return zones
    }
    
    // MARK: - Summary Generation
    
    private func generateSummary(
        timeSeriesData: [LoadVisualizationData.LoadDataPoint],
        weeklyPattern: LoadVisualizationData.WeeklyLoadPattern,
        dangerZones: [LoadVisualizationData.DangerZone]
    ) -> LoadVisualizationData.LoadSummary {
        
        guard let latest = timeSeriesData.last else {
            return LoadVisualizationData.LoadSummary(
                currentACWR: 1.0,
                currentStatus: "Unknown",
                daysInCurrentStatus: 0,
                weeksSinceLastDanger: nil,
                projectedLoadNextWeek: 0,
                recommendation: "Need more data"
            )
        }
        
        // Current status
        let currentStatus: String
        switch latest.status {
        case .optimal: currentStatus = "Optimal"
        case .building: currentStatus = "Building"
        case .danger: currentStatus = "Overreaching"
        case .detraining: currentStatus = "Detraining"
        }
        
        // Days in current status
        var daysInStatus = 1
        for point in timeSeriesData.reversed().dropFirst() {
            if point.status == latest.status {
                daysInStatus += 1
            } else {
                break
            }
        }
        
        // Weeks since last danger
        let calendar = Calendar.current
        let lastDangerZone = dangerZones.last
        let weeksSinceDanger: Int?
        if let lastDanger = lastDangerZone {
            weeksSinceDanger = calendar.dateComponents([.weekOfYear], from: lastDanger.endDate, to: Date()).weekOfYear
        } else {
            weeksSinceDanger = nil
        }
        
        // Project next week
        let recentWeeks = weeklyPattern.weeks.suffix(3)
        let avgRecentLoad = recentWeeks.isEmpty ? 0 : recentWeeks.reduce(0) { $0 + $1.totalLoad } / Double(recentWeeks.count)
        let projectedLoad = avgRecentLoad * (weeklyPattern.trend == .increasing ? 1.1 : weeklyPattern.trend == .decreasing ? 0.9 : 1.0)
        
        // Recommendation
        let recommendation: String
        switch latest.status {
        case .optimal:
            recommendation = "Well balanced. Safe to maintain or gradually increase."
        case .building:
            recommendation = "Load is building. Monitor fatigue and consider recovery week soon."
        case .danger:
            recommendation = "High injury risk. Reduce load immediately or take rest days."
        case .detraining:
            recommendation = "Load is low. Consider ramping up training volume."
        }
        
        return LoadVisualizationData.LoadSummary(
            currentACWR: latest.acwr,
            currentStatus: currentStatus,
            daysInCurrentStatus: daysInStatus,
            weeksSinceLastDanger: weeksSinceDanger,
            projectedLoadNextWeek: projectedLoad,
            recommendation: recommendation
        )
    }
    
    // MARK: - Helper Functions
    
    private func calculateLoad(workouts: [WorkoutData], ftpSnapshots: [StoredFTPSnapshot]) -> Double {
        workouts.reduce(0) { $0 + readinessService.calculateWorkoutLoad($1, ftpSnapshots: ftpSnapshots) }
    }


    /// Estimate a 1–10 effort score from the strongest physiological signal available,
    /// in priority order: power-zone distribution → normalized/avg power vs FTP → HR %max.
    /// Duration is deliberately NOT used — a long recovery spin and a short VO2max set are
    /// different intensities, and the old duration-only heuristic reported both as ~5.5.
    /// True when the workout carries a real physiological signal, so `estimateIntensity`
    /// will return a measured value rather than the neutral 5.0 fallback.
    ///
    /// Callers that COMPARE intensities must gate on this. Averaging a measured window
    /// against a window of 5.0 placeholders manufactures a difference out of missing
    /// data — the same fabrication this file's `estimateIntensity` exists to avoid.
    /// Must stay in lockstep with the fallback chain below.
    func hasIntensitySignal(_ workout: WorkoutData) -> Bool {
        if let zones = workout.powerZoneSeconds, zones.count == 7, zones.reduce(0, +) > 0 { return true }
        if let power = workout.normalizedPower ?? workout.averagePower, power > 0 { return true }
        if let hr = workout.averageHeartRate, hr > 0 { return true }
        return false
    }

    /// Non-private: `TrainingDNAAnalyzer.detectTaperUnderway` reuses this to corroborate
    /// that a volume drop was deliberate. Do not reimplement intensity anywhere else —
    /// duplicated load math is how this project ended up with two disagreeing ACWR
    /// engines (see CLAUDE.md, "One ACWR engine").
    func estimateIntensity(_ workout: WorkoutData, ftpSnapshots: [StoredFTPSnapshot]) -> Double {
        // 1. Power zones (cycling with stream data) — the ground truth for effort structure.
        if let zones = workout.powerZoneSeconds, zones.count == 7 {
            let total = zones.reduce(0, +)
            if total > 0 {
                // Representative intensity factor (fraction of FTP) at the middle of each zone.
                let zoneIF: [Double] = [0.40, 0.65, 0.83, 0.98, 1.13, 1.35, 1.60]
                let weightedIF = zip(zones, zoneIF).reduce(0.0) { $0 + ($1.0 / total) * $1.1 }
                return intensityFromIntensityFactor(weightedIF)
            }
        }

        // 2. Normalized power (or average power) relative to FTP → intensity factor.
        if let power = workout.normalizedPower ?? workout.averagePower, power > 0 {
            let ftp = StoredFTPSnapshot.resolved(for: workout.startDate, snapshots: ftpSnapshots)
            if ftp > 0 {
                return intensityFromIntensityFactor(power / ftp)
            }
        }

        // 3. Heart rate as a fraction of estimated max (same 185 bpm convention as the classifier).
        if let hr = workout.averageHeartRate, hr > 0 {
            return intensityFromHRFraction(hr / 185.0)
        }

        // 4. No physiological signal — return a neutral midpoint rather than a fabricated value.
        return 5.0
    }

    /// Map an intensity factor (fraction of FTP) to 1–10.
    /// Anchors: IF 0.40 (recovery) → 1, IF 1.20 (deep VO2max) → 10.
    private func intensityFromIntensityFactor(_ intensityFactor: Double) -> Double {
        let scaled = 1 + (intensityFactor - 0.40) / 0.80 * 9
        return min(10, max(1, scaled))
    }

    /// Map a heart-rate fraction of max to 1–10.
    /// Anchors: 50% max → 1, 100% max → 10.
    private func intensityFromHRFraction(_ fraction: Double) -> Double {
        let scaled = 1 + (fraction - 0.50) / 0.50 * 9
        return min(10, max(1, scaled))
    }
}
