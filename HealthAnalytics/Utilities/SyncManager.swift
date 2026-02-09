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
    @AppStorage("lastSyncDate") private var lastSyncTimestamp: Double = 0
    
    var lastSyncDate: Date? {
        get { lastSyncTimestamp == 0 ? nil : Date(timeIntervalSince1970: lastSyncTimestamp) }
        set { lastSyncTimestamp = newValue?.timeIntervalSince1970 ?? 0 }
    }
    
    @Published var isSyncing = false
    @Published var syncProgress: String = "" // For athlete transparency
    @Published var isBackfillingHistory: Bool = false
    
    private let healthKitManager = HealthKitManager.shared
    private let stravaManager = StravaManager.shared
    
    private init() {}
    
    func performGlobalSync() async {
        // Check if we synced recently (e.g., within last 6 hours / 21600 seconds)
        if let last = lastSyncDate, Date().timeIntervalSince(last) < 21600 {
            print("🛡️ Sync Guard: Data is fresh (last sync \(Int(Date().timeIntervalSince(last)/60))m ago). Skipping API calls.")
            return
        }
        
        guard !isSyncing else { return }
        isSyncing = true
        
        let container = HealthDataContainer.shared
        let dataHandler = DataPersistenceActor(modelContainer: container)
        
        do {
            // --- PHASE 1: RECENT YEAR & STRAVA (UI UPDATES PERMITTED) ---
            let calendar = Calendar.current
            let endDate = Date()
            let startDate = calendar.date(byAdding: .day, value: -365, to: endDate)!
            
            print("🌐 Phase 1: Syncing recent year and Strava...")
            
            // Concurrent fetches
            async let rhrTask = healthKitManager.fetchRestingHeartRate(startDate: startDate, endDate: endDate)
            async let hrvTask = healthKitManager.fetchHeartRateVariability(startDate: startDate, endDate: endDate)
            async let sleepTask = healthKitManager.fetchSleepDuration(startDate: startDate, endDate: endDate)
            async let workoutsTask = healthKitManager.fetchWorkouts(startDate: startDate, endDate: endDate)
            async let stepsTask = healthKitManager.fetchSteps(startDate: startDate, endDate: endDate)
            async let weightTask = healthKitManager.fetchBodyMass(startDate: startDate, endDate: endDate)
            async let nutritionTask = healthKitManager.fetchNutrition(startDate: startDate, endDate: endDate)
            
            // Paginated Strava Fetch
            var allStravaActivities: [StravaActivity] = []
            if stravaManager.isAuthenticated {
                var page = 1
                var hasMore = true
                while hasMore {
                    print("🚴 Fetching Strava page \(page)...")
                    if let activities = try? await stravaManager.fetchActivities(page: page, perPage: 100), !activities.isEmpty {
                        allStravaActivities.append(contentsOf: activities)
                        page += 1
                        try? await Task.sleep(nanoseconds: 50_000_000)
                    } else {
                        hasMore = false
                    }
                    if page > 50 { hasMore = false }
                }
            }
            
            let stravaSafeData: [StravaImportData] = allStravaActivities.compactMap { activity in
                guard let date = activity.startDateFormatted else { return nil }
                var energy = activity.calories ?? 0
                if energy == 0, let kj = activity.kilojoules, kj > 0 { energy = kj }
                return StravaImportData(
                    id: String(activity.id),
                    title: activity.name,
                    workoutType: mapStravaType(activity.type),
                    startDate: date,
                    duration: Double(activity.elapsedTime),
                    distance: activity.distance,
                    power: activity.averageWatts,
                    energy: energy,
                    averageHeartRate: activity.averageHeartrate
                )
            }
            
            // Await HealthKit
            let fetchedRHR = (try? await rhrTask) ?? []
            let fetchedHRV = (try? await hrvTask) ?? []
            let fetchedSleep = (try? await sleepTask) ?? []
            let fetchedWorkouts = (try? await workoutsTask) ?? []
            let fetchedSteps = await stepsTask
            let fetchedWeight = (try? await weightTask) ?? []
            let fetchedNutrition = await nutritionTask
            
            // Save current year (This updates the UI)
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
            
            // --- PHASE 2: 10-YEAR DEEP BACKFILL (UI UPDATES SILENCED) ---
            print("🕰️ Phase 2: Starting background historical backfill...")
            
            // TRIGGER SILENCE: Set this to true so Views can stop querying
            // to avoid the PermanentID remapping errors.
            await MainActor.run { self.isBackfillingHistory = true }
            
            let currentYear = calendar.component(.year, from: Date())
            for year in (currentYear-10..<currentYear-1).reversed() {
                print("⏳ Processing year \(year)...")
                let yearlyData = try await healthKitManager.fetchYearlySnapshot(year: year)
                
                // Append and obtainPermanentIDs (from the previous step's appendBatch fix)
                await dataHandler.appendBatch(
                    workouts: yearlyData.workouts,
                    sleep: yearlyData.sleep,
                    hrv: yearlyData.hrv,
                    rhr: yearlyData.rhr,
                    nutrition: yearlyData.nutrition
                )
                
                // Critical pause to allow Main thread to catch up and WAL to checkpoint
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
            
            // END SILENCE
            await MainActor.run {
                self.isBackfillingHistory = false 
                self.lastSyncDate = Date() // CRITICAL: Save the date so it doesn't run again immediately
            }
            
            print("✅ Global 10-Year Sync Complete")
        } catch {
            print("❌ Global Sync Failed: \(error.localizedDescription)")
            await MainActor.run { self.isBackfillingHistory = false }
        }
        
        await MainActor.run {
            self.lastSyncDate = Date()
            self.isSyncing = false
        }
    }
    
    // Helper for cleaner mapping
    private func mapStravaType(_ type: String) -> HKWorkoutActivityType {
        switch type {
        case "Run": return .running
        case "Ride", "VirtualRide": return .cycling
        case "WeightTraining": return .traditionalStrengthTraining
        default: return .other
        }
    }
        
    func performFullHistorySync() async {
        // Phase 1: Immediate Sync (Last 30 Days)
        // This ensures your current Readiness and Dashboards update instantly.
        await syncRange(from: .daysAgo(30), to: .now)
        
        // Phase 2: Historical Backfill (The last 10 years)
        // We process this in yearly chunks to manage memory and SwiftData performance.
        let currentYear = Calendar.current.component(.year, from: Date())
        for year in (currentYear-10..<currentYear).reversed() {
            await syncYearlyBatch(year: year)
            // Allow the UI to breathe between batches
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
    }

    func resetAllData() async {
        let container = HealthDataContainer.shared
        let dataHandler = DataPersistenceActor(modelContainer: container)

        self.lastSyncDate = nil
        await dataHandler.deleteAll()
        
        print("🗑️ All data deleted. Starting fresh sync...")
        await performGlobalSync()
    }
    
    private func syncRange(from: Date, to: Date) async {
        // This wraps your existing fetch logic for a specific window
        do {
            let workouts = try await healthKitManager.fetchWorkouts(startDate: from, endDate: to)
            let sleep = try await healthKitManager.fetchSleepDuration(startDate: from, endDate: to)
            let hrv = try await healthKitManager.fetchHeartRateVariability(startDate: from, endDate: to)
            let rhr = try await healthKitManager.fetchRestingHeartRate(startDate: from, endDate: to)
            
            let dataHandler = DataPersistenceActor(modelContainer: HealthDataContainer.shared)
            await dataHandler.appendBatch(workouts: workouts, sleep: sleep, hrv: hrv, rhr: rhr, nutrition: [])
        } catch {
            print("Range sync error: \(error)")
        }
    }

    private func syncYearlyBatch(year: Int) async {
        do {
            let data = try await healthKitManager.fetchYearlySnapshot(year: year)
            let dataHandler = DataPersistenceActor(modelContainer: HealthDataContainer.shared)
            await dataHandler.appendBatch(
                workouts: data.workouts,
                sleep: data.sleep,
                hrv: data.hrv,
                rhr: data.rhr,
                nutrition: data.nutrition
            )
        } catch {
            print("Yearly batch error for \(year): \(error)")
        }
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
    
    func appendBatch(
        workouts: [WorkoutData],
        sleep: [HealthDataPoint],
        hrv: [HealthDataPoint],
        rhr: [HealthDataPoint],
        nutrition: [DailyNutrition]
    ) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        // 1. Upsert Workouts
        for workout in workouts {
            let workoutID = workout.id.uuidString
            let descriptor = FetchDescriptor<StoredWorkout>(predicate: #Predicate { $0.id == workoutID })
            
            if let existing = try? modelContext.fetch(descriptor).first {
                existing.averagePower = workout.averagePower
                existing.averageHeartRate = workout.averageHeartRate
                existing.totalEnergyBurned = workout.totalEnergyBurned
            } else {
                modelContext.insert(StoredWorkout(
                    id: workoutID,
                    title: nil,
                    type: workout.workoutType,
                    startDate: workout.startDate,
                    duration: workout.duration,
                    distance: workout.totalDistance,
                    power: workout.averagePower,
                    energy: workout.totalEnergyBurned,
                    hr: workout.averageHeartRate,
                    source: workout.source.rawValue
                ))
            }
        }
        
        // 2. Upsert Metrics (HRV, RHR, Sleep)
        let metrics = [(hrv, "HRV"), (rhr, "RHR"), (sleep, "Sleep")]
        for (points, type) in metrics {
            for point in points {
                let key = "\(type)_\(formatter.string(from: point.date))"
                let metricDescriptor = FetchDescriptor<StoredHealthMetric>(predicate: #Predicate { $0.uniqueKey == key })
                
                if let existingMetric = try? modelContext.fetch(metricDescriptor).first {
                    existingMetric.value = point.value
                } else {
                    modelContext.insert(StoredHealthMetric(type: type, date: point.date, value: point.value))
                }
            }
        }
        
        // 3. Upsert Nutrition
        for entry in nutrition {
            let dateString = formatter.string(from: entry.date)
            let nutritionDescriptor = FetchDescriptor<StoredNutrition>(predicate: #Predicate { $0.dateString == dateString })
            
            if let existingNutrition = try? modelContext.fetch(nutritionDescriptor).first {
                existingNutrition.calories = entry.totalCalories
                existingNutrition.carbs = entry.totalCarbs
                existingNutrition.protein = entry.totalProtein
                existingNutrition.fat = entry.totalFat
            } else {
                modelContext.insert(StoredNutrition(
                    date: entry.date,
                    calories: entry.totalCalories,
                    protein: entry.totalProtein,
                    carbs: entry.totalCarbs,
                    fat: entry.totalFat
                ))
            }
        }
        
        // 4. THE STABILITY FIX: Save and Sync Contexts
        if modelContext.hasChanges {
            do {
                // First: Save on background thread to establish permanent IDs in the store
                try modelContext.save()
                
                // Second: Clear the background context memory for this batch
                modelContext.processPendingChanges()
                
                // Third: Signal the Main Actor to reconcile its own IDs.
                // This prevents the "remapped to temporary identifier" error in the UI.
                Task { @MainActor in
                    HealthDataContainer.shared.mainContext.processPendingChanges()
                }
                
                print("💾 Batch processed: Saved and synchronized to Main Context.")
            } catch {
                print("⚠️ SwiftData Batch Save Error: \(error.localizedDescription)")
            }
        }
    }
}
