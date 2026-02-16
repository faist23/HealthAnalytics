//
//  HeuristicIntentClassifier.swift
//  HealthAnalytics
//
//  Rule-based automatic intent classification using physiological markers
//  No manual labeling required - runs automatically on workout import
//

import Foundation
import HealthKit

struct HeuristicIntentClassifier {
    
    // MARK: - Classification
    
    /// Automatically classify workout intent based on physiological markers
    /// Returns (intent, confidence) where confidence is 0.0-1.0
    static func classifyWorkout(_ workout: StoredWorkout) -> (intent: ActivityIntent, confidence: Double) {
        
        let type = workout.workoutType
        let durationMinutes = workout.duration / 60.0
        
        // Handle strength training first
        if type == .functionalStrengthTraining || type == .traditionalStrengthTraining {
            return (.strength, 0.9)
        }
        
        // Handle walking
        if type == .walking {
            // Short walks with low/no HR data are likely casual
            if durationMinutes < 45 || workout.averageHeartRate == nil || (workout.averageHeartRate ?? 0) < 100 {
                return (.casualWalk, 0.85)
            }
            // Long walks with elevated HR might be exercise walks
            return (.easy, 0.7)
        }
        
        // For cardio activities (running, cycling, swimming), use HR-based classification
        guard let avgHR = workout.averageHeartRate, avgHR > 0 else {
            // No HR data - make best guess from duration and activity type
            return classifyWithoutHeartRate(workout)
        }
        
        // Estimate max HR (rough approximation: 220 - age, but we'll use 185 as a conservative estimate)
        // Most endurance athletes have max HR between 170-200
        let estimatedMaxHR = 185.0
        let hrPercentage = (avgHR / estimatedMaxHR) * 100.0
        
        // Calculate pace if available (for running/walking)
        var avgPaceMinPerMile: Double? = nil
        if let distance = workout.distance, distance > 0 {
            let miles = distance / 1609.34
            avgPaceMinPerMile = workout.duration / miles / 60.0
        }
        
        // Classify based on HR zones and activity patterns
        if hrPercentage >= 85 {
            // Very high effort - likely race or PR attempt
            // Races are sustained high effort
            if durationMinutes >= 15 {
                return (.race, 0.85)
            } else {
                // Short high intensity = intervals
                return (.intervals, 0.80)
            }
            
        } else if hrPercentage >= 78 {
            // Threshold zone - tempo run or hard effort
            
            // Check for interval patterns (we'd need HR variability for this, but we can approximate)
            // For now, sustained efforts are tempo
            if durationMinutes >= 20 && durationMinutes <= 60 {
                return (.tempo, 0.85)
            } else if durationMinutes < 20 {
                // Shorter high effort = intervals
                return (.intervals, 0.75)
            } else {
                // Long sustained hard effort = race pace or tempo
                return (.tempo, 0.80)
            }
            
        } else if hrPercentage >= 68 {
            // Moderate effort zone
            
            // Long duration at moderate effort = long run/ride
            if durationMinutes >= 90 {
                return (.long, 0.90)
            }
            
            // Medium duration could be tempo or easy depending on context
            if durationMinutes >= 45 {
                // Longer moderate efforts are likely long runs
                return (.long, 0.75)
            } else {
                // Shorter moderate efforts are likely easy/recovery
                return (.easy, 0.75)
            }
            
        } else {
            // Low effort zone (< 68% max HR)
            
            // Very long low effort = easy long run
            if durationMinutes >= 90 {
                return (.long, 0.80)
            }
            
            // Otherwise easy/recovery
            return (.easy, 0.85)
        }
    }
    
    /// Fallback classification when no HR data is available
    private static func classifyWithoutHeartRate(_ workout: StoredWorkout) -> (intent: ActivityIntent, confidence: Double) {
        let durationMinutes = workout.duration / 60.0
        let type = workout.workoutType
        
        // Use duration and pace as proxies
        var avgPaceMinPerMile: Double? = nil
        if let distance = workout.distance, distance > 0 {
            let miles = distance / 1609.34
            avgPaceMinPerMile = workout.duration / miles / 60.0
        }
        
        // Long duration = long run/ride
        if durationMinutes >= 90 {
            return (.long, 0.60)
        }
        
        // For running, use pace as a proxy
        if type == .running, let pace = avgPaceMinPerMile {
            // Fast pace (< 7:30/mile) = hard effort
            if pace < 7.5 {
                if durationMinutes >= 20 && durationMinutes <= 60 {
                    return (.tempo, 0.50)
                } else if durationMinutes < 20 {
                    return (.intervals, 0.45)
                } else {
                    return (.race, 0.40)
                }
            }
            // Easy pace (> 9:00/mile) = easy
            else if pace > 9.0 {
                return (.easy, 0.60)
            }
        }
        
        // Default to easy/other for cardio without good data
        if type == .running || type == .cycling || type == .swimming {
            return (.easy, 0.40)
        }
        
        // Unknown
        return (.other, 0.30)
    }
    
    // MARK: - Batch Classification
    
    /// Classify all unlabeled workouts in a batch
    static func classifyAll(
        workouts: [StoredWorkout],
        existingLabels: Set<String>
    ) -> [(workoutId: String, intent: ActivityIntent, confidence: Double)] {
        
        var results: [(String, ActivityIntent, Double)] = []
        
        for workout in workouts {
            // Skip if already labeled
            guard !existingLabels.contains(workout.id) else { continue }
            
            let (intent, confidence) = classifyWorkout(workout)
            results.append((workout.id, intent, confidence))
        }
        
        print("🧠 Heuristic classifier: Classified \(results.count) workouts")
        
        return results
    }
    
    // MARK: - Classification Logic Summary
    
    /// Returns a human-readable explanation of classification rules
    static func classificationRules() -> String {
        """
        Automatic Workout Intent Classification Rules:
        
        Based on Heart Rate Zones (% of estimated max HR):
        • 85%+ sustained (15+ min) → Race/PR Attempt
        • 85%+ short duration → Intervals
        • 78-85% sustained → Tempo/Threshold
        • 78-85% short → Intervals
        • 68-78% + 90+ min → Long Run/Endurance
        • 68-78% + 45-90 min → Long Run or Easy
        • 68-78% + <45 min → Easy/Recovery
        • <68% + 90+ min → Long Easy Run
        • <68% → Easy/Recovery
        
        Special Cases:
        • Strength Training → Always classified as Strength
        • Walking (short/low HR) → Casual Walk
        • Walking (long/high HR) → Easy
        • No HR data → Uses duration + pace as proxy (lower confidence)
        
        All classifications include a confidence score (0.0-1.0).
        Lower confidence means the system is less certain and the label
        could be manually reviewed if needed.
        """
    }
}
