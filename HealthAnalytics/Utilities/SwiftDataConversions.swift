//
//  SwiftDataConversions.swift
//  HealthAnalytics
//
//  Conversion extensions for SwiftData models
//

import Foundation
import HealthKit

// MARK: - WorkoutData Conversion

extension WorkoutData {
    init(from stored: StoredWorkout) {
        self.init(
            id: UUID(uuidString: stored.id) ?? UUID(),
            title: stored.title,
            workoutType: stored.workoutType,
            startDate: stored.startDate,
            endDate: stored.startDate.addingTimeInterval(stored.duration),
            duration: stored.duration,
            totalEnergyBurned: stored.totalEnergyBurned,
            totalDistance: stored.distance,
            averagePower: stored.averagePower,
            normalizedPower: stored.normalizedPower,
            powerZoneSeconds: stored.powerZoneSeconds,
            averageHeartRate: stored.averageHeartRate,
            source: stored.source.lowercased() == "strava" ? .strava : (stored.source.lowercased() == "applewatch" ? .appleWatch : .other)
        )
    }
}

// MARK: - DailyNutrition Conversion

extension DailyNutrition {
    init(from stored: StoredNutrition) {
        self.init(
            date: stored.date,
            totalCalories: stored.calories,
            totalProtein: stored.protein,
            totalCarbs: stored.carbs,
            totalFat: stored.fat,
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
