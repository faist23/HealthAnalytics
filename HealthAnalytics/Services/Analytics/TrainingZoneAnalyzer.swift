//
//  TrainingZoneAnalyzer.swift
//  HealthAnalytics
//
//  Auto-detects training thresholds and analyzes zone distribution
//  No manual FTP/threshold tests required - uses your actual workout data
//

import Foundation
import SwiftUI
import HealthKit

struct TrainingZoneAnalyzer {
    
    // MARK: - Models
    
    struct ZoneAnalysis {
        let activityType: String
        let criticalPower: Double?        // Auto-detected from power curve
        let criticalPace: Double?         // Auto-detected from pace curve (min/km)
        let functionalThreshold: Double?  // Estimated FTP/threshold pace
        let thresholdMethod: String       // How threshold was detected
        let zones: [TrainingZone]
        let trainingBalance: TrainingBalance  // Renamed from polarizedBalance
        let efficiencyTrend: EfficiencyTrend
        let recentDecoupling: [DecouplingEvent]
        let confidence: Confidence
        
        enum Confidence {
            case high      // 20+ workouts with power/pace
            case medium    // 10-19 workouts
            case low       // 5-9 workouts
            case building  // <5 workouts
            
            var description: String {
                switch self {
                case .high: return "High confidence"
                case .medium: return "Medium confidence"
                case .low: return "Low confidence"
                case .building: return "Building baseline"
                }
            }
        }
    }
    
    struct TrainingZone {
        let number: Int
        let name: String
        let range: ClosedRange<Double>  // % of threshold
        let description: String
        let purpose: String
        let timeInZone: TimeInterval    // Recent 30 days
        let percentOfTotal: Double      // % of total training time
    }
    
    enum TrainingModel {
        case polarized      // 80/20: Lots of easy, lots of hard, minimal moderate
        case pyramidal      // 80/15/5: Lots of easy, some moderate, little hard
        case threshold      // 70/20/10: More threshold/tempo work
        
        var name: String {
            switch self {
            case .polarized: return "Polarized (80/20)"
            case .pyramidal: return "Pyramidal"
            case .threshold: return "Threshold-Based"
            }
        }
        
        var description: String {
            switch self {
            case .polarized:
                return "80% easy (Z1-2), minimal moderate, 20% hard (Z5+). Great for maximizing fitness with limited time."
            case .pyramidal:
                return "80% easy (Z1-2), 15% moderate (Z3-4), 5% hard (Z5+). Classic endurance model, sustainable long-term."
            case .threshold:
                return "70% easy (Z1-2), 20% threshold (Z3-4), 10% hard (Z5+). Builds race-specific fitness for time-crunched athletes."
            }
        }
        
        var targetDistribution: (easy: Double, moderate: Double, hard: Double) {
            switch self {
            case .polarized: return (80, 5, 15)      // 80% easy, 5% moderate, 15% hard
            case .pyramidal: return (80, 15, 5)      // 80% easy, 15% moderate, 5% hard
            case .threshold: return (70, 20, 10)     // 70% easy, 20% moderate, 10% hard
            }
        }
    }
    
    struct TrainingBalance {
        let model: TrainingModel
        let easyPercentage: Double      // Zone 1-2
        let moderatePercentage: Double  // Zone 3-4
        let hardPercentage: Double      // Zone 5+
        let matchesModel: Bool          // Within reasonable range of target
        let recommendation: String
        let targetEasy: Double
        let targetModerate: Double
        let targetHard: Double
    }
    
    struct EfficiencyTrend {
        let current: Double             // Current efficiency factor
        let thirtyDayChange: Double     // % change over 30 days
        let trend: Trend
        let interpretation: String
        
        enum Trend {
            case improving
            case stable
            case declining
        }
    }
    
    struct DecouplingEvent: Identifiable {
        let id = UUID()
        let date: Date
        let activityType: String
        let duration: TimeInterval
        let decouplingPercentage: Double  // HR drift while power/pace dropped
        let cause: String
        let severity: Severity
        
        enum Severity {
            case mild        // 2-5%
            case moderate    // 5-10%
            case significant // >10%
            
            var color: Color {
                switch self {
                case .mild: return .yellow
                case .moderate: return .orange
                case .significant: return .red
                }
            }
        }
    }
    
    // MARK: - Main Analysis
    
    func analyzeTrainingZones(
        workouts: [WorkoutData],
        activityType: HKWorkoutActivityType = .cycling
    ) -> ZoneAnalysis? {
        
        print("🎯 Analyzing Training Zones for \(activityType.name)...")
        
        // Filter to specific activity type
        let relevantWorkouts = workouts.filter { $0.workoutType == activityType }
        
        guard relevantWorkouts.count >= 5 else {
            print("   ⚠️ Need at least 5 workouts to analyze zones")
            return nil
        }
        
        // Determine confidence based on sample size
        let confidence = determineConfidence(workoutCount: relevantWorkouts.count)
        
        // Auto-detect critical power/pace with conservative algorithm
        let (criticalPower, criticalPace, detectionMethod) = detectCriticalThreshold(workouts: relevantWorkouts)
        
        // Estimate functional threshold (95% of critical power/pace)
        let functionalThreshold: Double?
        if let cp = criticalPower {
            functionalThreshold = cp * 0.95
        } else if let pace = criticalPace {
            functionalThreshold = pace / 0.95
        } else {
            functionalThreshold = nil
        }
        
        // Generate training zones based on threshold
        let zones = generateZones(
            threshold: functionalThreshold ?? 200,  // Default if not detected
            activityType: activityType,
            workouts: relevantWorkouts
        )
        
        // Determine best-fit training model based on current distribution
        let trainingBalance = analyzeTrainingBalance(zones: zones)
        
        // Calculate efficiency trend
        let efficiencyTrend = calculateEfficiencyTrend(workouts: relevantWorkouts)
        
        // Detect recent decoupling events
        let decouplingEvents = detectDecoupling(workouts: relevantWorkouts)
        
        print("   ✅ Zones analyzed: \(detectionMethod)")
        print("   📊 Training Balance (\(trainingBalance.model.name)): \(Int(trainingBalance.easyPercentage))% easy, \(Int(trainingBalance.moderatePercentage))% moderate, \(Int(trainingBalance.hardPercentage))% hard")
        
        return ZoneAnalysis(
            activityType: activityType.name,
            criticalPower: criticalPower,
            criticalPace: criticalPace,
            functionalThreshold: functionalThreshold,
            thresholdMethod: detectionMethod,
            zones: zones,
            trainingBalance: trainingBalance,
            efficiencyTrend: efficiencyTrend,
            recentDecoupling: decouplingEvents,
            confidence: confidence
        )
    }
    
    // MARK: - Critical Power/Pace Detection
    
    private func detectCriticalThreshold(workouts: [WorkoutData]) -> (power: Double?, pace: Double?, method: String) {
        // Conservative threshold detection using multiple methods
        // Avoids overestimating from occasional hard efforts
        
        var bestPower: Double?
        var bestPace: Double?
        var method = "Not enough data"
        
        // Only consider recent workouts (last 120 days) to reflect current fitness
        let cutoffDate = Date().addingTimeInterval(-120 * 24 * 3600)
        let recentWorkouts = workouts.filter { $0.startDate >= cutoffDate }
        
        // Find workouts 15-60 minutes long (ideal for threshold detection)
        let thresholdWorkouts = recentWorkouts.filter {
            $0.duration >= 900 && $0.duration <= 3600
        }
        
        // For power-based activities
        let powerWorkouts = thresholdWorkouts.compactMap { $0.averagePower }.sorted(by: >)
        if powerWorkouts.count >= 3 {
            // Use 90th percentile of top efforts instead of best single effort
            // This is more conservative and realistic for non-test workouts
            let top10Percent = Array(powerWorkouts.prefix(max(3, powerWorkouts.count / 10)))
            bestPower = top10Percent.reduce(0, +) / Double(top10Percent.count)
            method = "Avg of top \(top10Percent.count) efforts (last 120 days)"
        } else if let topEffort = powerWorkouts.first {
            // Not enough data, use single best but apply conservative factor
            bestPower = topEffort * 0.90  // 10% reduction for safety
            method = "Single effort, 90% applied (last 120 days)"
        }
        
        // For pace-based activities (running)
        let paceWorkouts = thresholdWorkouts.compactMap { workout -> Double? in
            guard let distance = workout.totalDistance, distance > 0 else { return nil }
            let paceSecondsPerKm = (workout.duration / (distance / 1000))
            return paceSecondsPerKm / 60.0  // Convert to min/km
        }.sorted()  // Faster pace = lower number
        
        if paceWorkouts.count >= 3 {
            let top10Percent = Array(paceWorkouts.prefix(max(3, paceWorkouts.count / 10)))
            bestPace = top10Percent.reduce(0, +) / Double(top10Percent.count)
            method = "Avg of top \(top10Percent.count) efforts (last 120 days)"
        } else if let fastestPace = paceWorkouts.first {
            bestPace = fastestPace * 1.05  // 5% slower for safety (higher number = slower)
            method = "Single effort, 5% slower (last 120 days)"
        }
        
        return (bestPower, bestPace, method)
    }
    
    // MARK: - Zone Generation
    
    private func generateZones(
        threshold: Double,
        activityType: HKWorkoutActivityType,
        workouts: [WorkoutData]
    ) -> [TrainingZone] {
        
        let last30Days = Date().addingTimeInterval(-30 * 24 * 3600)
        let recentWorkouts = workouts.filter { $0.startDate >= last30Days }
        let totalTime = recentWorkouts.reduce(0.0) { $0 + $1.duration }
        
        // Define zones as % of FTP/Threshold
        let zoneDefinitions: [(Int, String, ClosedRange<Double>, String, String)] = [
            (1, "Recovery", 0...0.55, "Active recovery and warm-up", "Promote recovery"),
            (2, "Endurance", 0.56...0.75, "Base aerobic development", "Build aerobic base"),
            (3, "Tempo", 0.76...0.90, "Sustained moderate effort", "Increase endurance"),
            (4, "Threshold", 0.91...1.05, "At or near FTP/threshold pace", "Raise threshold"),
            (5, "VO2max", 1.06...1.20, "Hard intervals, 3-8 minutes", "Boost max capacity"),
            (6, "Anaerobic", 1.21...1.50, "Very hard, 30s-3min", "Increase power/speed"),
            (7, "Neuromuscular", 1.51...2.00, "Sprint efforts, <30s", "Develop explosiveness")
        ]
        
        return zoneDefinitions.map { (number, name, range, desc, purpose) in
            // Calculate time in this zone (simplified - would need lap data for accuracy)
            let estimatedTime = estimateTimeInZone(
                zone: number,
                workouts: recentWorkouts,
                threshold: threshold
            )
            
            let percentage = totalTime > 0 ? (estimatedTime / totalTime) * 100 : 0
            
            return TrainingZone(
                number: number,
                name: name,
                range: range,
                description: desc,
                purpose: purpose,
                timeInZone: estimatedTime,
                percentOfTotal: percentage
            )
        }
    }
    
    private func estimateTimeInZone(zone: Int, workouts: [WorkoutData], threshold: Double) -> TimeInterval {
        // Simplified estimation based on average power/pace
        // In a production app, you'd use lap-by-lap or second-by-second data
        
        var timeInZone: TimeInterval = 0
        
        for workout in workouts {
            if let power = workout.averagePower {
                let intensity = power / threshold
                
                switch zone {
                case 1 where intensity <= 0.55:
                    timeInZone += workout.duration
                case 2 where intensity > 0.55 && intensity <= 0.75:
                    timeInZone += workout.duration
                case 3 where intensity > 0.75 && intensity <= 0.90:
                    timeInZone += workout.duration
                case 4 where intensity > 0.90 && intensity <= 1.05:
                    timeInZone += workout.duration
                case 5 where intensity > 1.05 && intensity <= 1.20:
                    timeInZone += workout.duration
                default:
                    break
                }
            }
        }
        
        return timeInZone
    }
    
    // MARK: - Training Balance Analysis
    
    private func analyzeTrainingBalance(zones: [TrainingZone]) -> TrainingBalance {
        let zone1 = zones.first { $0.number == 1 }?.percentOfTotal ?? 0
        let zone2 = zones.first { $0.number == 2 }?.percentOfTotal ?? 0
        let zone3 = zones.first { $0.number == 3 }?.percentOfTotal ?? 0
        let zone4 = zones.first { $0.number == 4 }?.percentOfTotal ?? 0
        let zone5Plus = zones.filter { $0.number >= 5 }.reduce(0.0) { $0 + $1.percentOfTotal }
        
        let easyPercentage = zone1 + zone2
        let moderatePercentage = zone3 + zone4
        let hardPercentage = zone5Plus
        
        // Determine which training model best fits current distribution
        let bestFitModel = determineBestFitModel(
            easy: easyPercentage,
            moderate: moderatePercentage,
            hard: hardPercentage
        )
        
        // Check if within acceptable range of the model
        let target = bestFitModel.targetDistribution
        let matchesModel = abs(easyPercentage - target.easy) <= 15 &&
                          abs(moderatePercentage - target.moderate) <= 10 &&
                          abs(hardPercentage - target.hard) <= 10
        
        // Generate recommendation based on model and current distribution
        let recommendation = generateRecommendation(
            model: bestFitModel,
            easy: easyPercentage,
            moderate: moderatePercentage,
            hard: hardPercentage,
            target: target
        )
        
        return TrainingBalance(
            model: bestFitModel,
            easyPercentage: easyPercentage,
            moderatePercentage: moderatePercentage,
            hardPercentage: hardPercentage,
            matchesModel: matchesModel,
            recommendation: recommendation,
            targetEasy: target.easy,
            targetModerate: target.moderate,
            targetHard: target.hard
        )
    }
    
    private func determineBestFitModel(easy: Double, moderate: Double, hard: Double) -> TrainingModel {
        // Calculate distance from each model's target distribution
        let polarizedTarget = TrainingModel.polarized.targetDistribution
        let pyramidalTarget = TrainingModel.pyramidal.targetDistribution
        let thresholdTarget = TrainingModel.threshold.targetDistribution
        
        let polarizedDistance = abs(easy - polarizedTarget.easy) + 
                               abs(moderate - polarizedTarget.moderate) + 
                               abs(hard - polarizedTarget.hard)
        let pyramidalDistance = abs(easy - pyramidalTarget.easy) + 
                               abs(moderate - pyramidalTarget.moderate) + 
                               abs(hard - pyramidalTarget.hard)
        let thresholdDistance = abs(easy - thresholdTarget.easy) + 
                               abs(moderate - thresholdTarget.moderate) + 
                               abs(hard - thresholdTarget.hard)
        
        // Return model with smallest distance
        if polarizedDistance <= pyramidalDistance && polarizedDistance <= thresholdDistance {
            return .polarized
        } else if pyramidalDistance <= thresholdDistance {
            return .pyramidal
        } else {
            return .threshold
        }
    }
    
    private func generateRecommendation(
        model: TrainingModel,
        easy: Double,
        moderate: Double,
        hard: Double,
        target: (easy: Double, moderate: Double, hard: Double)
    ) -> String {
        let easyDiff = easy - target.easy
        let moderateDiff = moderate - target.moderate
        let hardDiff = hard - target.hard
        
        switch model {
        case .polarized:
            if abs(easyDiff) <= 10 && abs(hardDiff) <= 10 {
                return "Excellent polarized distribution! Most time easy, minimal moderate, focused hard work."
            } else if easyDiff < -10 {
                return "Add more easy Z1-2 volume. Polarized means lots of easy, not just lots of hard."
            } else if moderateDiff > 10 {
                return "Too much Z3-4 'gray zone'. Go harder or go easier for better polarization."
            } else {
                return "Add 1-2 high-intensity sessions (Z5+) to complement your easy base."
            }
            
        case .pyramidal:
            if abs(easyDiff) <= 10 && abs(moderateDiff) <= 10 && abs(hardDiff) <= 5 {
                return "Classic pyramidal distribution. Sustainable and effective for most athletes."
            } else if easyDiff < -10 {
                return "Build more aerobic base (Z1-2). Pyramidal = lots of easy foundation."
            } else if moderateDiff < -5 {
                return "Add tempo/threshold work (Z3-4) to sharpen fitness."
            } else {
                return "Dial back hard intensity slightly. Pyramidal focuses on volume over intensity."
            }
            
        case .threshold:
            if abs(easyDiff) <= 10 && abs(moderateDiff) <= 10 {
                return "Good threshold-focused distribution. Efficient for time-crunched athletes."
            } else if moderateDiff < -5 {
                return "Add more threshold/tempo sessions (Z3-4) to build race-specific fitness."
            } else if hardDiff > 5 {
                return "Too much Z5+ work. Threshold model emphasizes sustainable hard efforts."
            } else {
                return "Balance easy recovery with quality threshold work for best results."
            }
        }
    }
    
    // MARK: - Efficiency Factor
    
    private func calculateEfficiencyTrend(workouts: [WorkoutData]) -> EfficiencyTrend {
        // Efficiency Factor = Power/Pace per heart beat
        // Higher EF = more output per heart beat = better aerobic fitness
        
        let now = Date()
        let thirtyDaysAgo = now.addingTimeInterval(-30 * 24 * 3600)
        let sixtyDaysAgo = now.addingTimeInterval(-60 * 24 * 3600)
        
        let recentWorkouts = workouts.filter {
            $0.startDate >= thirtyDaysAgo &&
            $0.averageHeartRate != nil &&
            ($0.averagePower != nil || $0.totalDistance != nil)
        }
        
        let previousWorkouts = workouts.filter {
            $0.startDate >= sixtyDaysAgo &&
            $0.startDate < thirtyDaysAgo &&
            $0.averageHeartRate != nil &&
            ($0.averagePower != nil || $0.totalDistance != nil)
        }
        
        guard !recentWorkouts.isEmpty else {
            return EfficiencyTrend(
                current: 0,
                thirtyDayChange: 0,
                trend: .stable,
                interpretation: "Need more data with heart rate to calculate efficiency."
            )
        }
        
        let currentEF = calculateAverageEF(workouts: recentWorkouts)
        let previousEF = calculateAverageEF(workouts: previousWorkouts)
        
        let change = previousEF > 0 ? ((currentEF - previousEF) / previousEF) * 100 : 0
        
        let trend: EfficiencyTrend.Trend
        let interpretation: String
        
        if change > 5 {
            trend = .improving
            interpretation = "Your aerobic fitness is improving! More output per heartbeat."
        } else if change < -5 {
            trend = .declining
            interpretation = "Efficiency declining. Check recovery, nutrition, or overtraining."
        } else {
            trend = .stable
            interpretation = "Efficiency stable. Continue current training approach."
        }
        
        return EfficiencyTrend(
            current: currentEF,
            thirtyDayChange: change,
            trend: trend,
            interpretation: interpretation
        )
    }
    
    private func calculateAverageEF(workouts: [WorkoutData]) -> Double {
        let efficiencies = workouts.compactMap { workout -> Double? in
            guard let hr = workout.averageHeartRate, hr > 0 else { return nil }
            
            if let power = workout.averagePower, power > 0 {
                return power / hr
            } else if let distance = workout.totalDistance, distance > 0 {
                let paceKmH = (distance / 1000) / (workout.duration / 3600)
                return paceKmH / hr
            }
            return nil
        }
        
        guard !efficiencies.isEmpty else { return 0 }
        return efficiencies.reduce(0, +) / Double(efficiencies.count)
    }
    
    // MARK: - Decoupling Detection
    
    private func detectDecoupling(workouts: [WorkoutData]) -> [DecouplingEvent] {
        // Cardiac decoupling: HR stays high but power/pace drops during long efforts
        // This indicates glycogen depletion or dehydration
        
        let last30Days = Date().addingTimeInterval(-30 * 24 * 3600)
        let longWorkouts = workouts.filter {
            $0.startDate >= last30Days &&
            $0.duration > 3600 &&  // >1 hour
            $0.averageHeartRate != nil
        }
        
        // Simplified detection (would need lap data for real decoupling analysis)
        return longWorkouts.compactMap { workout in
            // If we had lap data, we'd compare first half vs second half
            // For now, flag long workouts with high HR and low power as potential decoupling
            
            guard let hr = workout.averageHeartRate else { return nil }
            
            // Heuristic: If duration > 2 hours and HR > 140, likely some decoupling occurred
            if workout.duration > 7200 && hr > 140 {
                return DecouplingEvent(
                    date: workout.startDate,
                    activityType: workout.workoutType.name,
                    duration: workout.duration,
                    decouplingPercentage: 5.0,  // Placeholder
                    cause: "Long duration + high HR suggests glycogen depletion or dehydration",
                    severity: .moderate
                )
            }
            
            return nil
        }
    }
    
    // MARK: - Helper Methods
    
    private func determineConfidence(workoutCount: Int) -> ZoneAnalysis.Confidence {
        if workoutCount >= 20 {
            return .high
        } else if workoutCount >= 10 {
            return .medium
        } else if workoutCount >= 5 {
            return .low
        } else {
            return .building
        }
    }
}
