//
//  FitnessTrendAnalyzer.swift
//  HealthAnalytics
//
//  Advanced VO2max and cardiorespiratory fitness trend analysis
//  Uses existing HealthKit VO2max data + workout patterns
//

import Foundation
import SwiftUI
import HealthKit

struct FitnessTrendAnalyzer {
    
    // MARK: - Models
    
    struct FitnessAnalysis {
        let currentVO2max: Double?
        let vo2maxTrend: VO2maxTrend
        let fitnessAge: FitnessAge?
        let fitnessBalance: FitnessBalance
        let trainingEffectiveness: TrainingEffectiveness
        let projections: FitnessProjection
        let recommendations: [String]
    }
    
    struct VO2maxTrend {
        let currentValue: Double
        let thirtyDayChange: Double      // ml/kg/min change
        let ninetyDayChange: Double
        let yearOverYearChange: Double?
        let trend: TrendDirection
        let confidence: Confidence
        let recentMeasurements: [VO2maxMeasurement]
        
        enum TrendDirection {
            case improving       // +2% or more
            case stable          // ±2%
            case declining       // -2% or more
            case rapidDecline    // -5% or more (detraining alert)
        }
        
        enum Confidence {
            case high      // 10+ measurements in period
            case medium    // 5-9 measurements
            case low       // 3-4 measurements
            case insufficient  // <3 measurements
        }
    }
    
    struct VO2maxMeasurement: Identifiable {
        let id = UUID()
        let date: Date
        let value: Double
        let source: String  // "Apple Watch", "Manual", etc.
    }
    
    struct FitnessAge {
        let chronologicalAge: Int
        let fitnessAge: Int
        let percentile: Double  // For age/gender
        let classification: Classification
        
        enum Classification {
            case superior    // Top 10%
            case excellent   // 10-25%
            case good        // 25-50%
            case fair        // 50-75%
            case poor        // Bottom 25%
            
            var description: String {
                switch self {
                case .superior: return "Superior"
                case .excellent: return "Excellent"
                case .good: return "Good"
                case .fair: return "Fair"
                case .poor: return "Needs Improvement"
                }
            }
            
            var color: Color {
                switch self {
                case .superior: return .purple
                case .excellent: return .green
                case .good: return .blue
                case .fair: return .orange
                case .poor: return .red
                }
            }
        }
    }
    
    struct FitnessBalance {
        let aerobicFitness: Double      // 0-100 based on VO2max + zone 2 time
        let anaerobicFitness: Double    // 0-100 based on high-intensity capacity
        let balance: BalanceType
        let recommendation: String
        
        enum BalanceType {
            case wellBalanced
            case aerobicDominant
            case anaerobicDominant
            case bothWeak
        }
    }
    
    struct TrainingEffectiveness {
        let score: Double              // 0-100
        let interpretation: String
        let loadToFitnessRatio: Double // How well training translates to fitness
        let optimalLoadRange: ClosedRange<Double>  // TSS/week for this athlete
        let insights: [String]
    }
    
    struct FitnessProjection {
        let projectedVO2maxIn30Days: Double?
        let projectedVO2maxIn90Days: Double?
        let estimatedCeiling: Double    // Genetic potential estimate
        let percentOfCeiling: Double    // Current vs ceiling
        let timeToPlateauEstimate: String?  // "2-3 months" or nil if declining
    }
    
    // MARK: - Main Analysis
    
    func analyzeFitnessTrends(
        vo2maxData: [HealthDataPoint],
        workouts: [WorkoutData],
        hrvData: [HealthDataPoint],
        rhrData: [HealthDataPoint],
        userAge: Int,
        userGender: String = "male"  // "male" or "female"
    ) -> FitnessAnalysis? {
        
        print("🏃 Analyzing Fitness Trends...")
        
        guard !vo2maxData.isEmpty else {
            print("   ⚠️ No VO2max data available")
            return nil
        }
        
        // Convert HealthDataPoint to VO2maxMeasurement
        let measurements = vo2maxData.map { point in
            VO2maxMeasurement(
                date: point.date,
                value: point.value,
                source: "Apple Watch"
            )
        }.sorted { $0.date > $1.date }  // Most recent first
        
        guard let currentVO2max = measurements.first?.value else {
            return nil
        }
        
        // Analyze VO2max trend
        let vo2maxTrend = analyzeVO2maxTrend(measurements: measurements)
        
        // Calculate fitness age
        let fitnessAge = calculateFitnessAge(
            vo2max: currentVO2max,
            chronologicalAge: userAge,
            gender: userGender
        )
        
        // Analyze aerobic vs anaerobic balance
        let fitnessBalance = analyzeFitnessBalance(
            vo2max: currentVO2max,
            workouts: workouts,
            hrvData: hrvData
        )
        
        // Calculate training effectiveness
        let trainingEffectiveness = calculateTrainingEffectiveness(
            vo2maxTrend: vo2maxTrend,
            workouts: workouts,
            measurements: measurements
        )
        
        // Project future fitness
        let projections = projectFitness(
            currentVO2max: currentVO2max,
            trend: vo2maxTrend,
            age: userAge,
            gender: userGender
        )
        
        // Generate recommendations
        let recommendations = generateRecommendations(
            vo2maxTrend: vo2maxTrend,
            fitnessBalance: fitnessBalance,
            effectiveness: trainingEffectiveness,
            projections: projections
        )
        
        print("   ✅ Current VO2max: \(Int(currentVO2max)) ml/kg/min")
        print("   📈 Trend: \(vo2maxTrend.trend)")
        if let fitAge = fitnessAge {
            print("   🎂 Fitness Age: \(fitAge.fitnessAge) (\(fitAge.classification.description))")
        }
        
        return FitnessAnalysis(
            currentVO2max: currentVO2max,
            vo2maxTrend: vo2maxTrend,
            fitnessAge: fitnessAge,
            fitnessBalance: fitnessBalance,
            trainingEffectiveness: trainingEffectiveness,
            projections: projections,
            recommendations: recommendations
        )
    }
    
    // MARK: - VO2max Trend Analysis
    
    private func analyzeVO2maxTrend(measurements: [VO2maxMeasurement]) -> VO2maxTrend {
        let current = measurements.first!.value
        
        // Calculate changes over different periods
        let thirtyDaysAgo = Date().addingTimeInterval(-30 * 24 * 3600)
        let ninetyDaysAgo = Date().addingTimeInterval(-90 * 24 * 3600)
        let oneYearAgo = Date().addingTimeInterval(-365 * 24 * 3600)
        
        let thirtyDayMeasurements = measurements.filter { $0.date >= thirtyDaysAgo }
        let ninetyDayMeasurements = measurements.filter { $0.date >= ninetyDaysAgo }
        let yearMeasurements = measurements.filter { $0.date >= oneYearAgo }
        
        // 30-day change
        let thirtyDayChange: Double
        if let baseline30 = thirtyDayMeasurements.last?.value {
            thirtyDayChange = current - baseline30
        } else {
            thirtyDayChange = 0
        }
        
        // 90-day change
        let ninetyDayChange: Double
        if let baseline90 = ninetyDayMeasurements.last?.value {
            ninetyDayChange = current - baseline90
        } else {
            ninetyDayChange = 0
        }
        
        // Year-over-year change
        let yearOverYearChange: Double?
        if let baselineYear = yearMeasurements.last?.value {
            yearOverYearChange = current - baselineYear
        } else {
            yearOverYearChange = nil
        }
        
        // Determine trend direction (using 90-day as primary)
        let percentChange = (ninetyDayChange / current) * 100
        let trend: VO2maxTrend.TrendDirection
        if percentChange >= 2 {
            trend = .improving
        } else if percentChange <= -5 {
            trend = .rapidDecline
        } else if percentChange <= -2 {
            trend = .declining
        } else {
            trend = .stable
        }
        
        // Determine confidence
        let confidence: VO2maxTrend.Confidence
        if ninetyDayMeasurements.count >= 10 {
            confidence = .high
        } else if ninetyDayMeasurements.count >= 5 {
            confidence = .medium
        } else if ninetyDayMeasurements.count >= 3 {
            confidence = .low
        } else {
            confidence = .insufficient
        }
        
        return VO2maxTrend(
            currentValue: current,
            thirtyDayChange: thirtyDayChange,
            ninetyDayChange: ninetyDayChange,
            yearOverYearChange: yearOverYearChange,
            trend: trend,
            confidence: confidence,
            recentMeasurements: Array(ninetyDayMeasurements.prefix(20))
        )
    }
    
    // MARK: - Fitness Age Calculation
    
    private func calculateFitnessAge(
        vo2max: Double,
        chronologicalAge: Int,
        gender: String
    ) -> FitnessAge? {
        
        // VO2max norms by age and gender (ml/kg/min)
        // Source: ACSM Guidelines, Cooper Institute
        let maleNorms: [(age: Int, superior: Double, excellent: Double, good: Double, fair: Double, poor: Double)] = [
            (25, 56, 51, 45, 39, 35),
            (35, 52, 48, 42, 37, 33),
            (45, 49, 44, 39, 34, 30),
            (55, 45, 41, 36, 31, 27),
            (65, 42, 38, 33, 29, 25)
        ]
        
        let femaleNorms: [(age: Int, superior: Double, excellent: Double, good: Double, fair: Double, poor: Double)] = [
            (25, 49, 44, 38, 33, 29),
            (35, 45, 41, 35, 31, 27),
            (45, 42, 38, 33, 28, 25),
            (55, 38, 34, 30, 25, 22),
            (65, 35, 32, 27, 23, 20)
        ]
        
        let norms = gender.lowercased() == "female" ? femaleNorms : maleNorms
        
        // Find closest age bracket
        let ageIndex = norms.enumerated().min(by: { abs($0.element.age - chronologicalAge) < abs($1.element.age - chronologicalAge) })?.offset ?? 0
        let norm = norms[ageIndex]
        
        // Classify current VO2max
        let classification: FitnessAge.Classification
        let percentile: Double
        
        if vo2max >= norm.superior {
            classification = .superior
            percentile = 95
        } else if vo2max >= norm.excellent {
            classification = .excellent
            percentile = 80
        } else if vo2max >= norm.good {
            classification = .good
            percentile = 60
        } else if vo2max >= norm.fair {
            classification = .fair
            percentile = 40
        } else {
            classification = .poor
            percentile = 20
        }
        
        // Estimate fitness age by finding age bracket where current VO2max would be "good"
        var fitnessAge = chronologicalAge
        for (index, ageNorm) in norms.enumerated() {
            if vo2max >= ageNorm.good {
                fitnessAge = ageNorm.age
                break
            }
        }
        
        return FitnessAge(
            chronologicalAge: chronologicalAge,
            fitnessAge: fitnessAge,
            percentile: percentile,
            classification: classification
        )
    }
    
    // MARK: - Fitness Balance Analysis
    
    private func analyzeFitnessBalance(
        vo2max: Double,
        workouts: [WorkoutData],
        hrvData: [HealthDataPoint]
    ) -> FitnessBalance {
        
        // Aerobic fitness score (0-100) based on VO2max
        let aerobicFitness = min(100, (vo2max / 60.0) * 100)  // 60+ is elite
        
        // Anaerobic fitness based on high-intensity workout frequency
        let last30Days = Date().addingTimeInterval(-30 * 24 * 3600)
        let recentWorkouts = workouts.filter { $0.startDate >= last30Days }
        
        let highIntensityCount = recentWorkouts.filter { workout in
            guard let avgHR = workout.averageHeartRate else {
                return false
            }
            return avgHR > 160  // High intensity proxy
        }.count
        
        let anaerobicFitness = min(100, Double(highIntensityCount) * 10)  // 10+ high-intensity sessions = 100
        
        // Determine balance
        let difference = abs(aerobicFitness - anaerobicFitness)
        let balance: FitnessBalance.BalanceType
        let recommendation: String
        
        if aerobicFitness < 50 && anaerobicFitness < 50 {
            balance = .bothWeak
            recommendation = "Focus on building both aerobic base and high-intensity capacity. Start with more easy volume."
        } else if difference < 20 {
            balance = .wellBalanced
            recommendation = "Excellent balance between aerobic and anaerobic fitness. Maintain current training mix."
        } else if aerobicFitness > anaerobicFitness {
            balance = .aerobicDominant
            recommendation = "Strong aerobic base. Add 1-2 high-intensity sessions weekly to develop anaerobic capacity."
        } else {
            balance = .anaerobicDominant
            recommendation = "Good high-intensity capacity. Build more aerobic base with easy zone 2 volume."
        }
        
        return FitnessBalance(
            aerobicFitness: aerobicFitness,
            anaerobicFitness: anaerobicFitness,
            balance: balance,
            recommendation: recommendation
        )
    }
    
    // MARK: - Training Effectiveness
    
    private func calculateTrainingEffectiveness(
        vo2maxTrend: VO2maxTrend,
        workouts: [WorkoutData],
        measurements: [VO2maxMeasurement]
    ) -> TrainingEffectiveness {
        
        // Calculate training load over same period as VO2max improvement
        let ninetyDaysAgo = Date().addingTimeInterval(-90 * 24 * 3600)
        let recentWorkouts = workouts.filter { $0.startDate >= ninetyDaysAgo }
        
        let totalHours = recentWorkouts.reduce(0.0) { $0 + $1.duration } / 3600.0
        let weeklyHours = totalHours / 13.0  // ~13 weeks in 90 days
        
        // Load to fitness ratio
        let fitnessGain = vo2maxTrend.ninetyDayChange
        let loadToFitnessRatio = weeklyHours > 0 ? fitnessGain / weeklyHours : 0
        
        // Score based on efficiency
        let score: Double
        let interpretation: String
        let insights: [String]
        
        if loadToFitnessRatio > 0.5 {
            score = 90
            interpretation = "Excellent training response"
            insights = ["Training is very effective", "You're responding well to current load"]
        } else if loadToFitnessRatio > 0.2 {
            score = 70
            interpretation = "Good training response"
            insights = ["Training is effective", "Continue current approach"]
        } else if loadToFitnessRatio > 0 {
            score = 50
            interpretation = "Moderate training response"
            insights = ["Fitness improving but slowly", "Consider periodization or intensity variation"]
        } else if fitnessGain == 0 {
            score = 30
            interpretation = "Plateau"
            insights = ["Fitness stable despite training", "May need training stimulus change"]
        } else {
            score = 10
            interpretation = "Poor response or overtraining"
            insights = ["Fitness declining despite training", "Check for overtraining or inadequate recovery"]
        }
        
        // Optimal load range based on current effectiveness
        let optimalLoadRange: ClosedRange<Double>
        if weeklyHours < 3 {
            optimalLoadRange = 3...5
        } else if weeklyHours < 6 {
            optimalLoadRange = 5...8
        } else if weeklyHours < 10 {
            optimalLoadRange = 8...12
        } else {
            optimalLoadRange = 10...15
        }
        
        return TrainingEffectiveness(
            score: score,
            interpretation: interpretation,
            loadToFitnessRatio: loadToFitnessRatio,
            optimalLoadRange: optimalLoadRange,
            insights: insights
        )
    }
    
    // MARK: - Fitness Projections
    
    private func projectFitness(
        currentVO2max: Double,
        trend: VO2maxTrend,
        age: Int,
        gender: String
    ) -> FitnessProjection {
        
        // Estimate genetic ceiling (rough approximation)
        // Elite athletes: 70-85 ml/kg/min (male), 60-75 (female)
        // Ceiling decreases ~1% per year after 30
        let baseCeiling = gender.lowercased() == "female" ? 70.0 : 80.0
        let ageFactor = age > 30 ? pow(0.99, Double(age - 30)) : 1.0
        let estimatedCeiling = baseCeiling * ageFactor
        
        let percentOfCeiling = (currentVO2max / estimatedCeiling) * 100
        
        // Project based on current trend
        let monthlyRate = trend.ninetyDayChange / 3.0
        
        let projectedVO2maxIn30Days: Double?
        let projectedVO2maxIn90Days: Double?
        
        if trend.trend != .rapidDecline && trend.confidence != .insufficient {
            projectedVO2maxIn30Days = currentVO2max + monthlyRate
            projectedVO2maxIn90Days = currentVO2max + (monthlyRate * 3)
        } else {
            projectedVO2maxIn30Days = nil
            projectedVO2maxIn90Days = nil
        }
        
        // Time to plateau estimate
        let timeToPlateauEstimate: String?
        if monthlyRate > 0.1 {
            let remainingGain = estimatedCeiling * 0.95 - currentVO2max  // 95% of ceiling is realistic max
            let monthsToPlateau = remainingGain / monthlyRate
            if monthsToPlateau < 12 {
                timeToPlateauEstimate = "\(Int(monthsToPlateau)) months"
            } else {
                timeToPlateauEstimate = "\(Int(monthsToPlateau / 12)) years"
            }
        } else {
            timeToPlateauEstimate = nil
        }
        
        return FitnessProjection(
            projectedVO2maxIn30Days: projectedVO2maxIn30Days,
            projectedVO2maxIn90Days: projectedVO2maxIn90Days,
            estimatedCeiling: estimatedCeiling,
            percentOfCeiling: percentOfCeiling,
            timeToPlateauEstimate: timeToPlateauEstimate
        )
    }
    
    // MARK: - Recommendations
    
    private func generateRecommendations(
        vo2maxTrend: VO2maxTrend,
        fitnessBalance: FitnessBalance,
        effectiveness: TrainingEffectiveness,
        projections: FitnessProjection
    ) -> [String] {
        
        var recommendations: [String] = []
        
        // Trend-based recommendations
        switch vo2maxTrend.trend {
        case .improving:
            recommendations.append("✅ VO2max improving. Keep current training approach.")
        case .stable:
            recommendations.append("💡 VO2max stable. Consider adding variety or intensity to stimulate adaptation.")
        case .declining:
            recommendations.append("⚠️ VO2max declining. Check recovery, sleep, and training load balance.")
        case .rapidDecline:
            recommendations.append("🚨 Rapid VO2max decline detected. Reduce training load and prioritize recovery.")
        }
        
        // Balance recommendations
        recommendations.append(fitnessBalance.recommendation)
        
        // Effectiveness recommendations
        if effectiveness.score < 50 {
            recommendations.append("Training effectiveness is low. Consider working with a coach or adjusting training structure.")
        }
        
        // Projection recommendations
        if projections.percentOfCeiling > 85 {
            recommendations.append("You're near your genetic ceiling. Focus on maintenance and event-specific fitness.")
        } else if projections.percentOfCeiling < 50 {
            recommendations.append("Significant fitness potential remaining. Consistent training will yield good results.")
        }
        
        return recommendations
    }
}
