//
//  InjuryRiskCalculator.swift
//  HealthAnalytics
//
//  Created by Craig Faist on 1/26/26.
//


import Foundation

struct InjuryRiskCalculator {
    
    // MARK: - Risk Models
    
    struct InjuryRiskAssessment {
        let riskScore: Int
        let riskLevel: RiskLevel
        let contributingFactors: [RiskFactor]
        let recommendation: String
        
        enum RiskLevel {
            case low
            case moderate
            case high
            case veryHigh
            
            var emoji: String {
                switch self {
                case .low: return "🟢"
                case .moderate: return "🟡"
                case .high: return "🟠"
                case .veryHigh: return "🔴"
                }
            }
            
            var color: String {
                switch self {
                case .low: return "green"
                case .moderate: return "yellow"
                case .high: return "orange"
                case .veryHigh: return "red"
                }
            }
            
            var label: String {
                switch self {
                case .low: return "Low Injury Risk"
                case .moderate: return "Moderate Injury Risk"
                case .high: return "High Injury Risk"
                case .veryHigh: return "Very High Injury Risk"
                }
            }
        }
        
        struct RiskFactor {
            let description: String
            let points: Int
            let severity: Severity
            
            enum Severity {
                case minor, moderate, major
            }
        }
    }
    
    // MARK: - Calculate Injury Risk
    
    /// Calculates injury risk based on training load, recovery, and trends
    func calculateInjuryRisk(
        trainingLoad: TrainingLoadCalculator.TrainingLoadSummary?,
        recoveryInsights: [CorrelationEngine.RecoveryInsight],
        trends: [TrendDetector.MetricTrend],
        recentWorkouts: [WorkoutData],
        stravaActivities: [StravaActivity]
    ) -> InjuryRiskAssessment? {
        
        var riskScore = 0
        var factors: [InjuryRiskAssessment.RiskFactor] = []
        
        // 1. Training Load Analysis (Most Important)
        if let load = trainingLoad {
            // More nuanced ACR scoring - consider absolute load too
            let isLowAbsoluteLoad = load.acuteLoad < 100 // Very low training volume
            
            switch load.status {
            case .overreaching:
                // If absolute load is low, this is less concerning
                let points = isLowAbsoluteLoad ? 25 : 40
                riskScore += points
                factors.append(InjuryRiskAssessment.RiskFactor(
                    description: "ACR \(String(format: "%.2f", load.acuteChronicRatio)) - Training load spike detected",
                    points: points,
                    severity: isLowAbsoluteLoad ? .moderate : .major
                ))
                
            case .fatigued:
                // If coming back from low load, this is expected
                let points = isLowAbsoluteLoad ? 15 : 25
                riskScore += points
                factors.append(InjuryRiskAssessment.RiskFactor(
                    description: "ACR \(String(format: "%.2f", load.acuteChronicRatio)) - Load increasing",
                    points: points,
                    severity: .moderate
                ))
                
            case .fresh:
                // Deduct points for being well-recovered
                riskScore -= 10
                
            case .optimal:
                // No points - this is good
                break
            }
        }
        
        // 2. Recovery Metrics
        let rhrInsight = recoveryInsights.first { $0.metric == "Resting Heart Rate" }
        let hrvInsight = recoveryInsights.first { $0.metric == "Heart Rate Variability" }
        
        if let rhr = rhrInsight {
            let difference = rhr.currentValue - rhr.baselineValue
            
            if difference >= 5 {
                riskScore += 15
                factors.append(InjuryRiskAssessment.RiskFactor(
                    description: "RHR elevated \(Int(difference)) bpm above baseline",
                    points: 15,
                    severity: .moderate
                ))
            } else if difference >= 3 {
                riskScore += 10
                factors.append(InjuryRiskAssessment.RiskFactor(
                    description: "RHR slightly elevated (\(Int(difference)) bpm)",
                    points: 10,
                    severity: .minor
                ))
            }
        }
        
        if let hrv = hrvInsight {
            let percentDiff = ((hrv.currentValue - hrv.baselineValue) / hrv.baselineValue) * 100
            
            if percentDiff <= -15 {
                riskScore += 15
                factors.append(InjuryRiskAssessment.RiskFactor(
                    description: "HRV suppressed \(String(format: "%.0f", abs(percentDiff)))% below baseline",
                    points: 15,
                    severity: .moderate
                ))
            } else if percentDiff <= -10 {
                riskScore += 10
                factors.append(InjuryRiskAssessment.RiskFactor(
                    description: "HRV moderately suppressed (\(String(format: "%.0f", abs(percentDiff)))%)",
                    points: 10,
                    severity: .minor
                ))
            }
        }
        
        // Both RHR and HRV compromised = extra risk
        if let rhr = rhrInsight, let hrv = hrvInsight,
           rhr.trend == .fatigued, hrv.trend == .fatigued {
            riskScore += 15
            factors.append(InjuryRiskAssessment.RiskFactor(
                description: "Multiple recovery metrics compromised",
                points: 15,
                severity: .major
            ))
        }
        
        // 3. Sleep Issues
        if let sleepTrend = trends.first(where: { $0.metric == "Sleep Duration" }),
           sleepTrend.direction == .declining,
           abs(sleepTrend.percentChange) > 10 {
            riskScore += 10
            factors.append(InjuryRiskAssessment.RiskFactor(
                description: "Sleep duration declining (\(String(format: "%.0f", abs(sleepTrend.percentChange)))%)",
                points: 10,
                severity: .minor
            ))
        }
        
        // 4. Load Spike Detection (week-over-week)
        let loadSpike = detectLoadSpike(
            recentWorkouts: recentWorkouts,
            stravaActivities: stravaActivities
        )
        
        if loadSpike > 0.3 { // 30%+ spike
            riskScore += 20
            factors.append(InjuryRiskAssessment.RiskFactor(
                description: "Sudden load increase (\(Int(loadSpike * 100))% in past week)",
                points: 20,
                severity: .major
            ))
        } else if loadSpike > 0.2 { // 20-30% spike
            riskScore += 10
            factors.append(InjuryRiskAssessment.RiskFactor(
                description: "Moderate load increase (\(Int(loadSpike * 100))%)",
                points: 10,
                severity: .minor
            ))
        }
        
        // 5. Multiple Declining Trends
        let decliningCount = trends.filter { $0.direction == .declining }.count
        if decliningCount >= 3 {
            riskScore += 15
            factors.append(InjuryRiskAssessment.RiskFactor(
                description: "\(decliningCount) metrics declining simultaneously",
                points: 15,
                severity: .moderate
            ))
        } else if decliningCount == 2 {
            riskScore += 5
            factors.append(InjuryRiskAssessment.RiskFactor(
                description: "Multiple metrics declining",
                points: 5,
                severity: .minor
            ))
        }
        
        // Only show assessment if there are actual risk factors
        // This prevents "low risk" noise when everything is fine
        guard !factors.isEmpty || riskScore > 0 else {
            return nil
        }
        
        // Determine risk level (adjusted thresholds to reduce false alarms)
        let riskLevel: InjuryRiskAssessment.RiskLevel
        
        if riskScore >= 70 {
            riskLevel = .veryHigh
        } else if riskScore >= 50 {
            riskLevel = .high
        } else if riskScore >= 30 {
            riskLevel = .moderate
        } else {
            riskLevel = .low
        }
        
        // Generate recommendation
        let recommendation = generateRecommendation(
            riskLevel: riskLevel,
            factors: factors
        )
        
        print("🏥 Injury Risk Assessment:")
        print("   Risk Score: \(riskScore)")
        print("   Risk Level: \(riskLevel)")
        print("   Contributing Factors: \(factors.count)")
        
        return InjuryRiskAssessment(
            riskScore: riskScore,
            riskLevel: riskLevel,
            contributingFactors: factors,
            recommendation: recommendation
        )
    }
    
    // MARK: - Helper Methods
    
    private func detectLoadSpike(
        recentWorkouts: [WorkoutData],
        stravaActivities: [StravaActivity]
    ) -> Double {
        
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        guard let oneWeekAgo = calendar.date(byAdding: .day, value: -7, to: today),
              let twoWeeksAgo = calendar.date(byAdding: .day, value: -14, to: today) else {
            return 0
        }
        
        // Calculate last week's load
        let lastWeekWorkouts = recentWorkouts.filter { workout in
            workout.startDate >= oneWeekAgo && workout.startDate < today
        }
        
        let lastWeekStrava = stravaActivities.filter { activity in
            guard let date = activity.startDateFormatted else { return false }
            return date >= oneWeekAgo && date < today
        }
        
        let lastWeekLoad = calculateTotalLoad(
            workouts: lastWeekWorkouts,
            stravaActivities: lastWeekStrava
        )
        
        // Calculate previous week's load
        let prevWeekWorkouts = recentWorkouts.filter { workout in
            workout.startDate >= twoWeeksAgo && workout.startDate < oneWeekAgo
        }
        
        let prevWeekStrava = stravaActivities.filter { activity in
            guard let date = activity.startDateFormatted else { return false }
            return date >= twoWeeksAgo && date < oneWeekAgo
        }
        
        let prevWeekLoad = calculateTotalLoad(
            workouts: prevWeekWorkouts,
            stravaActivities: prevWeekStrava
        )
        
        guard prevWeekLoad > 0 else { return 0 }
        
        let spike = (lastWeekLoad - prevWeekLoad) / prevWeekLoad
        
        return max(0, spike) // Only positive spikes
    }
    
    private func calculateTotalLoad(
        workouts: [WorkoutData],
        stravaActivities: [StravaActivity]
    ) -> Double {
        
        let workoutLoad = workouts.reduce(0.0) { total, workout in
            total + (workout.duration / 3600.0) * 60 // Rough TSS
        }
        
        let stravaLoad = stravaActivities.reduce(0.0) { total, activity in
            total + (Double(activity.movingTime) / 3600.0) * 60
        }
        
        return workoutLoad + stravaLoad
    }
    
    private func generateRecommendation(
        riskLevel: InjuryRiskAssessment.RiskLevel,
        factors: [InjuryRiskAssessment.RiskFactor]
    ) -> String {
        
        switch riskLevel {
        case .veryHigh:
            return "Multiple significant risk factors detected. Take immediate action to reduce injury risk."
            
        case .high:
            return "Elevated injury risk. Be cautious with training progression and prioritize recovery."
            
        case .moderate:
            return "Some warning signs present. Monitor closely and adjust training if needed. This is normal when ramping up after a break."
            
        case .low:
            if factors.isEmpty {
                return "Continue current training and recovery practices."
            } else {
                return "Minor risk factors present but manageable. Continue monitoring trends."
            }
        }
    }
}
