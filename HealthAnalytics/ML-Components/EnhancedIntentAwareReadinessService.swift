//
//  EnhancedIntentAwareReadinessService.swift
//  HealthAnalytics
//
//  Intent-aware readiness with full statistical rigor
//  Adds confidence intervals to ACWR and validates sample sizes
//

import Foundation
import SwiftData
import HealthKit

struct EnhancedIntentAwareReadinessService {
    
    // MARK: - Enhanced Assessment with Statistical Rigor
    
    struct EnhancedReadinessAssessment {
        let acwr: StatisticalResult
        let chronicLoad: Double
        let acuteLoad: Double
        let trend: Trend
        
        // Intent-specific insights with confidence
        let performanceReadiness: [ActivityIntent: ReadinessWithConfidence]
        let recommendedIntents: [ActivityIntent]
        let shouldAvoidIntents: [ActivityIntent]
        
        // NEW: Statistical metadata
        let sampleValidation: SampleSizeValidator.ValidationResult
        let dataQuality: DataQuality
        
        enum Trend {
            case building
            case optimal
            case detraining
        }
        
        struct ReadinessWithConfidence {
            let level: ReadinessLevel
            let confidence: StatisticalResult.ConfidenceLevel
            let sampleSize: Int
            
            enum ReadinessLevel {
                case excellent, good, fair, poor
                
                var emoji: String {
                    switch self {
                    case .excellent: return "🟢"
                    case .good: return "🟡"
                    case .fair: return "🟠"
                    case .poor: return "🔴"
                    }
                }
                
                var priority: Int {
                    switch self {
                    case .excellent: return 4
                    case .good: return 3
                    case .fair: return 2
                    case .poor: return 1
                    }
                }
            }
        }
        
        struct DataQuality {
            let hasAdequateSleep: Bool
            let hasAdequateHRV: Bool
            let hasAdequateWorkouts: Bool
            let overallQuality: Quality
            
            enum Quality {
                case excellent  // All metrics well-populated
                case good       // Most metrics present
                case fair       // Some gaps
                case poor       // Significant gaps
                
                var description: String {
                    switch self {
                    case .excellent: return "High-quality data (30+ days each metric)"
                    case .good: return "Good data quality (15-30 days)"
                    case .fair: return "Fair data (7-15 days, use caution)"
                    case .poor: return "Limited data (<7 days, low confidence)"
                    }
                }
            }
        }
    }
    
    /// Calculate readiness with full statistical validation
    func calculateEnhancedReadiness(
        workouts: [StoredWorkout],
        labels: [StoredIntentLabel],
        sleep: [HealthDataPoint],
        hrv: [HealthDataPoint]
    ) -> EnhancedReadinessAssessment {
        
        // Build intent lookup
        let intentLookup = Dictionary(uniqueKeysWithValues: labels.map { ($0.workoutId, $0.intent) })
        
        // Filter performance workouts
        let performanceIntents: [ActivityIntent] = [.race, .tempo, .intervals, .long]
        let performanceWorkouts = workouts.filter { workout in
            if let intent = intentLookup[workout.id] {
                return performanceIntents.contains(intent)
            }
            return false
        }
        
        // Calculate loads with raw data for statistical analysis
        let (chronicLoad, chronicWorkouts) = calculateChronicLoadWithData(workouts: performanceWorkouts)
        let (acuteLoad, acuteWorkouts) = calculateAcuteLoadWithData(workouts: performanceWorkouts)
        
        // Calculate ACWR with confidence interval
        let acwrResult: StatisticalResult
        if let ci = StatisticalValidator.acwrConfidenceInterval(
            acuteWorkouts: acuteWorkouts,
            chronicWorkouts: chronicWorkouts
        ) {
            let confidence = determineConfidence(sampleSize: performanceWorkouts.count)
            acwrResult = StatisticalResult(
                value: ci.acwr,
                confidenceInterval: (lower: ci.lower, upper: ci.upper),
                sampleSize: performanceWorkouts.count,
                confidence: confidence
            )
        } else {
            let simpleACWR = chronicLoad > 0 ? acuteLoad / chronicLoad : 1.0
            let confidence = determineConfidence(sampleSize: performanceWorkouts.count)
            acwrResult = StatisticalResult(
                value: simpleACWR,
                confidenceInterval: nil,
                sampleSize: performanceWorkouts.count,
                confidence: confidence
            )
        }
        
        // Validate sample sizes
        let sampleValidation = SampleSizeValidator.validate(
            sampleSize: performanceWorkouts.count,
            analysisType: .intentClassification
        )
        
        // Assess data quality
        let dataQuality = assessDataQuality(
            sleep: sleep,
            hrv: hrv,
            workouts: performanceWorkouts
        )
        
        // Determine trend
        let trend: EnhancedReadinessAssessment.Trend
        if acwrResult.value > 1.3 {
            trend = .building
        } else if acwrResult.value < 0.8 {
            trend = .detraining
        } else {
            trend = .optimal
        }
        
        // Calculate intent-specific readiness with confidence
        let intentWorkouts = Dictionary(grouping: workouts) { workout in
            intentLookup[workout.id] ?? .other
        }
        
        let performanceReadiness = calculateIntentReadinessWithConfidence(
            acwr: acwrResult.value,
            intentWorkouts: intentWorkouts,
            sleep: sleep,
            hrv: hrv,
            labels: labels
        )
        
        // Recommend/avoid with statistical validation
        let recommended = recommendIntents(readiness: performanceReadiness)
        let shouldAvoid = avoidIntents(readiness: performanceReadiness)
        
        return EnhancedReadinessAssessment(
            acwr: acwrResult,
            chronicLoad: chronicLoad,
            acuteLoad: acuteLoad,
            trend: trend,
            performanceReadiness: performanceReadiness,
            recommendedIntents: recommended,
            shouldAvoidIntents: shouldAvoid,
            sampleValidation: sampleValidation,
            dataQuality: dataQuality
        )
    }
    
    // MARK: - Intent Readiness with Confidence
    
    private func calculateIntentReadinessWithConfidence(
        acwr: Double,
        intentWorkouts: [ActivityIntent: [StoredWorkout]],
        sleep: [HealthDataPoint],
        hrv: [HealthDataPoint],
        labels: [StoredIntentLabel]
    ) -> [ActivityIntent: EnhancedReadinessAssessment.ReadinessWithConfidence] {
        
        var readiness: [ActivityIntent: EnhancedReadinessAssessment.ReadinessWithConfidence] = [:]
        
        // Recovery metrics
        let recentSleep = sleep.suffix(3)
        let recentHRV = hrv.suffix(7)
        
        let avgSleep = recentSleep.isEmpty ? 7.0 : recentSleep.map { $0.value }.reduce(0, +) / Double(recentSleep.count)
        let avgHRV = recentHRV.isEmpty ? 50.0 : recentHRV.map { $0.value }.reduce(0, +) / Double(recentHRV.count)
        
        let daysSinceHardEffort = calculateDaysSinceHardEffort(intentWorkouts: intentWorkouts)
        
        // Calculate for each intent with sample size tracking
        for intent in ActivityIntent.allCases {
            let intentSampleSize = labels.filter { $0.intent == intent }.count
            let confidence = determineConfidence(sampleSize: intentSampleSize)
            
            let level = calculateReadinessLevel(
                intent: intent,
                acwr: acwr,
                avgSleep: avgSleep,
                avgHRV: avgHRV,
                daysSinceHardEffort: daysSinceHardEffort
            )
            
            readiness[intent] = EnhancedReadinessAssessment.ReadinessWithConfidence(
                level: level,
                confidence: confidence,
                sampleSize: intentSampleSize
            )
        }
        
        return readiness
    }
    
    private func calculateReadinessLevel(
        intent: ActivityIntent,
        acwr: Double,
        avgSleep: Double,
        avgHRV: Double,
        daysSinceHardEffort: Int
    ) -> EnhancedReadinessAssessment.ReadinessWithConfidence.ReadinessLevel {
        
        switch intent {
        case .race:
            if acwr <= 1.2 && avgSleep >= 7.5 && avgHRV >= 50 && daysSinceHardEffort >= 2 {
                return .excellent
            } else if acwr <= 1.4 && avgSleep >= 7.0 {
                return .good
            } else if acwr <= 1.5 {
                return .fair
            } else {
                return .poor
            }
            
        case .tempo:
            if acwr <= 1.3 && avgSleep >= 7.0 {
                return .excellent
            } else if acwr <= 1.5 {
                return .good
            } else {
                return .fair
            }
            
        case .intervals:
            if acwr <= 1.2 && avgSleep >= 7.0 && daysSinceHardEffort >= 1 {
                return .excellent
            } else if acwr <= 1.4 && avgSleep >= 6.5 {
                return .good
            } else if acwr <= 1.5 {
                return .fair
            } else {
                return .poor
            }
            
        case .easy:
            if acwr <= 1.6 {
                return .excellent
            } else if acwr <= 1.8 {
                return .good
            } else {
                return .fair
            }
            
        case .long:
            if acwr >= 0.9 && acwr <= 1.3 && avgSleep >= 7.0 {
                return .excellent
            } else if acwr >= 0.8 && acwr <= 1.4 {
                return .good
            } else {
                return .fair
            }
            
        case .strength:
            if daysSinceHardEffort >= 1 && acwr <= 1.4 {
                return .excellent
            } else if acwr <= 1.5 {
                return .good
            } else {
                return .fair
            }
            
        case .casualWalk:
            return .excellent
            
        case .other:
            return acwr <= 1.4 ? .good : .fair
        }
    }
    
    // MARK: - Helper Functions
    
    private func calculateChronicLoadWithData(workouts: [StoredWorkout]) -> (load: Double, data: [Double]) {
        let calendar = Calendar.current
        let now = Date()
        
        guard let twentyEightDaysAgo = calendar.date(byAdding: .day, value: -28, to: now) else {
            return (0, [])
        }
        
        let recentWorkouts = workouts.filter { $0.startDate >= twentyEightDaysAgo }
        
        guard !recentWorkouts.isEmpty else { return (0, []) }
        
        let dailyLoads = recentWorkouts.map { calculateWorkoutLoad($0) }
        let totalLoad = dailyLoads.reduce(0, +)
        
        return (totalLoad / 28.0, dailyLoads)
    }
    
    private func calculateAcuteLoadWithData(workouts: [StoredWorkout]) -> (load: Double, data: [Double]) {
        let calendar = Calendar.current
        let now = Date()
        
        guard let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: now) else {
            return (0, [])
        }
        
        let recentWorkouts = workouts.filter { $0.startDate >= sevenDaysAgo }
        
        guard !recentWorkouts.isEmpty else { return (0, []) }
        
        let dailyLoads = recentWorkouts.map { calculateWorkoutLoad($0) }
        let totalLoad = dailyLoads.reduce(0, +)
        
        return (totalLoad / 7.0, dailyLoads)
    }
    
    private func calculateWorkoutLoad(_ workout: StoredWorkout) -> Double {
        let durationHours = workout.duration / 3600.0
        let multiplier = sportMultiplier(for: workout.workoutType)
        return durationHours * multiplier
    }
    
    private func sportMultiplier(for type: HKWorkoutActivityType) -> Double {
        switch type {
        case .running: return 1.2
        case .cycling: return 1.0
        case .swimming: return 1.3
        case .functionalStrengthTraining, .traditionalStrengthTraining: return 1.1
        case .walking: return 0.5
        default: return 1.0
        }
    }
    
    private func calculateDaysSinceHardEffort(intentWorkouts: [ActivityIntent: [StoredWorkout]]) -> Int {
        let hardIntents: [ActivityIntent] = [.race, .tempo, .intervals]
        
        var mostRecentHard: Date? = nil
        
        for intent in hardIntents {
            if let workouts = intentWorkouts[intent],
               let recent = workouts.max(by: { $0.startDate < $1.startDate }) {
                if mostRecentHard == nil || recent.startDate > mostRecentHard! {
                    mostRecentHard = recent.startDate
                }
            }
        }
        
        guard let lastHard = mostRecentHard else { return 7 }
        
        let days = Calendar.current.dateComponents([.day], from: lastHard, to: Date()).day ?? 0
        return days
    }
    
    private func recommendIntents(
        readiness: [ActivityIntent: EnhancedReadinessAssessment.ReadinessWithConfidence]
    ) -> [ActivityIntent] {
        
        readiness
            .filter { $0.value.level == .excellent || $0.value.level == .good }
            .filter { $0.value.confidence != .insufficient } // Don't recommend without data
            .sorted { $0.value.level.priority > $1.value.level.priority }
            .map { $0.key }
    }
    
    private func avoidIntents(
        readiness: [ActivityIntent: EnhancedReadinessAssessment.ReadinessWithConfidence]
    ) -> [ActivityIntent] {
        
        readiness
            .filter { $0.value.level == .poor }
            .map { $0.key }
    }
    
    private func assessDataQuality(
        sleep: [HealthDataPoint],
        hrv: [HealthDataPoint],
        workouts: [StoredWorkout]
    ) -> EnhancedReadinessAssessment.DataQuality {
        
        let hasAdequateSleep = sleep.count >= 7
        let hasAdequateHRV = hrv.count >= 7
        let hasAdequateWorkouts = workouts.count >= 5
        
        let quality: EnhancedReadinessAssessment.DataQuality.Quality
        if sleep.count >= 30 && hrv.count >= 30 && workouts.count >= 30 {
            quality = .excellent
        } else if sleep.count >= 15 && hrv.count >= 15 && workouts.count >= 15 {
            quality = .good
        } else if hasAdequateSleep && hasAdequateHRV && hasAdequateWorkouts {
            quality = .fair
        } else {
            quality = .poor
        }
        
        return EnhancedReadinessAssessment.DataQuality(
            hasAdequateSleep: hasAdequateSleep,
            hasAdequateHRV: hasAdequateHRV,
            hasAdequateWorkouts: hasAdequateWorkouts,
            overallQuality: quality
        )
    }
    
    private func determineConfidence(sampleSize: Int) -> StatisticalResult.ConfidenceLevel {
        if sampleSize >= 30 {
            return .high
        } else if sampleSize >= 10 {
            return .medium
        } else if sampleSize >= 5 {
            return .low
        } else {
            return .insufficient
        }
    }
}
