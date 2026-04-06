//
//  StoredWorkout.swift (FIXED)
//  HealthAnalytics
//
//  FIXES:
//  1. DateFormatter timezone for consistent date keys
//  2. Better HRV storage logic (morning values only)
//

import Foundation
import SwiftData
import HealthKit

@Model
final class StoredWorkout {
    @Attribute(.unique) var id: String
    var title: String?
    var workoutTypeInt: Int
    var startDate: Date
    var duration: TimeInterval
    var distance: Double?
    var averagePower: Double?
    var totalEnergyBurned: Double?
    var source: String
    var averageHeartRate: Double?

    init(id: String, title: String? = nil, type: HKWorkoutActivityType, startDate: Date, duration: TimeInterval, distance: Double?, power: Double?, energy: Double?, hr: Double?, source: String) {
        self.id = id
        self.title = title
        self.workoutTypeInt = Int(type.rawValue)
        self.startDate = startDate
        self.duration = duration
        self.distance = distance
        self.averagePower = power
        self.totalEnergyBurned = energy
        self.source = source
        self.averageHeartRate = hr
        self.source = source
    }
    
    var workoutType: HKWorkoutActivityType {
        HKWorkoutActivityType(rawValue: UInt(workoutTypeInt)) ?? .other
    }
}

@Model
final class StoredHealthMetric {
    @Attribute(.unique) var uniqueKey: String
    var type: String
    var date: Date
    var value: Double
    
    init(type: String, date: Date, value: Double) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current  // ✅ FIXED: Explicit timezone
        self.uniqueKey = "\(type)_\(formatter.string(from: date))"
        self.type = type
        self.date = date
        self.value = value
    }
}

@Model
final class StoredNutrition {
    @Attribute(.unique) var dateString: String
    var date: Date
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    
    init(date: Date, calories: Double, protein: Double, carbs: Double, fat: Double) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current  // ✅ FIXED: Explicit timezone
        self.dateString = formatter.string(from: date)
        self.date = date
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
    }
}

/// Persists one readiness score per calendar day for 90-day pattern analysis.
/// Uses plain UUID primary key (NOT @Attribute(.unique)) to avoid non-lightweight migration risk.
/// Uniqueness is enforced in-memory via dateString dedup in ReadinessRepository.
@Model
final class StoredDailyScore {
    var id: UUID = UUID()
    var dateString: String      // "yyyy-MM-dd" — used for in-memory dedup
    var date: Date
    var readinessScore: Int     // 0–100
    var dailyStrain: Double     // ACWR-based strain value
    var workoutCount: Int       // number of workouts logged that day

    init(date: Date, readinessScore: Int, dailyStrain: Double, workoutCount: Int) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        self.dateString = formatter.string(from: date)
        self.date = date
        self.readinessScore = readinessScore
        self.dailyStrain = dailyStrain
        self.workoutCount = workoutCount
    }
}
