//
//  BiologicalAgingService.swift
//  HealthAnalytics
//
//  Calculates the "Aging Alpha"—the gap between chronological and biological age.
//  Uses 10-year historical trends in HRV, RHR, and VO2 Max.
//

import Foundation
import SwiftData
import SwiftUI

class BiologicalAgingService {
    
    struct AgingAssessment {
        let chronologicalAge: Int
        let biologicalAge: Double
        let agingAlpha: Double // Positive = aging slower than average
        let hrvRetained: Double // % of expected HRV for age
        let rhrStability: Double // Trend in RHR over 5+ years
        let yearlyHRVDecline: Double // User's specific decline rate
        let averageHRVDecline: Double = 0.8 // RMSSD decline rate ~0.8ms/year (Malik et al. 1996)
        // Signal pillar inputs for SIGNAL INPUTS UI card
        let currentHRV: Double
        let standardHRVForAge: Double
        let currentRHR: Double
        let standardVO2ForAge: Double
        let currentVO2: Double?         // nil when no Apple Watch VO2 Max data in last 180 days
        let vo2MaxRetained: Double?     // (currentVO2 / standardVO2ForAge) * 100; nil if no data

        var status: AgingStatus {
            if agingAlpha >= 5 { return .excellent }
            if agingAlpha >= 0 { return .good }
            if agingAlpha >= -5 { return .moderate }
            return .accelerated
        }
    }
    
    enum AgingStatus: String {
        case excellent = "Slowing Aging"
        case good = "Optimal Aging"
        case moderate = "Standard Aging"
        case accelerated = "Accelerated Aging"
        
        var color: Color {
            switch self {
            case .excellent:   return Color.accent           // Terracotta — exceptional
            case .good:        return Color.statusOptimal    // Bio-green — good health
            case .moderate:    return Color.statusMonitoring // Amber — monitoring zone
            case .accelerated: return Color.statusWarning    // Ember — requires attention
            }
        }
        
        var icon: String {
            switch self {
            case .excellent: return "sparkles"
            case .good: return "leaf.fill"
            case .moderate: return "person.fill"
            case .accelerated: return "exclamationmark.triangle.fill"
            }
        }
    }
    
    // MARK: - Main Assessment Logic

    internal static let minimumHRVSamples = 30

    func calculateAgingAlpha(modelContext: ModelContext) async -> AgingAssessment? {
        // 1. Get Chronological Age from HealthKit
        guard let chronoAge = HealthKitManager.shared.getUserAge() else {
            #if DEBUG
            print("⚠️ BiologicalAgingService: Could not retrieve age from HealthKit")
            #endif
            return nil
        }
        
        do {
            // 2. Fetch Historical Metrics (Last 10 years)
            let calendar = Calendar.current
            let now = Date()
            let tenYearsAgo = calendar.date(byAdding: .year, value: -10, to: now)!
            
            let descriptor = FetchDescriptor<StoredHealthMetric>(
                predicate: #Predicate { $0.date >= tenYearsAgo },
                sortBy: [SortDescriptor(\.date)]
            )
            
            let metrics = try modelContext.fetch(descriptor)
            
            // 3. Extract HRV and RHR yearly trends
            let hrvData = metrics.filter { $0.type == "HRV" }
            let rhrData = metrics.filter { $0.type == "RHR" }
            
            guard hrvData.count > Self.minimumHRVSamples else { // Need at least a month of data to start
                #if DEBUG
                print("⚠️ BiologicalAgingService: Insufficient historical data")
                #endif
                return nil
            }
            
            // 4. Calculate User's Current Baselines (Last 90 days)
            let ninetyDaysAgo = calendar.date(byAdding: .day, value: -90, to: now)!
            let currentHRV = hrvData.filter { $0.date >= ninetyDaysAgo }.map(\.value).reduce(0, +) / Double(max(1, hrvData.filter { $0.date >= ninetyDaysAgo }.count))
            let currentRHR = rhrData.filter { $0.date >= ninetyDaysAgo }.map(\.value).reduce(0, +) / Double(max(1, rhrData.filter { $0.date >= ninetyDaysAgo }.count))
            
            // 5. Calculate Historical Rate of Change (Decay)
            let yearlyAverages = calculateYearlyAverages(hrvData: hrvData)
            let userDeclineRate = calculateDeclineRate(yearlyAverages: yearlyAverages)
            
            // 6. Compare Current HRV to Population Standard
            // Calibrated for Apple Watch RMSSD output (HealthKit HRV type).
            // Decline rate (~0.8ms/year) derived from Malik et al. 1996 age-stratified norms.
            // Floor 25ms reflects realistic RMSSD lower bound for active older adults.
            // Age 30 → 57ms, age 40 → 49ms, age 50 → 41ms, age 65 → 29ms
            let standardHRVForAge = max(25.0, 65.0 - Double(max(0, chronoAge - 20)) * 0.8)
            
            // Biological Age Calculation (Primary Driver: HRV Efficiency)
            // If current HRV is higher than standard, you are biologically younger.
            let hrvDifference = currentHRV - standardHRVForAge
            let hrvAgeAdjustment = hrvDifference / 2.5 // Less aggressive equivalence
            
            // RHR Adjustment (Lower is better, typically stable RHR is 60)
            // Every 3bpm below 60 is roughly 1 "bonus" biological year
            let rhrAgeAdjustment = (60.0 - currentRHR) / 3.0

            // VO2 Max Pillar (30% weight when available)
            // Apple Watch estimates VO2 from outdoor walking/running — 180-day window avoids
            // cliff for users who run outdoors less than monthly.
            let oneEightyDaysAgo = calendar.date(byAdding: .day, value: -180, to: now)!
            let vo2Data = metrics.filter { $0.type == "VO2max" && $0.date >= oneEightyDaysAgo }
            let currentVO2: Double? = vo2Data.isEmpty ? nil : vo2Data.map(\.value).reduce(0, +) / Double(vo2Data.count)

            // ACSM sex-stratified VO2 Max norms. getUserSex() already authorized via .biologicalSex.
            // Male: Age 20 → 45, Age 65 → 22.5 ml/kg/min
            // Female: Age 20 → 40, Age 65 → 19.5 ml/kg/min (~10% lower, per ACSM)
            let sex = HealthKitManager.shared.getUserSex() ?? "male"
            let baseVO2 = sex == "female" ? 40.0 : 45.0
            let standardVO2ForAge = max(18.0, baseVO2 - Double(max(0, chronoAge - 20)) * 0.5)

            // 1 biological year per 3 ml/kg/min above/below standard
            let vo2AgeAdjustment: Double? = currentVO2.map { ($0 - standardVO2ForAge) / 3.0 }
            let vo2MaxRetained: Double? = currentVO2.map { ($0 / max(standardVO2ForAge, 1)) * 100 }

            // Weighted blend — falls back gracefully if VO2 unavailable
            let totalAdjustment: Double
            if let vo2Adj = vo2AgeAdjustment {
                totalAdjustment = (hrvAgeAdjustment * 0.45) + (rhrAgeAdjustment * 0.25) + (vo2Adj * 0.30)
            } else {
                // VO2 Max not available — redistribute to HRV + RHR
                totalAdjustment = (hrvAgeAdjustment * 0.60) + (rhrAgeAdjustment * 0.40)
            }

            // ±8 years: research-defensible range for lifestyle intervention impact
            let maxAdjustment = 8.0
            let minAdjustment = -8.0

            let clampedAdjustment = max(min(totalAdjustment, maxAdjustment), minAdjustment)

            let biologicalAge = Double(chronoAge) - clampedAdjustment
            let agingAlpha = clampedAdjustment

            return AgingAssessment(
                chronologicalAge: chronoAge,
                biologicalAge: biologicalAge,
                agingAlpha: agingAlpha,
                hrvRetained: (currentHRV / standardHRVForAge) * 100,
                rhrStability: calculateRHRStability(rhrData: rhrData),
                yearlyHRVDecline: userDeclineRate,
                currentHRV: currentHRV,
                standardHRVForAge: standardHRVForAge,
                currentRHR: currentRHR,
                standardVO2ForAge: standardVO2ForAge,
                currentVO2: currentVO2,
                vo2MaxRetained: vo2MaxRetained
            )
            
        } catch {
            #if DEBUG
            print("❌ BiologicalAgingService Error: \(error)")
            #endif
            return nil
        }
    }
    
    // MARK: - Testable Core Algorithm (internal for unit tests)

    /// Pure-math calculation of biological age from raw metric values.
    /// Bypasses HealthKit and SwiftData — suitable for unit testing.
    internal static func computeBiologicalAge(
        chronoAge: Int,
        currentHRV: Double,
        currentRHR: Double,
        currentVO2: Double? = nil,
        sex: String = "male"
    ) -> (biologicalAge: Double, agingAlpha: Double, vo2MaxRetained: Double?) {
        let standardHRVForAge = max(25.0, 65.0 - Double(max(0, chronoAge - 20)) * 0.8)
        let hrvDifference = currentHRV - standardHRVForAge
        let hrvAgeAdjustment = hrvDifference / 2.5
        let rhrAgeAdjustment = (60.0 - currentRHR) / 3.0

        let baseVO2 = sex == "female" ? 40.0 : 45.0
        let standardVO2ForAge = max(18.0, baseVO2 - Double(max(0, chronoAge - 20)) * 0.5)
        let vo2AgeAdjustment: Double? = currentVO2.map { ($0 - standardVO2ForAge) / 3.0 }
        let vo2MaxRetained: Double? = currentVO2.map { ($0 / max(standardVO2ForAge, 1)) * 100 }

        let totalAdjustment: Double
        if let vo2Adj = vo2AgeAdjustment {
            totalAdjustment = (hrvAgeAdjustment * 0.45) + (rhrAgeAdjustment * 0.25) + (vo2Adj * 0.30)
        } else {
            totalAdjustment = (hrvAgeAdjustment * 0.60) + (rhrAgeAdjustment * 0.40)
        }

        let clamped = max(min(totalAdjustment, 8.0), -8.0)
        return (Double(chronoAge) - clamped, clamped, vo2MaxRetained)
    }

    // MARK: - Mathematical Helpers
    
    private func calculateYearlyAverages(hrvData: [StoredHealthMetric]) -> [Int: Double] {
        let calendar = Calendar.current
        var yearlySums: [Int: (sum: Double, count: Int)] = [:]
        
        for metric in hrvData {
            let year = calendar.component(.year, from: metric.date)
            let current = yearlySums[year] ?? (0.0, 0)
            yearlySums[year] = (current.sum + metric.value, current.count + 1)
        }
        
        return yearlySums.mapValues { $0.sum / Double($0.count) }
    }
    
    private func calculateDeclineRate(yearlyAverages: [Int: Double]) -> Double {
        guard yearlyAverages.count >= 2 else { return 0.8 } // Fallback to Malik et al. RMSSD rate
        
        let sortedYears = yearlyAverages.keys.sorted()
        let firstYear = sortedYears.first!
        let lastYear = sortedYears.last!
        
        let firstAvg = yearlyAverages[firstYear]!
        let lastAvg = yearlyAverages[lastYear]!
        
        let totalDrop = firstAvg - lastAvg
        let yearSpan = lastYear - firstYear
        
        guard yearSpan > 0 else { return 0.8 }
        return totalDrop / Double(yearSpan)
    }
    
    private func calculateRHRStability(rhrData: [StoredHealthMetric]) -> Double {
        guard rhrData.count > 365 else { return 0.0 }
        
        let calendar = Calendar.current
        let now = Date()
        let oneYearAgo = calendar.date(byAdding: .year, value: -1, to: now)!
        let fiveYearsAgo = calendar.date(byAdding: .year, value: -5, to: now)!
        
        let recentRHR = rhrData.filter { $0.date >= oneYearAgo }.map(\.value).reduce(0, +) / Double(max(1, rhrData.filter { $0.date >= oneYearAgo }.count))
        let historicalRHR = rhrData.filter { $0.date >= fiveYearsAgo && $0.date < oneYearAgo }.map(\.value).reduce(0, +) / Double(max(1, rhrData.filter { $0.date >= fiveYearsAgo && $0.date < oneYearAgo }.count))
        
        return historicalRHR - recentRHR // Positive = RHR is dropping/improving
    }
}
