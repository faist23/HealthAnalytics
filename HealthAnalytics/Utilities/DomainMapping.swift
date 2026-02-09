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
            id: UUID(uuidString: self.id) ?? UUID(),
            title: self.title, // Pass the custom title (e.g., "Shovel Snow")
            workoutType: self.workoutType,
            startDate: self.startDate,
            endDate: end,
            duration: self.duration,
            totalEnergyBurned: self.totalEnergyBurned,
            totalDistance: self.distance,
            averagePower: self.averagePower,
            averageHeartRate: self.averageHeartRate, 
            source: WorkoutSource(rawValue: self.source) ?? .other
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

extension Date {
    static var now: Date { Date() }
    
    static func daysAgo(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
    }
    
    static func monthsAgo(_ months: Int) -> Date {
        Calendar.current.date(byAdding: .month, value: -months, to: Date()) ?? Date()
    }
    
    static func yearsAgo(_ years: Int) -> Date {
        Calendar.current.date(byAdding: .year, value: -years, to: Date()) ?? Date()
    }
}
