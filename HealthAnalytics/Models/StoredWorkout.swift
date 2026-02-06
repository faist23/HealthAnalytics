//
//  StoredWorkout.swift
//  HealthAnalytics
//
//  Created by Craig Faist on 2/4/26.
//

import Foundation
import SwiftData
import HealthKit

@Model
final class StoredWorkout {
    @Attribute(.unique) var id: String // Strava ID or HealthKit UUID
    var workoutTypeInt: Int
    var startDate: Date
    var duration: TimeInterval
    var distance: Double?
    var averagePower: Double?
    var totalEnergyBurned: Double?
    var source: String
    
    init(id: String, type: HKWorkoutActivityType, startDate: Date, duration: TimeInterval, distance: Double?, power: Double?, energy: Double?, source: String) {
        self.id = id
        self.workoutTypeInt = Int(type.rawValue)
        self.startDate = startDate
        self.duration = duration
        self.distance = distance
        self.averagePower = power
        self.totalEnergyBurned = energy
        self.source = source
    }
    
    var workoutType: HKWorkoutActivityType {
        HKWorkoutActivityType(rawValue: UInt(workoutTypeInt)) ?? .other
    }
}

@Model
final class StoredHealthMetric {
    @Attribute(.unique) var uniqueKey: String // "type_dateString" to prevent duplicates
    var type: String // "HRV", "RHR", "Sleep", "Steps", "ActiveEnergy"
    var date: Date
    var value: Double
    
    init(type: String, date: Date, value: Double) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        self.uniqueKey = "\(type)_\(formatter.string(from: date))"
        self.type = type
        self.date = date
        self.value = value
    }
}

@Model
final class StoredNutrition {
    @Attribute(.unique) var dateString: String // "yyyy-MM-dd"
    var date: Date
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    
    init(date: Date, calories: Double, protein: Double, carbs: Double, fat: Double) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        self.dateString = formatter.string(from: date)
        self.date = date
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
    }
}
