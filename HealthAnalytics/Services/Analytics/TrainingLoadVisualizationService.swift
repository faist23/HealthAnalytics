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
                    case .optimal: return .green
                    case .building: return .orange
                    case .danger: return .red
                    case .detraining: return .blue
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
                    case .warning: return .orange
                    case .danger: return .red
                    case .critical: return .purple
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
        daysBack: Int = 90
    ) -> LoadVisualizationData {
        
        print("📊 Generating training load visualization...")
        
        let calendar = Calendar.current
        let endDate = Date()
        let startDate = calendar.date(byAdding: .day, value: -daysBack, to: endDate)!
        
        // Filter recent workouts
        let recentWorkouts = workouts.filter { $0.startDate >= startDate }
        
        print("   Analyzing \(recentWorkouts.count) workouts over \(daysBack) days")
        
        // 1. Generate time series data (daily ACWR)
        let timeSeriesData = generateTimeSeriesData(
            workouts: workouts,
            startDate: startDate,
            endDate: endDate
        )
        
        // 2. Calculate intent breakdown
        let intentBreakdown = calculateIntentBreakdown(
            workouts: recentWorkouts,
            labels: labels
        )
        
        // 3. Analyze weekly patterns
        let weeklyPattern = analyzeWeeklyPattern(
            workouts: recentWorkouts,
            startDate: startDate
        )
        
        // 4. Identify danger zones
        let dangerZones = identifyDangerZones(timeSeriesData: timeSeriesData)
        
        // 5. Generate summary
        let summary = generateSummary(
            timeSeriesData: timeSeriesData,
            weeklyPattern: weeklyPattern,
            dangerZones: dangerZones
        )
        
        print("   ✅ Visualization data generated")
        print("      Time points: \(timeSeriesData.count)")
        print("      Intent types: \(intentBreakdown.count)")
        print("      Danger zones: \(dangerZones.count)")
        
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
        endDate: Date
    ) -> [LoadVisualizationData.LoadDataPoint] {
        
        let calendar = Calendar.current
        var dataPoints: [LoadVisualizationData.LoadDataPoint] = []
        
        var currentDate = calendar.startOfDay(for: startDate)
        
        // Calculate daily for complete data coverage
        let samplingInterval = 1
        
        while currentDate <= endDate {
            // Calculate loads for this day
            let acuteEnd = currentDate
            let acuteStart = calendar.date(byAdding: .day, value: -7, to: acuteEnd)!
            let chronicStart = calendar.date(byAdding: .day, value: -28, to: acuteEnd)!
            
            let acuteWorkouts = workouts.filter {
                $0.startDate >= acuteStart && $0.startDate < acuteEnd
            }
            
            let chronicWorkouts = workouts.filter {
                $0.startDate >= chronicStart && $0.startDate < acuteEnd
            }
            
            let acuteLoad = calculateLoad(workouts: acuteWorkouts) / 7.0
            let chronicLoad = calculateLoad(workouts: chronicWorkouts) / 28.0
            
            let acwr = chronicLoad > 0 ? acuteLoad / chronicLoad : 1.0
            
            // Determine status
            let status: LoadVisualizationData.LoadDataPoint.LoadStatus
            switch acwr {
            case 0..<0.8:
                status = .detraining
            case 0.8...1.3:
                status = .optimal
            case 1.3...1.5:
                status = .building
            default:
                status = .danger
            }
            
            dataPoints.append(LoadVisualizationData.LoadDataPoint(
                date: currentDate,
                acuteLoad: acuteLoad,
                chronicLoad: chronicLoad,
                acwr: acwr,
                status: status
            ))
            
            currentDate = calendar.date(byAdding: .day, value: samplingInterval, to: currentDate)!
        }
        
        // Always include the most recent day (today) if not already included
        let lastPoint = dataPoints.last?.date ?? startDate
        let today = calendar.startOfDay(for: endDate)
        if !calendar.isDate(lastPoint, inSameDayAs: today) {
            let acuteStart = calendar.date(byAdding: .day, value: -7, to: today)!
            let chronicStart = calendar.date(byAdding: .day, value: -28, to: today)!
            
            let acuteWorkouts = workouts.filter {
                $0.startDate >= acuteStart && $0.startDate < today
            }
            
            let chronicWorkouts = workouts.filter {
                $0.startDate >= chronicStart && $0.startDate < today
            }
            
            let acuteLoad = calculateLoad(workouts: acuteWorkouts) / 7.0
            let chronicLoad = calculateLoad(workouts: chronicWorkouts) / 28.0
            let acwr = chronicLoad > 0 ? acuteLoad / chronicLoad : 1.0
            
            let status: LoadVisualizationData.LoadDataPoint.LoadStatus
            switch acwr {
            case 0..<0.8:
                status = .detraining
            case 0.8...1.3:
                status = .optimal
            case 1.3...1.5:
                status = .building
            default:
                status = .danger
            }
            
            dataPoints.append(LoadVisualizationData.LoadDataPoint(
                date: today,
                acuteLoad: acuteLoad,
                chronicLoad: chronicLoad,
                acwr: acwr,
                status: status
            ))
        }
        
        return dataPoints
    }
    
    // MARK: - Intent Breakdown
    
    private func calculateIntentBreakdown(
        workouts: [WorkoutData],
        labels: [StoredIntentLabel]
    ) -> [LoadVisualizationData.IntentLoadBreakdown] {
        
        // Map workouts to their intents
        var intentLoads: [ActivityIntent: (totalLoad: Double, count: Int, totalIntensity: Double)] = [:]
        
        for workout in workouts {
            // Find matching label
            let workoutId = workout.id.uuidString
            let label = labels.first { $0.workoutId == workoutId }
            let intent = label?.intent ?? .other
            
            let load = calculateWorkoutLoad(workout)
            let intensity = estimateIntensity(workout)
            
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
        startDate: Date
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
            
            let totalLoad = calculateLoad(workouts: weekWorkouts)
            let highIntensity = weekWorkouts.filter { estimateIntensity($0) > 7 }.count
            
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
    
    private func calculateLoad(workouts: [WorkoutData]) -> Double {
        workouts.reduce(0) { $0 + calculateWorkoutLoad($1) }
    }
    
    private func calculateWorkoutLoad(_ workout: WorkoutData) -> Double {
        // Simple TSS approximation based on duration
        let hours = workout.duration / 3600.0
        return hours * 100.0 // Rough TSS estimate
    }
    
    private func estimateIntensity(_ workout: WorkoutData) -> Double {
        // Estimate 1-10 intensity based on duration and type
        let baseDuration = workout.duration / 3600.0
        
        switch workout.workoutType {
        case .running:
            return min(10, 5 + baseDuration * 2)
        case .cycling:
            return min(10, 4 + baseDuration * 1.5)
        case .swimming:
            return min(10, 6 + baseDuration * 2)
        default:
            return 5
        }
    }
}
