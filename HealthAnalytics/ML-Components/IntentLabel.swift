//
//  IntentLabel.swift
//  HealthAnalytics
//
//  Activity Intent Classification Model
//  Stores ML-generated or manually-assigned intent labels for workouts
//

import Foundation
import SwiftData

/// The primary intent categories for workouts
enum ActivityIntent: String, Codable, CaseIterable {
    case race = "Race/PR Attempt"
    case tempo = "Tempo/Threshold"
    case intervals = "Intervals/Speed Work"
    case easy = "Easy/Recovery"
    case long = "Long Run/Endurance"
    case casualWalk = "Casual Walk"
    case strength = "Strength Training"
    case other = "Other/Unclassified"
    
    var emoji: String {
        switch self {
        case .race: return "🏆"
        case .tempo: return "⚡️"
        case .intervals: return "🔥"
        case .easy: return "😌"
        case .long: return "🎯"
        case .casualWalk: return "🚶"
        case .strength: return "💪"
        case .other: return "❓"
        }
    }
    
    var color: String {
        switch self {
        case .race: return "red"
        case .tempo: return "orange"
        case .intervals: return "purple"
        case .easy: return "green"
        case .long: return "blue"
        case .casualWalk: return "gray"
        case .strength: return "brown"
        case .other: return "secondary"
        }
    }
    
    var description: String {
        switch self {
        case .race: 
            return "High sustained effort (80-95% max HR), consistent pacing, goal-oriented"
        case .tempo:
            return "Sustained moderate-high effort (75-85% max HR), steady pacing"
        case .intervals:
            return "High variability in pace and HR, clear work/rest patterns"
        case .easy:
            return "Low-moderate effort (60-75% max HR), conversational pace"
        case .long:
            return "Extended duration (90+ min), steady moderate effort"
        case .casualWalk:
            return "Low effort, variable pacing, often social/transportation"
        case .strength:
            return "Resistance training, core work, functional movement"
        case .other:
            return "Unclassified or insufficient data"
        }
    }
}

/// SwiftData model to store intent labels
@Model
final class StoredIntentLabel {
    @Attribute(.unique) var workoutId: String
    var intentRawValue: String
    var confidence: Double  // 0.0 to 1.0
    var source: LabelSource
    var createdAt: Date
    var lastUpdated: Date
    
    enum LabelSource: String, Codable {
        case manual = "Manual"
        case mlModel = "ML Model"
        case heuristic = "Rule-based"
    }
    
    init(workoutId: String, intent: ActivityIntent, confidence: Double, source: LabelSource) {
        self.workoutId = workoutId
        self.intentRawValue = intent.rawValue
        self.confidence = confidence
        self.source = source
        self.createdAt = Date()
        self.lastUpdated = Date()
    }
    
    var intent: ActivityIntent {
        ActivityIntent(rawValue: intentRawValue) ?? .other
    }
    
    func update(intent: ActivityIntent, confidence: Double) {
        self.intentRawValue = intent.rawValue
        self.confidence = confidence
        self.lastUpdated = Date()
    }
}

/// Extension to StoredWorkout to easily access intent
extension StoredWorkout {
    // Note: We're NOT modifying the StoredWorkout @Model itself
    // Instead, we'll use a separate lookup table (StoredIntentLabel)
    // This keeps your existing model intact
}
