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
            async let weightTask = healthKitManager.fetchBodyMass(startDate: startDate, endDate: endDate)
            async let nutritionTask = healthKitManager.fetchNutrition(startDate: startDate, endDate: endDate)
            
            // 2. Fetch Strava data
            var strava: [StravaActivity] = []
            if stravaManager.isAuthenticated {
                let page1 = (try? await stravaManager.fetchActivities(page: 1, perPage: 100)) ?? []
                let page2 = (try? await stravaManager.fetchActivities(page: 2, perPage: 100)) ?? []
                strava = page1 + page2
            }
            
            let stravaSafeData: [StravaImportData] = strava.compactMap { (activity: StravaActivity) -> StravaImportData? in // Explicitly allow nil
                guard let date = activity.startDateFormatted else { return nil }
                
                // Energy Fix: Estimate calories if the API returns 0.0
                // Based on your console debug, Strava is sending 0.0 for calories in the summary list.
                var energy = activity.calories ?? 0
                if energy == 0, let kj = activity.kilojoules, kj > 0 {
                    energy = kj // 1:1 approximation for cycling
                } else if energy == 0, let hr = activity.averageHeartrate, hr > 0 {
                    // Fallback estimate for activities like "Shovel Snow"
                    let minutes = Double(activity.elapsedTime) / 60.0
                    energy = minutes * (hr > 120 ? 10.0 : 5.0)
                }
                
                // Map the activity type properly so the Matcher can find duplicates
                let mappedType: HKWorkoutActivityType
                switch activity.type {
                case "Run": mappedType = .running
                case "Ride", "VirtualRide": mappedType = .cycling
                case "WeightTraining": mappedType = .traditionalStrengthTraining
                case "Workout": mappedType = .other
                default: mappedType = .other
                }
                
                return StravaImportData(
                    id: String(activity.id),
                    title: activity.name,
                    workoutType: mappedType,
                    startDate: date,
                    duration: Double(activity.elapsedTime),
                    distance: activity.distance,
                    power: activity.averageWatts,
                    energy: energy,
                    averageHeartRate: activity.averageHeartrate
                )
            }
            
            // 3. Await results
            let fetchedRHR = (try? await rhrTask) ?? []
            let fetchedHRV = (try? await hrvTask) ?? []
            let fetchedSleep = (try? await sleepTask) ?? []
            let fetchedWorkouts = (try? await workoutsTask) ?? []
            let fetchedSteps = await stepsTask
            let fetchedWeight = (try? await weightTask) ?? []
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
                weight: fetchedWeight,
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
        weight: [HealthDataPoint],
        nutrition: [DailyNutrition]
    ) {
        deleteAll()
        
        // 1. Metrics (Added Weight to the list)
        let metrics = [
            (hrv, "HRV"),
            (rhr, "RHR"),
            (sleep, "Sleep"),
            (steps, "Steps"),
            (weight, "Weight") 
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
        
        // Track which Strava IDs we've used so we don't save them twice
        var matchedStravaIds = Set<String>()
        
        for hkWorkout in workouts {
            // Use the Matcher!
            if let match = WorkoutMatcher.findMatch(for: hkWorkout, in: strava) {
                // MATCH FOUND: Save the Strava version (better metadata/titles)
                modelContext.insert(StoredWorkout(
                    id: match.id,
                    title: match.title,
                    type: match.workoutType,
                    startDate: match.startDate,
                    duration: match.duration,
                    distance: match.distance,
                    power: match.power,
                    energy: match.energy,
                    hr: match.averageHeartRate,
                    source: "Strava"
                ))
                matchedStravaIds.insert(match.id)
            } else {
                // NO MATCH: Save the Apple Health version
                modelContext.insert(StoredWorkout(
                    id: hkWorkout.id.uuidString,
                    title: nil,
                    type: hkWorkout.workoutType,
                    startDate: hkWorkout.startDate,
                    duration: hkWorkout.duration,
                    distance: hkWorkout.totalDistance,
                    power: hkWorkout.averagePower,
                    energy: hkWorkout.totalEnergyBurned,
                    hr: hkWorkout.averageHeartRate,
                    source: hkWorkout.source.rawValue
                ))
            }
        }
        
        // Finally, save Strava activities that had no Apple Health counterpart
        for activity in strava where !matchedStravaIds.contains(activity.id) {
            modelContext.insert(StoredWorkout(
                id: activity.id,
                title: activity.title,
                type: activity.workoutType,
                startDate: activity.startDate,
                duration: activity.duration,
                distance: activity.distance,
                power: activity.power,
                energy: activity.energy,
                hr: activity.averageHeartRate,
                source: "Strava"
            ))
        }
        
        try? modelContext.save()
        print("💾 Batch save completed successfully.")
    }
}
