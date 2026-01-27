//
//  NutritionCorrelationEngine.swift
//  HealthAnalytics
//
//  Created by Craig Faist on 1/26/26.
//


import Foundation

struct NutritionCorrelationEngine {
    
    // MARK: - Protein vs Recovery Analysis
    
    struct ProteinRecoveryInsight {
        let proteinRanges: [ProteinRange]
        let optimalProteinRange: ProteinRange?
        let currentAverage: Double
        let recommendation: String
        let confidence: ConfidenceLevel
        
        enum ConfidenceLevel {
            case high    // 20+ data points
            case medium  // 10-19 data points
            case low     // 5-9 data points
            case insufficient // <5 data points
            
            var description: String {
                switch self {
                case .high: return "High confidence"
                case .medium: return "Medium confidence"
                case .low: return "Low confidence"
                case .insufficient: return "More data needed"
                }
            }
        }
        
        struct ProteinRange {
            let range: String
            let minProtein: Double
            let maxProtein: Double
            let avgHRV: Double?
            let avgRHR: Double?
            let sampleSize: Int
            
            var recoveryScore: Double? {
                // Combine HRV (higher is better) and RHR (lower is better) into single score
                guard let hrv = avgHRV, let rhr = avgRHR else { return nil }
                
                // Normalize: HRV contribution + inverse RHR contribution
                // This is a simple scoring - higher HRV and lower RHR = better recovery
                return hrv - (rhr * 0.5) // Weight RHR less heavily
            }
        }
    }
    
    /// Analyzes correlation between protein intake and recovery metrics
    func analyzeProteinVsRecovery(
        nutritionData: [DailyNutrition],
        restingHRData: [HealthDataPoint],
        hrvData: [HealthDataPoint]
    ) -> ProteinRecoveryInsight? {
        
        // Need at least 10 days with complete data
        let completeNutritionDays = nutritionData.filter { $0.isComplete }
        guard completeNutritionDays.count >= 10 else {
            print("⚠️ Protein analysis: Need 10+ complete nutrition days (have \(completeNutritionDays.count))")
            return ProteinRecoveryInsight(
                proteinRanges: [],
                optimalProteinRange: nil,
                currentAverage: 0,
                recommendation: "Log nutrition for \(10 - completeNutritionDays.count) more days to unlock protein insights.",
                confidence: .insufficient
            )
        }
        
        // Create lookup dictionaries for recovery metrics
        let calendar = Calendar.current
        var rhrByDate: [Date: Double] = [:]
        var hrvByDate: [Date: Double] = [:]
        
        for rhr in restingHRData {
            let day = calendar.startOfDay(for: rhr.date)
            rhrByDate[day] = rhr.value
        }
        
        for hrv in hrvData {
            let day = calendar.startOfDay(for: hrv.date)
            hrvByDate[day] = hrv.value
        }
        
        // Group protein intake into ranges and correlate with NEXT DAY recovery
        var proteinGroups: [String: (protein: [Double], rhr: [Double], hrv: [Double])] = [
            "<100g": ([], [], []),
            "100-130g": ([], [], []),
            "130-160g": ([], [], []),
            ">160g": ([], [], [])
        ]
        
        for nutrition in completeNutritionDays {
            let protein = nutrition.totalProtein
            let nutritionDay = calendar.startOfDay(for: nutrition.date)
            
            // Get NEXT day's recovery metrics
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: nutritionDay),
                  let nextDayRHR = rhrByDate[nextDay],
                  let nextDayHRV = hrvByDate[nextDay] else {
                continue
            }
            
            // Categorize protein intake
            let group: String
            if protein < 100 {
                group = "<100g"
            } else if protein < 130 {
                group = "100-130g"
            } else if protein < 160 {
                group = "130-160g"
            } else {
                group = ">160g"
            }
            
            proteinGroups[group]?.protein.append(protein)
            proteinGroups[group]?.rhr.append(nextDayRHR)
            proteinGroups[group]?.hrv.append(nextDayHRV)
        }
        
        // Calculate averages for each group
        var ranges: [ProteinRecoveryInsight.ProteinRange] = []
        
        for (groupName, data) in proteinGroups.sorted(by: { $0.key < $1.key }) {
            guard !data.protein.isEmpty else { continue }
            
            let avgRHR = data.rhr.reduce(0, +) / Double(data.rhr.count)
            let avgHRV = data.hrv.reduce(0, +) / Double(data.hrv.count)
            
            let (minP, maxP): (Double, Double)
            switch groupName {
            case "<100g": (minP, maxP) = (0, 100)
            case "100-130g": (minP, maxP) = (100, 130)
            case "130-160g": (minP, maxP) = (130, 160)
            case ">160g": (minP, maxP) = (160, 300)
            default: continue
            }
            
            ranges.append(ProteinRecoveryInsight.ProteinRange(
                range: groupName,
                minProtein: minP,
                maxProtein: maxP,
                avgHRV: avgHRV,
                avgRHR: avgRHR,
                sampleSize: data.protein.count
            ))
            
            print("📊 Protein Range: \(groupName)")
            print("   Samples: \(data.protein.count)")
            print("   Avg next-day RHR: \(String(format: "%.1f", avgRHR)) bpm")
            print("   Avg next-day HRV: \(String(format: "%.1f", avgHRV)) ms")
        }
        
        // Find optimal range (best recovery score)
        let optimalRange = ranges.max { a, b in
            (a.recoveryScore ?? 0) < (b.recoveryScore ?? 0)
        }
        
        // Current average protein
        let currentAvgProtein = completeNutritionDays.map { $0.totalProtein }.reduce(0, +) / Double(completeNutritionDays.count)
        
        // Determine confidence
        let totalSamples = ranges.reduce(0) { $0 + $1.sampleSize }
        let confidence: ProteinRecoveryInsight.ConfidenceLevel
        if totalSamples >= 20 {
            confidence = .high
        } else if totalSamples >= 10 {
            confidence = .medium
        } else {
            confidence = .low
        }
        
        // Generate recommendation
        let recommendation = generateProteinRecommendation(
            optimalRange: optimalRange,
            currentAverage: currentAvgProtein,
            ranges: ranges
        )
        
        return ProteinRecoveryInsight(
            proteinRanges: ranges,
            optimalProteinRange: optimalRange,
            currentAverage: currentAvgProtein,
            recommendation: recommendation,
            confidence: confidence
        )
    }
    
    // MARK: - Helper Methods
    
    private func generateProteinRecommendation(
        optimalRange: ProteinRecoveryInsight.ProteinRange?,
        currentAverage: Double,
        ranges: [ProteinRecoveryInsight.ProteinRange]
    ) -> String {
        
        guard let optimal = optimalRange else {
            return "Continue tracking to identify your optimal protein intake."
        }
        
        let currentRange = ranges.first { range in
            currentAverage >= range.minProtein && currentAverage < range.maxProtein
        }
        
        if let current = currentRange, current.range == optimal.range {
            return "Your current protein intake (\(Int(currentAverage))g) is in the optimal range for recovery. Next-day HRV averages \(String(format: "%.1f", optimal.avgHRV ?? 0))ms in this range."
        } else {
            let direction = currentAverage < optimal.minProtein ? "increase" : "decrease"
            let target = "\(Int(optimal.minProtein))-\(Int(optimal.maxProtein))g"
            
            if let optimalHRV = optimal.avgHRV, let currentHRV = currentRange?.avgHRV {
                let hrvDiff = optimalHRV - currentHRV
                return "Consider targeting \(target) protein daily. Recovery metrics are \(String(format: "%.1f", abs(hrvDiff)))ms HRV \(hrvDiff > 0 ? "better" : "worse") in that range."
            } else {
                return "Your optimal recovery occurs with \(target) protein daily. Current average: \(Int(currentAverage))g."
            }
        }
    }
}