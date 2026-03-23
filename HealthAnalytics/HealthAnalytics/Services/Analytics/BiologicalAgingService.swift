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
        let averageHRVDecline: Double = 1.5 // Standard human decline (ms/year)
        
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
            case .excellent: return .purple
            case .good: return .green
            case .moderate: return .blue
            case .accelerated: return .orange
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
    
    func calculateAgingAlpha(modelContext: ModelContext) async -> AgingAssessment? {
        // 1. Get Chronological Age from HealthKit
        guard let chronoAge = HealthKitManager.shared.getUserAge() else {
            print("⚠️ BiologicalAgingService: Could not retrieve age from HealthKit")
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
            
            guard hrvData.count > 30 else { // Need at least a month of data to start
                print("⚠️ BiologicalAgingService: Insufficient historical data")
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
            // Model: Standard 25-year-old HRV (SDNN) is roughly 65-70ms. 
            // It drops ~1.5ms per year.
            let standardHRVForAge = 70.0 - (Double(chronoAge - 25) * 1.5)
            
            // Biological Age Calculation (Primary Driver: HRV Efficiency)
            // If current HRV is higher than standard, you are biologically younger.
            let hrvDifference = currentHRV - standardHRVForAge
            let hrvAgeAdjustment = hrvDifference / 1.5 // 1.5ms per year equivalence
            
            // RHR Adjustment (Lower is better, typically stable RHR is 60)
            // Every 2bpm below 60 is roughly 1 "bonus" biological year
            let rhrAgeAdjustment = (60.0 - currentRHR) / 2.0
            
            let biologicalAge = Double(chronoAge) - hrvAgeAdjustment - rhrAgeAdjustment
            let agingAlpha = Double(chronoAge) - biologicalAge
            
            return AgingAssessment(
                chronologicalAge: chronoAge,
                biologicalAge: biologicalAge,
                agingAlpha: agingAlpha,
                hrvRetained: (currentHRV / standardHRVForAge) * 100,
                rhrStability: calculateRHRStability(rhrData: rhrData),
                yearlyHRVDecline: userDeclineRate
            )
            
        } catch {
            print("❌ BiologicalAgingService Error: \(error)")
            return nil
        }
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
        guard yearlyAverages.count >= 2 else { return 1.5 } // Fallback to standard
        
        let sortedYears = yearlyAverages.keys.sorted()
        let firstYear = sortedYears.first!
        let lastYear = sortedYears.last!
        
        let firstAvg = yearlyAverages[firstYear]!
        let lastAvg = yearlyAverages[lastYear]!
        
        let totalDrop = firstAvg - lastAvg
        let yearSpan = lastYear - firstYear
        
        guard yearSpan > 0 else { return 1.5 }
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
