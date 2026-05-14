//
//  SmartRoutingEngine.swift
//  HealthAnalytics
//
//  Phase 4: Structured Ontology & Smart Routing
//

import Foundation

struct SmartRoutingEngine {
    
    /// Returns a readiness multiplier (0.0 to 1.0) for a given activity type based on active injury memories.
    static func readinessMultiplier(for activity: String, memories: [CoachMemoryNote]) -> Double {
        let activeInjuries = memories.filter { $0.isCurrentlyActive && $0.category.lowercased() == "injury" }
        if activeInjuries.isEmpty { return 1.0 }
        
        var multiplier = 1.0
        let activityLower = activity.lowercased()
        
        for injury in activeInjuries {
            guard let region = injury.anatomicalRegion?.lowercased() else { continue }
            
            // Phase 4 specific rules:
            if region.contains("knee") || region.contains("lower body") {
                if activityLower.contains("run") || activityLower.contains("running") {
                    multiplier = min(multiplier, 0.0) // Zero out Running
                }
                // Keep Upper Body Strength at 100%
            }
            
            if region.contains("shoulder") || region.contains("upper body") {
                if activityLower.contains("upper body") || activityLower.contains("swim") {
                    multiplier = min(multiplier, 0.0)
                }
            }
            
            if region.contains("back") || region.contains("core") {
                if activityLower.contains("rowing") || activityLower.contains("deadlift") {
                    multiplier = min(multiplier, 0.0)
                }
            }
        }
        
        return multiplier
    }
    
    /// Applies smart routing filters to a list of target activities/zones
    static func filterRecommendations(targets: [String], memories: [CoachMemoryNote]) -> [String] {
        return targets.filter { activity in
            readinessMultiplier(for: activity, memories: memories) > 0.0
        }
    }
    
    /// Calculates activity-specific readiness based on the overall readiness score and active injuries.
    static func generateActivityReadiness(baseScore: Int, memories: [CoachMemoryNote]) -> [String: Int] {
        let defaultActivities = ["Running", "Cycling", "Swimming", "Upper Body Strength", "Lower Body Strength", "Yoga"]
        var activityScores: [String: Int] = [:]
        
        for activity in defaultActivities {
            let multiplier = readinessMultiplier(for: activity, memories: memories)
            activityScores[activity] = Int(Double(baseScore) * multiplier)
        }
        
        return activityScores
    }
}
