//
//  SyncManager.swift
//  HealthAnalytics
//
//  Created by Craig Faist.
//

import Foundation
import SwiftData
import SwiftUI
import HealthKit
import Combine

struct StravaImportData: Sendable {
    let id: String
    let title: String
    let workoutType: HKWorkoutActivityType
    let startDate: Date
    let duration: Double
    let distance: Double?
    let power: Double?
    let energy: Double?
}

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
            let startDate = calendar.date(byAdding: .day, value: -365, to: endDate)!
            
            print("🌐 Starting Global Background Sync (365 days)...")
            
            // 1. Fetch data concurrently
            async let rhrTask = healthKitManager.fetchRestingHeartRate(startDate: startDate, endDate: endDate)
            async let hrvTask = healthKitManager.fetchHeartRateVariability(startDate: startDate, endDate: endDate)
            async let sleepTask = healthKitManager.fetchSleepDuration(startDate: startDate, endDate: endDate)
            async let workoutsTask = healthKitManager.fetchWorkouts(startDate: startDate, endDate: endDate)
            async let stepsTask = healthKitManager.fetchSteps(startDate: startDate, endDate: endDate)
            async let weightTask = healthKitManager.fetchBodyMass(startDate: startDate, endDate: endDate) // 🟢 NEW
            async let nutritionTask = healthKitManager.fetchNutrition(startDate: startDate, endDate: endDate)
            
            // 2. Fetch Strava data
            var strava: [StravaActivity] = []
            if stravaManager.isAuthenticated {
                let page1 = (try? await stravaManager.fetchActivities(page: 1, perPage: 100)) ?? []
                let page2 = (try? await stravaManager.fetchActivities(page: 2, perPage: 100)) ?? []
                strava = page1 + page2
            }
            
            let stravaSafeData: [StravaImportData] = strava.compactMap { activity in
                guard let date = activity.startDateFormatted else { return nil }
                return StravaImportData(
                    id: String(activity.id),
                    title: activity.name,
                    workoutType: activity.type == "Run" ? .running : .cycling,
                    startDate: date,
                    duration: Double(activity.elapsedTime),
                    distance: activity.distance,
                    power: activity.averageWatts,
                    energy: activity.kilojoules
                )
            }
            
            // 3. Await results
            let fetchedRHR = (try? await rhrTask) ?? []
            let fetchedHRV = (try? await hrvTask) ?? []
            let fetchedSleep = (try? await sleepTask) ?? []
            let fetchedWorkouts = (try? await workoutsTask) ?? []
            let fetchedSteps = await stepsTask
            let fetchedWeight = (try? await weightTask) ?? [] // 🟢 NEW
            let fetchedNutrition = await nutritionTask
            
            // 4. Persist safely
            let container = HealthDataContainer.shared
            let dataHandler = DataPersistenceActor(modelContainer: container)
            
            await dataHandler.saveBatch(
                workouts: fetchedWorkouts,
                strava: stravaSafeData,
                sleep: fetchedSleep,
                hrv: fetchedHRV,
                rhr: fetchedRHR,
                steps: fetchedSteps,
                weight: fetchedWeight, // 🟢 NEW
                nutrition: fetchedNutrition
            )
            
            print("✅ Global Sync Complete")
        } catch {
            print("❌ Global Sync Failed: \(error.localizedDescription)")
        }
        
        isSyncing = false
    }
    
    func resetAllData() async {
        let container = HealthDataContainer.shared
        let dataHandler = DataPersistenceActor(modelContainer: container)
        await dataHandler.deleteAll()
        
        print("🗑️ All data deleted. Starting fresh sync...")
        await performGlobalSync()
    }
}

@ModelActor
actor DataPersistenceActor {
    
    func deleteAll() {
        try? modelContext.delete(model: StoredWorkout.self)
        try? modelContext.delete(model: StoredHealthMetric.self)
        try? modelContext.delete(model: StoredNutrition.self)
        try? modelContext.save()
    }
    
    func saveBatch(
        workouts: [WorkoutData],
        strava: [StravaImportData],
        sleep: [HealthDataPoint],
        hrv: [HealthDataPoint],
        rhr: [HealthDataPoint],
        steps: [HealthDataPoint],
        weight: [HealthDataPoint], // 🟢 NEW
        nutrition: [DailyNutrition]
    ) {
        deleteAll()
        
        // 1. Metrics (Added Weight to the list)
        let metrics = [
            (hrv, "HRV"),
            (rhr, "RHR"),
            (sleep, "Sleep"),
            (steps, "Steps"),
            (weight, "Weight") // 🟢 NEW
        ]
        
        for (points, type) in metrics {
            for point in points {
                modelContext.insert(StoredHealthMetric(type: type, date: point.date, value: point.value))
            }
        }
        
        // 2. Nutrition
        for entry in nutrition {
            modelContext.insert(StoredNutrition(
                date: entry.date,
                calories: entry.totalCalories,
                protein: entry.totalProtein,
                carbs: entry.totalCarbs,
                fat: entry.totalFat
            ))
        }
        
        // 3. Workouts (HealthKit)
        for workout in workouts {
            modelContext.insert(StoredWorkout(
                id: workout.id.uuidString,
                title: nil,
                type: workout.workoutType,
                startDate: workout.startDate,
                duration: workout.duration,
                distance: workout.totalDistance,
                power: workout.averagePower,
                energy: workout.totalEnergyBurned,
                source: workout.source.rawValue
            ))
        }
        
        // 4. Workouts (Strava)
        for activity in strava {
            modelContext.insert(StoredWorkout(
                id: activity.id,
                title: activity.title,
                type: activity.workoutType,
                startDate: activity.startDate,
                duration: activity.duration,
                distance: activity.distance,
                power: activity.power,
                energy: activity.energy,
                source: "Strava"
            ))
        }
        
        try? modelContext.save()
        print("💾 Batch save completed successfully.")
    }
}
