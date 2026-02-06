//
//  SyncManager.swift
//  HealthAnalytics
//
//  Created by Craig Faist on 2/4/26.
//

import Foundation
import SwiftData
import SwiftUI
import HealthKit
import Combine

@MainActor
class SyncManager: ObservableObject {
    static let shared = SyncManager()
    
    @Published var isSyncing = false
    
    private let healthKitManager = HealthKitManager.shared
    private let stravaManager = StravaManager.shared
    
    private init() {}
    
    func performGlobalSync() async {
        guard !isSyncing else { return }
        isSyncing = true
        
        do {
            let calendar = Calendar.current
            let endDate = Date()
            let startDate = calendar.date(byAdding: .day, value: -120, to: endDate)!
            
            print("🌐 Starting Global Background Sync (120 days)...")
            
            // 1. Concurrent Fetching (Define background tasks)
            async let rhrTask = healthKitManager.fetchRestingHeartRate(startDate: startDate, endDate: endDate)
            async let hrvTask = healthKitManager.fetchHeartRateVariability(startDate: startDate, endDate: endDate)
            async let sleepTask = healthKitManager.fetchSleepDuration(startDate: startDate, endDate: endDate)
            async let workoutsTask = healthKitManager.fetchWorkouts(startDate: startDate, endDate: endDate)
            async let stepsTask = healthKitManager.fetchSteps(startDate: startDate, endDate: endDate)
            async let nutritionTask = healthKitManager.fetchNutrition(startDate: startDate, endDate: endDate)
            
            var strava: [StravaActivity] = []
            if stravaManager.isAuthenticated {
                // Fetch Strava concurrently or linearly depending on your API preference
                strava = (try? await stravaManager.fetchActivities(page: 1, perPage: 150)) ?? []
            }
            
            // 2. Await all results (Fixes "Use of local variable before declaration")
            let fetchedRHR = (try? await rhrTask) ?? []
            let fetchedHRV = (try? await hrvTask) ?? []
            let fetchedSleep = (try? await sleepTask) ?? []
            let fetchedWorkouts = (try? await workoutsTask) ?? []
            let fetchedSteps = await stepsTask
            let fetchedNutrition = await nutritionTask
            
            // 3. Persist to SwiftData
            persistData(
                workouts: fetchedWorkouts,
                strava: strava,
                sleep: fetchedSleep,
                hrv: fetchedHRV,
                rhr: fetchedRHR,
                steps: fetchedSteps,
                nutrition: fetchedNutrition
            )
            
            print("✅ Global Sync Complete")
        } catch {
            print("❌ Global Sync Failed: \(error.localizedDescription)")
        }
        
        isSyncing = false
    }
    
    private func persistData(
        workouts: [WorkoutData],
        strava: [StravaActivity],
        sleep: [HealthDataPoint],
        hrv: [HealthDataPoint],
        rhr: [HealthDataPoint],
        steps: [HealthDataPoint],
        nutrition: [DailyNutrition]
    ) {
        let context = HealthDataContainer.shared.mainContext
        
        // Persist Nutrition
        for entry in nutrition {
            context.insert(StoredNutrition(
                date: entry.date,
                calories: entry.totalCalories,
                protein: entry.totalProtein,
                carbs: entry.totalCarbs,
                fat: entry.totalFat           
            ))
        }
        
        // Persist Health Metrics (including Steps)
        let metrics = [(hrv, "HRV"), (rhr, "RHR"), (sleep, "Sleep"), (steps, "Steps")]
        for (points, type) in metrics {
            for point in points {
                context.insert(StoredHealthMetric(type: type, date: point.date, value: point.value))
            }
        }
        
        // Persist Workouts (Strava and HealthKit)
        for workout in workouts {
            context.insert(StoredWorkout(
                id: workout.id.uuidString,
                type: workout.workoutType,
                startDate: workout.startDate,
                duration: workout.duration,
                distance: workout.totalDistance,
                power: workout.averagePower,
                energy: workout.totalEnergyBurned,
                source: workout.source.rawValue
            ))
        }
        
        for activity in strava {
            guard let date = activity.startDateFormatted else { continue }
            
            // Strava typically provides 'calories' only for certain activity types
            // or uses 'kilojoules'. We'll use kilojoules as the energy source.
            let stravaEnergy = activity.kilojoules
            
            context.insert(StoredWorkout(
                id: String(activity.id),
                type: activity.type == "Run" ? .running : .cycling,
                startDate: date,
                duration: Double(activity.elapsedTime),
                distance: activity.distance,
                power: activity.averageWatts,
                energy: stravaEnergy,
                source: "Strava"
            ))
        }
        
        // Single batch save
        try? context.save()
    }
    
    func resetAllData() async {
        let context = HealthDataContainer.shared.mainContext
        try? context.delete(model: StoredWorkout.self)
        try? context.save()
        print("🗑️ All workouts deleted. Starting fresh sync...")
        await performGlobalSync()
    }
}
