//
//  SyncManager.swift (MIGRATION-AWARE VERSION)
//  HealthAnalytics
//
//  Handles both old metric names (lowercase) and new (capitalized)
//  This allows smooth migration without losing existing data
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
    @AppStorage("hasCompletedHistoricalBackfill") private var hasCompletedHistoricalBackfill: Bool = false
    @AppStorage("hasMigratedMetricNames") private var hasMigratedMetricNames: Bool = false
    
    var lastSyncDate: Date? {
        get { lastSyncTimestamp == 0 ? nil : Date(timeIntervalSince1970: lastSyncTimestamp) }
        set { lastSyncTimestamp = newValue?.timeIntervalSince1970 ?? 0 }
    }
    
    @Published var isSyncing = false
    @Published var syncProgress: String = ""
    @Published var isBackfillingHistory: Bool = false
    @Published var backfillProgress: Double = 0
    
    private let healthKitManager = HealthKitManager.shared
    private let stravaManager = StravaManager.shared
    
    private init() {}
    
    // MARK: - Smart Sync Entry Point
    
    /// Intelligently syncs only what's needed
    func performSmartSync() async {
        // Prevent redundant syncs
        if let last = lastSyncDate, Date().timeIntervalSince(last) < 3600 {
            print("🛡️ Sync Guard: Synced \(Int(Date().timeIntervalSince(last)/60))m ago. Skipping.")
            return
        }
        
        guard !isSyncing else {
            print("⚠️ Sync already in progress")
            return
        }
        
        isSyncing = true
        
        let container = HealthDataContainer.shared
        let dataHandler = DataPersistenceActor(modelContainer: container)
        
        do {
            // MIGRATION: Update old metric type names to new standardized names
            if !hasMigratedMetricNames {
                await migrateMetricNames(dataHandler: dataHandler)
                hasMigratedMetricNames = true
            }
            
            // STEP 1: Determine what we need to sync
            let syncPlan = await determineSyncPlan(dataHandler: dataHandler)
            
            print("📋 Sync Plan:")
            print("   Historical backfill needed: \(syncPlan.needsHistoricalBackfill)")
            print("   Years to backfill: \(syncPlan.yearsToBackfill)")
            print("   Last data: \(syncPlan.mostRecentDataDate?.formatted() ?? "none")")
            
            // STEP 2: Sync recent data (always - this is fast)
            await syncRecentData(dataHandler: dataHandler)
            
            // STEP 3: Historical backfill (only if needed)
            if syncPlan.needsHistoricalBackfill && !hasCompletedHistoricalBackfill {
                await performHistoricalBackfill(years: syncPlan.yearsToBackfill, dataHandler: dataHandler)
                hasCompletedHistoricalBackfill = true
            }
            
            lastSyncDate = Date()
            print("✅ Smart Sync Complete")
            
        } catch {
            print("❌ Sync Failed: \(error.localizedDescription)")
        }
        
        isSyncing = false
    }
    
    // MARK: - Metric Name Migration
    
    private func migrateMetricNames(dataHandler: DataPersistenceActor) async {
        print("🔄 Migrating metric type names to standardized format...")
        
        await dataHandler.migrateMetricNames(
            oldToNew: [
                "sleep": "Sleep",
                "hrv": "HRV",
                "restingHR": "RHR",
                "steps": "Steps",
                "bodyMass": "Weight",
                "BodyMass": "Weight"
            ]
        )
        
        print("   ✅ Metric names migrated")
    }
    
    // MARK: - Sync Plan
    
    private struct SyncPlan {
        let needsHistoricalBackfill: Bool
        let yearsToBackfill: Int
        let mostRecentDataDate: Date?
        let oldestDataDate: Date?
    }
    
    private func determineSyncPlan(dataHandler: DataPersistenceActor) async -> SyncPlan {
        // Check what data we have
        let summary = await dataHandler.getDataSummary()
        
        print("📊 Current Data Summary:")
        print("   Workouts: \(summary.workoutCount)")
        print("   Sleep days: \(summary.sleepDays)")
        print("   Date range: \(summary.oldestDate?.formatted() ?? "none") to \(summary.newestDate?.formatted() ?? "none")")
        
        // Determine if we need historical backfill
        let needsBackfill: Bool
        let yearsToBackfill: Int
        
        if summary.workoutCount == 0 {
            needsBackfill = true
            yearsToBackfill = 10
        } else if let oldest = summary.oldestDate {
            let calendar = Calendar.current
            let yearsOfData = calendar.dateComponents([.year], from: oldest, to: Date()).year ?? 0
            
            if yearsOfData < 10 {
                needsBackfill = true
                yearsToBackfill = max(1, 10 - yearsOfData)
                print("   Need \(yearsToBackfill) more years of backfill")
            } else {
                needsBackfill = false
                yearsToBackfill = 0
            }
        } else {
            needsBackfill = true
            yearsToBackfill = 10
        }
        
        return SyncPlan(
            needsHistoricalBackfill: needsBackfill,
            yearsToBackfill: yearsToBackfill,
            mostRecentDataDate: summary.newestDate,
            oldestDataDate: summary.oldestDate
        )
    }
    
    // MARK: - Recent Data Sync
    
    private func syncRecentData(dataHandler: DataPersistenceActor) async {
        let calendar = Calendar.current
        let endDate = Date()
        let startDate = calendar.date(byAdding: .day, value: -30, to: endDate)!
        
        print("🔄 Syncing recent data (last 30 days)...")
        syncProgress = "Updating recent data..."
        
        do {
            async let rhr = healthKitManager.fetchRestingHeartRate(startDate: startDate, endDate: endDate)
            async let hrv = healthKitManager.fetchHeartRateVariability(startDate: startDate, endDate: endDate)
            async let sleep = healthKitManager.fetchSleepDuration(startDate: startDate, endDate: endDate)
            async let workouts = healthKitManager.fetchWorkouts(startDate: startDate, endDate: endDate)
            async let steps = healthKitManager.fetchSteps(startDate: startDate, endDate: endDate)
            async let weight = healthKitManager.fetchBodyMass(startDate: startDate, endDate: endDate)
            async let nutrition = healthKitManager.fetchNutrition(startDate: startDate, endDate: endDate)
            
            var stravaActivities: [StravaImportData] = []
            if stravaManager.isAuthenticated {
                if let activities = try? await stravaManager.fetchActivities(page: 1, perPage: 100) {
                    stravaActivities = activities.compactMap { mapStravaActivity($0) }
                }
            }
            
            let data = try await (
                rhr: rhr,
                hrv: hrv,
                sleep: sleep,
                workouts: workouts,
                steps: steps,
                weight: weight,
                nutrition: nutrition
            )
            
            await dataHandler.upsertRecentData(
                workouts: data.workouts,
                strava: stravaActivities,
                sleep: data.sleep,
                hrv: data.hrv,
                rhr: data.rhr,
                steps: data.steps,
                weight: data.weight,
                nutrition: data.nutrition
            )
            
            print("   ✅ Recent data synced")
            
        } catch {
            print("   ❌ Recent sync failed: \(error)")
        }
    }
    
    // MARK: - Historical Backfill
    
    private func performHistoricalBackfill(years: Int, dataHandler: DataPersistenceActor) async {
        print("🕰️ Starting \(years)-year historical backfill...")
        
        isBackfillingHistory = true
        backfillProgress = 0
        syncProgress = "Building historical baseline..."
        
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: Date())
        let startYear = currentYear - years
        
        for yearOffset in 0..<years {
            let year = startYear + yearOffset
            
            print("   📅 Backfilling year \(year)...")
            backfillProgress = Double(yearOffset) / Double(years)
            syncProgress = "Processing \(year)..."
            
            do {
                let snapshot = try await healthKitManager.fetchYearlySnapshot(year: year)
                
                await dataHandler.appendHistoricalBatch(
                    workouts: snapshot.workouts,
                    sleep: snapshot.sleep,
                    hrv: snapshot.hrv,
                    rhr: snapshot.rhr,
                    nutrition: snapshot.nutrition
                )
                
                print("      ✅ Year \(year) complete")
                
                try? await Task.sleep(nanoseconds: 300_000_000)
                
            } catch {
                print("      ❌ Year \(year) failed: \(error)")
            }
        }
        
        isBackfillingHistory = false
        backfillProgress = 1.0
        print("   ✅ Historical backfill complete")
    }
    
    // MARK: - Manual Operations
    
    func performFullResync() async {
        print("🔄 Forcing full resync...")
        
        hasCompletedHistoricalBackfill = false
        lastSyncDate = nil
        
        let container = HealthDataContainer.shared
        let dataHandler = DataPersistenceActor(modelContainer: container)
        
        await dataHandler.deleteAll()
        await performSmartSync()
    }
    
    func resetAllData() async {
        print("🗑️ Resetting all data...")
        
        let container = HealthDataContainer.shared
        let dataHandler = DataPersistenceActor(modelContainer: container)
        
        hasCompletedHistoricalBackfill = false
        hasMigratedMetricNames = false
        lastSyncDate = nil
        
        await dataHandler.deleteAll()
        await performSmartSync()
    }
    
    // MARK: - Helper
    
    private func mapStravaActivity(_ activity: StravaActivity) -> StravaImportData? {
        guard let date = activity.startDateFormatted else { return nil }
        
        var energy = activity.calories ?? 0
        if energy == 0, let kj = activity.kilojoules, kj > 0 {
            energy = kj
        }
        
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
    
    private func mapStravaType(_ type: String) -> HKWorkoutActivityType {
        switch type {
        case "Run": return .running
        case "Ride", "VirtualRide": return .cycling
        case "WeightTraining": return .traditionalStrengthTraining
        default: return .other
        }
    }
}

// MARK: - Data Persistence Actor

@ModelActor
actor DataPersistenceActor {
    
    // MARK: - Metric Name Migration
    
    func migrateMetricNames(oldToNew: [String: String]) {
        for (oldName, newName) in oldToNew {
            let descriptor = FetchDescriptor<StoredHealthMetric>(
                predicate: #Predicate { $0.type == oldName }
            )
            
            if let metrics = try? modelContext.fetch(descriptor) {
                print("   Migrating \(metrics.count) '\(oldName)' metrics to '\(newName)'")
                
                for metric in metrics {
                    metric.type = newName
                    
                    // Update uniqueKey too
                    let formatter = DateFormatter()
                    formatter.dateFormat = "yyyy-MM-dd"
                    metric.uniqueKey = "\(newName)_\(formatter.string(from: metric.date))"
                }
            }
        }
        
        if modelContext.hasChanges {
            try? modelContext.save()
        }
    }
    
    // MARK: - Data Summary
    
    struct DataSummary {
        let workoutCount: Int
        let sleepDays: Int
        let hrvDays: Int
        let rhrDays: Int
        let oldestDate: Date?
        let newestDate: Date?
    }
    
    func getDataSummary() -> DataSummary {
        let workoutCount = (try? modelContext.fetchCount(FetchDescriptor<StoredWorkout>())) ?? 0
        
        // ✅ Check BOTH old and new metric names
        let sleepCount = (try? modelContext.fetchCount(
            FetchDescriptor<StoredHealthMetric>(predicate: #Predicate {
                $0.type == "Sleep" || $0.type == "sleep"
            })
        )) ?? 0
        
        let hrvCount = (try? modelContext.fetchCount(
            FetchDescriptor<StoredHealthMetric>(predicate: #Predicate {
                $0.type == "HRV" || $0.type == "hrv"
            })
        )) ?? 0
        
        let rhrCount = (try? modelContext.fetchCount(
            FetchDescriptor<StoredHealthMetric>(predicate: #Predicate {
                $0.type == "RHR" || $0.type == "restingHR"
            })
        )) ?? 0
        
        let workoutDescriptor = FetchDescriptor<StoredWorkout>(
            sortBy: [SortDescriptor(\.startDate)]
        )
        let workouts = (try? modelContext.fetch(workoutDescriptor)) ?? []
        
        return DataSummary(
            workoutCount: workoutCount,
            sleepDays: sleepCount,
            hrvDays: hrvCount,
            rhrDays: rhrCount,
            oldestDate: workouts.first?.startDate,
            newestDate: workouts.last?.startDate
        )
    }
    
    // MARK: - Delete All
    
    func deleteAll() {
        try? modelContext.delete(model: StoredWorkout.self)
        try? modelContext.delete(model: StoredHealthMetric.self)
        try? modelContext.delete(model: StoredNutrition.self)
        try? modelContext.save()
        print("🗑️ All data deleted")
    }
    
    // MARK: - Upsert Recent Data
    
    func upsertRecentData(
        workouts: [WorkoutData],
        strava: [StravaImportData],
        sleep: [HealthDataPoint],
        hrv: [HealthDataPoint],
        rhr: [HealthDataPoint],
        steps: [HealthDataPoint],
        weight: [HealthDataPoint],
        nutrition: [DailyNutrition]
    ) {
        var matchedStravaIds = Set<String>()
        
        for hkWorkout in workouts {
            let workoutID = hkWorkout.id.uuidString
            
            if let match = WorkoutMatcher.findMatch(for: hkWorkout, in: strava) {
                upsertWorkout(
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
                )
                matchedStravaIds.insert(match.id)
            } else {
                upsertWorkout(
                    id: workoutID,
                    title: nil,
                    type: hkWorkout.workoutType,
                    startDate: hkWorkout.startDate,
                    duration: hkWorkout.duration,
                    distance: hkWorkout.totalDistance,
                    power: hkWorkout.averagePower,
                    energy: hkWorkout.totalEnergyBurned,
                    hr: hkWorkout.averageHeartRate,
                    source: hkWorkout.source.rawValue
                )
            }
        }
        
        for activity in strava where !matchedStravaIds.contains(activity.id) {
            upsertWorkout(
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
            )
        }
        
        // ✅ Use NEW standardized names
        for (points, type) in [(hrv, "HRV"), (rhr, "RHR"), (sleep, "Sleep"), (steps, "Steps"), (weight, "Weight")] {
            for point in points {
                upsertMetric(type: type, date: point.date, value: point.value)
            }
        }
        
        for entry in nutrition {
            upsertNutrition(date: entry.date, entry: entry)
        }
        
        if modelContext.hasChanges {
            try? modelContext.save()
            modelContext.processPendingChanges()
            
            Task { @MainActor in
                HealthDataContainer.shared.mainContext.processPendingChanges()
            }
        }
        
        print("💾 Recent data upserted")
    }
    
    // MARK: - Append Historical Batch
    
    func appendHistoricalBatch(
        workouts: [WorkoutData],
        sleep: [HealthDataPoint],
        hrv: [HealthDataPoint],
        rhr: [HealthDataPoint],
        nutrition: [DailyNutrition]
    ) {
        for workout in workouts {
            let workoutID = workout.id.uuidString
            
            let descriptor = FetchDescriptor<StoredWorkout>(
                predicate: #Predicate { $0.id == workoutID }
            )
            
            if (try? modelContext.fetch(descriptor).first) == nil {
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
        
        // ✅ Use NEW standardized names
        for (points, type) in [(hrv, "HRV"), (rhr, "RHR"), (sleep, "Sleep")] {
            for point in points {
                upsertMetric(type: type, date: point.date, value: point.value)
            }
        }
        
        for entry in nutrition {
            upsertNutrition(date: entry.date, entry: entry)
        }
        
        if modelContext.hasChanges {
            try? modelContext.save()
            modelContext.processPendingChanges()
            
            Task { @MainActor in
                HealthDataContainer.shared.mainContext.processPendingChanges()
            }
        }
    }
    
    // MARK: - Private Helpers
    
    private func upsertWorkout(
        id: String,
        title: String?,
        type: HKWorkoutActivityType,
        startDate: Date,
        duration: TimeInterval,
        distance: Double?,
        power: Double?,
        energy: Double?,
        hr: Double?,
        source: String
    ) {
        let descriptor = FetchDescriptor<StoredWorkout>(
            predicate: #Predicate { $0.id == id }
        )
        
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.title = title
            existing.duration = duration
            existing.distance = distance
            existing.averagePower = power
            existing.totalEnergyBurned = energy
            existing.averageHeartRate = hr
        } else {
            modelContext.insert(StoredWorkout(
                id: id,
                title: title,
                type: type,
                startDate: startDate,
                duration: duration,
                distance: distance,
                power: power,
                energy: energy,
                hr: hr,
                source: source
            ))
        }
    }
    
    private func upsertMetric(type: String, date: Date, value: Double) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let key = "\(type)_\(formatter.string(from: date))"
        
        let descriptor = FetchDescriptor<StoredHealthMetric>(
            predicate: #Predicate { $0.uniqueKey == key }
        )
        
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.value = value
        } else {
            modelContext.insert(StoredHealthMetric(
                type: type,
                date: date,
                value: value
            ))
        }
    }
    
    private func upsertNutrition(date: Date, entry: DailyNutrition) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateString = formatter.string(from: date)
        
        let descriptor = FetchDescriptor<StoredNutrition>(
            predicate: #Predicate { $0.dateString == dateString }
        )
        
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.calories = entry.totalCalories
            existing.protein = entry.totalProtein
            existing.carbs = entry.totalCarbs
            existing.fat = entry.totalFat
        } else {
            modelContext.insert(StoredNutrition(
                date: date,
                calories: entry.totalCalories,
                protein: entry.totalProtein,
                carbs: entry.totalCarbs,
                fat: entry.totalFat
            ))
        }
    }
}
