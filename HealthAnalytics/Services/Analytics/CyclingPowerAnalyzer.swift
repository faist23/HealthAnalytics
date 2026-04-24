//
//  CyclingPowerAnalyzer.swift
//  HealthAnalytics
//

import Foundation
import HealthKit

struct CyclingPowerAnalyzer {
    
    struct CompoundScoreAnalysis {
        let absoluteFTP: Double
        let weightKg: Double
        let relativeFTP: Double
        let compoundScore: Double
        let phenotype: String
        let level: String
        let insight: String
        let dataSource: String
        let dataDate: Date
    }
    
    func analyzeCompoundScore(
        workouts: [WorkoutData],
        weightData: [HealthDataPoint]
    ) async -> CompoundScoreAnalysis? {
        
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let recentRides = workouts.filter { $0.workoutType == .cycling && $0.startDate >= thirtyDaysAgo }
        
        var max5MinPower: Double = 0
        var maxPowerDate: Date? = nil
        var sourceName: String = "HealthKit"
        
        // 1. Get 5-Min Max Power across recent rides
        for ride in recentRides {
            let peak: Double?
            if ride.source == .strava, let originalId = ride.originalId, let activityId = Int(originalId) {
                peak = try? await StravaManager.shared.fetchPeak5MinPower(activityId: activityId)
            } else {
                peak = try? await HealthKitManager.shared.fetchPeak5MinPower(startDate: ride.startDate, endDate: ride.endDate)
            }
            
            if let peak = peak, peak > max5MinPower {
                max5MinPower = peak
                maxPowerDate = ride.startDate
                sourceName = ride.source.rawValue
            }
        }
        
        guard max5MinPower > 0, let powerDate = maxPowerDate else { return nil }
        
        // 2. Get most recent Weight in kg (ideally around the time of the peak power, but latest is fine)
        let recentWeightPoint = weightData.max(by: { $0.date < $1.date })
        guard let weightLbs = recentWeightPoint?.value, weightLbs > 0 else { return nil }
        let weightKg = weightLbs / 2.20462
        
        // 3. Calculate Relative Power and Compound Score
        let absolutePower = max5MinPower
        let relativePower = absolutePower / weightKg
        let compoundScore = absolutePower * relativePower
        
        // 4. Determine Phenotype & Level
        let phenotype = determinePhenotype(absolute: absolutePower, relative: relativePower, weightKg: weightKg)
        let level = determineLevel(compoundScore: compoundScore)
        
        let insight = generateInsight(
            compoundScore: compoundScore,
            relativeFTP: relativePower,
            absoluteFTP: absolutePower,
            phenotype: phenotype
        )
        
        return CompoundScoreAnalysis(
            absoluteFTP: absolutePower,
            weightKg: weightKg,
            relativeFTP: relativePower,
            compoundScore: compoundScore,
            phenotype: phenotype,
            level: level,
            insight: insight,
            dataSource: sourceName,
            dataDate: powerDate
        )
    }
    
    private func determinePhenotype(absolute: Double, relative: Double, weightKg: Double) -> String {
        if relative > 4.5 && weightKg < 70 {
            return "Climber"
        } else if absolute > 350 && relative < 4.0 {
            return "Rouleur / Flat Specialist"
        } else if absolute > 300 && relative >= 4.0 {
            return "All-Rounder"
        } else {
            return "Endurance Rider"
        }
    }
    
    private func determineLevel(compoundScore: Double) -> String {
        if compoundScore >= 1600 {
            return "Elite / Pro"
        } else if compoundScore >= 1100 {
            return "Advanced"
        } else if compoundScore >= 750 {
            return "Intermediate"
        } else if compoundScore >= 450 {
            return "Recreational"
        } else {
            return "Beginner"
        }
    }
    
    private func generateInsight(compoundScore: Double, relativeFTP: Double, absoluteFTP: Double, phenotype: String) -> String {
        if relativeFTP >= 4.0 && absoluteFTP >= 300 {
            return "Excellent Compound Score. Strong balance of raw power for flats and efficiency for climbs."
        } else if relativeFTP > 4.5 {
            return "High climbing efficiency. To improve your Compound Score, focus on raw absolute power."
        } else if absoluteFTP > 350 {
            return "High absolute power. You dominate the flats, but optimizing weight will boost climbing ability."
        } else {
            return "Consistent training will lift both raw power and power-to-weight ratio."
        }
    }
}
