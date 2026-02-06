//
//  DomainMapping.swift
//  HealthAnalytics
//
//  Created for HealthAnalytics
//

import Foundation
import SwiftData
import HealthKit

// 1. Map StoredWorkout -> WorkoutData
extension StoredWorkout {
    func toWorkoutData() -> WorkoutData {
        // Calculate endDate from start + duration
        let end = self.startDate.addingTimeInterval(self.duration)
        
        return WorkoutData(
            workoutType: self.workoutType,
            startDate: self.startDate,
            endDate: end,
            duration: self.duration,
            totalEnergyBurned: self.totalEnergyBurned,
            totalDistance: self.distance,
            averagePower: self.averagePower,
            source: WorkoutSource(rawValue: self.source) ?? .other
//            source: self.source == "Strava" ? .strava : .appleWatch
        )
    }
}

// 2. Map StoredHealthMetric -> HealthDataPoint
extension StoredHealthMetric {
    func toHealthDataPoint() -> HealthDataPoint {
        HealthDataPoint(date: self.date, value: self.value)
    }
}

// 3. Map StoredNutrition -> DailyNutrition
extension StoredNutrition {
    func toDailyNutrition() -> DailyNutrition {
        DailyNutrition(
            date: self.date,
            totalCalories: self.calories,
            totalProtein: self.protein,
            totalCarbs: self.carbs,
            totalFat: self.fat,
            totalFiber: nil,
            totalSugar: nil,
            totalWater: nil,
            breakfast: nil,
            lunch: nil,
            dinner: nil,
            snacks: nil
        )
    }
}
