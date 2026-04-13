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
    
    /// Automatically classify workout intent based on physiological markers.
    /// For cycling: power zone distribution is used as the primary signal when available —
    /// it captures interval structure that average HR cannot (HR lags power, especially in short efforts).
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
            if durationMinutes < 45 || workout.averageHeartRate == nil || (workout.averageHeartRate ?? 0) < 100 {
                return (.casualWalk, 0.85)
            }
            return (.easy, 0.7)
        }

        // Power-zone path: takes priority over HR for cycling when stream data is present.
        // HR averages mask interval structure; zone distribution is the ground truth.
        if type == .cycling, let zoneSecs = workout.powerZoneSeconds {
            return classifyFromPowerZones(zoneSecs: zoneSecs, durationMinutes: durationMinutes)
        }

        // For cardio activities (running, cycling, swimming), use HR-based classification
        guard let avgHR = workout.averageHeartRate, avgHR > 0 else {
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
    
    // MARK: - Power Zone Classification

    /// Classify a cycling workout from its 7-zone power distribution.
    /// Zone boundaries: Z1 <55%, Z2 55-75%, Z3 76-90%, Z4 91-105%, Z5 106-120%, Z6 121-150%, Z7 >150% FTP.
    ///
    /// Priority order (first match wins):
    ///   Intervals  → ≥20% in Z5-Z7, or ≥10% in Z6-Z7 (anaerobic)
    ///   Race/TT    → ≥30% in Z4 + <15% in Z5-Z7 + ≥45min (sustained threshold)
    ///   Threshold  → ≥25% in Z4 + <15% in Z5-Z7
    ///   Tempo      → ≥30% in Z3 + <25% in Z4 + <10% in Z5-Z7
    ///   Long       → ≥70% in Z1-Z2 + ≥90min duration
    ///   Easy       → ≥70% in Z1-Z2
    static func classifyFromPowerZones(
        zoneSecs: [Double],
        durationMinutes: Double
    ) -> (intent: ActivityIntent, confidence: Double) {
        guard zoneSecs.count == 7 else { return (.other, 0.3) }

        let total = zoneSecs.reduce(0, +)
        guard total > 0 else { return (.other, 0.3) }

        let pct = zoneSecs.map { $0 / total }
        let highZone     = pct[4] + pct[5] + pct[6]   // Z5 + Z6 + Z7
        let anaerobicZone = pct[5] + pct[6]             // Z6 + Z7
        let enduranceBase = pct[0] + pct[1]             // Z1 + Z2

        // Intervals: significant time above VO2max, or meaningful anaerobic work
        if highZone >= 0.20 || anaerobicZone >= 0.10 {
            let conf = anaerobicZone >= 0.10 ? 0.92 : 0.85
            return (.intervals, conf)
        }

        // Race / Time Trial: sustained above-threshold with little Z5+ (TT or race effort)
        if pct[3] >= 0.30 && highZone < 0.15 && durationMinutes >= 45 {
            return (.race, 0.88)
        }

        // Threshold: significant Z4 work without much high-zone
        if pct[3] >= 0.25 && highZone < 0.15 {
            return (.tempo, 0.87)   // maps to "Tempo/Threshold" intent
        }

        // Tempo / Sweetspot: mostly Z3 work
        if pct[2] >= 0.30 && pct[3] < 0.25 && highZone < 0.10 {
            return (.tempo, 0.84)
        }

        // Long endurance ride
        if enduranceBase >= 0.70 && durationMinutes >= 90 {
            return (.long, 0.88)
        }

        // Easy / Recovery
        if enduranceBase >= 0.70 {
            return (.easy, 0.85)
        }

        // Mixed / not clearly dominant — defer to HR if available, else easy
        return (.easy, 0.55)
    }

    // MARK: - HR Fallback Classification

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
    
    /// Classify workouts in a batch.
    ///
    /// - Unlabeled workouts: always classified.
    /// - Cycling workouts with power zone data that were previously labeled by a heuristic (not manually):
    ///   re-classified using the more accurate power-zone path. The caller is responsible for
    ///   updating the existing label rather than inserting a duplicate.
    ///
    /// Returns new classifications. Re-classifications are flagged via `isReclassification = true`
    /// so the caller can upsert rather than insert.
    static func classifyAll(
        workouts: [StoredWorkout],
        existingLabels: Set<String>,
        heuristicLabeledIds: Set<String> = []   // IDs whose current label came from heuristic/HR (not manual)
    ) -> [(workoutId: String, intent: ActivityIntent, confidence: Double, isReclassification: Bool)] {

        var results: [(String, ActivityIntent, Double, Bool)] = []

        for workout in workouts {
            let alreadyLabeled = existingLabels.contains(workout.id)

            // Re-classify cycling workouts that now have zone data but were labeled by HR heuristic
            if alreadyLabeled,
               workout.workoutType == .cycling,
               workout.powerZoneSeconds != nil,
               heuristicLabeledIds.contains(workout.id) {
                let (intent, confidence) = classifyWorkout(workout)
                results.append((workout.id, intent, confidence, true))
                continue
            }

            // Skip anything already labeled that doesn't qualify for re-classification
            guard !alreadyLabeled else { continue }

            let (intent, confidence) = classifyWorkout(workout)
            results.append((workout.id, intent, confidence, false))
        }

        #if DEBUG
        let newCount = results.filter { !$0.3 }.count
        let reCount  = results.filter { $0.3 }.count
        print("🧠 Classifier: \(newCount) new labels, \(reCount) power-zone upgrades")
        #endif

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
