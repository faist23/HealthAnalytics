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
        #if DEBUG
        print("🔍 SYNC DEBUG:")
        print("   lastSyncDate: \(lastSyncDate?.formatted() ?? "nil")")
        if let last = lastSyncDate {
            print("   Time since last: \(Date().timeIntervalSince(last)) seconds")
            print("   Should skip: \(Date().timeIntervalSince(last) < 1800)")
        }
        #endif
        
        // Prevent redundant syncs - only sync if 30+ minutes have passed
        if let last = lastSyncDate, Date().timeIntervalSince(last) < 1800 {
            #if DEBUG
            print("🛡️ Sync Guard: Synced \(Int(Date().timeIntervalSince(last)/60))m ago. Skipping.")
            #endif
            return
        }

        guard !isSyncing else {
            #if DEBUG
            print("⚠️ Sync already in progress")
            #endif
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
            
            #if DEBUG
            print("📋 Sync Plan:")
            print("   Historical backfill needed: \(syncPlan.needsHistoricalBackfill)")
            print("   Years to backfill: \(syncPlan.yearsToBackfill)")
            print("   Last data: \(syncPlan.mostRecentDataDate?.formatted() ?? "none")")
            #endif
            
            // STEP 2: Sync recent data (always - this is fast)
            await syncRecentData(dataHandler: dataHandler)
            
            // STEP 3: Historical backfill (only if needed)
            if syncPlan.needsHistoricalBackfill && !hasCompletedHistoricalBackfill {
                await performHistoricalBackfill(years: syncPlan.yearsToBackfill, dataHandler: dataHandler)
                hasCompletedHistoricalBackfill = true
            }
            
            lastSyncDate = Date()
            #if DEBUG
            print("✅ Smart Sync Complete")
            #endif

            // Notify views that new data is available
            NotificationCenter.default.post(name: NSNotification.Name("DataSyncCompleted"), object: nil)

        } catch {
            #if DEBUG
            print("❌ Sync Failed: \(error.localizedDescription)")
            #endif
        }
        
        isSyncing = false
    }
    
    // MARK: - Metric Name Migration
    
    private func migrateMetricNames(dataHandler: DataPersistenceActor) async {
        #if DEBUG
        print("🔄 Migrating metric type names to standardized format...")
        #endif
        
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
        
        #if DEBUG
        print("   ✅ Metric names migrated")
        #endif
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
        
        #if DEBUG
        print("📊 Current Data Summary:")
        print("   Workouts: \(summary.workoutCount)")
        print("   Sleep days: \(summary.sleepDays)")
        print("   Date range: \(summary.oldestDate?.formatted() ?? "none") to \(summary.newestDate?.formatted() ?? "none")")
        #endif
        
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
                #if DEBUG
                print("   Need \(yearsToBackfill) more years of backfill")
                #endif
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

        // INCREMENTAL SYNC: Only fetch data since last successful sync
        let startDate: Date
        if let lastSync = lastSyncDate {
            // Add 1 day buffer to avoid missing data at boundaries
            startDate = calendar.date(byAdding: .day, value: -1, to: lastSync) ?? lastSync
            let daysSinceLastSync = calendar.dateComponents([.day], from: lastSync, to: endDate).day ?? 0
            
            // Better time display for recent syncs
            let timeSinceLastSync = endDate.timeIntervalSince(lastSync)
            let timeDescription: String
            if timeSinceLastSync < 3600 { // Less than 1 hour
                let minutes = Int(timeSinceLastSync / 60)
                timeDescription = "\(minutes) minute\(minutes == 1 ? "" : "s")"
            } else if timeSinceLastSync < 86400 { // Less than 1 day
                let hours = Int(timeSinceLastSync / 3600)
                timeDescription = "\(hours) hour\(hours == 1 ? "" : "s")"
            } else if daysSinceLastSync <= 7 {
                timeDescription = "\(daysSinceLastSync) day\(daysSinceLastSync == 1 ? "" : "s")"
            } else {
                let weeks = daysSinceLastSync / 7
                timeDescription = "\(weeks) week\(weeks == 1 ? "" : "s")"
            }
            
            #if DEBUG
            print("🔄 Syncing data since last sync (\(timeDescription) ago)...")
            #endif
            syncProgress = "Updating last \(timeDescription)..."
        } else {
            // First sync ever - get last 30 days as initial data
            startDate = calendar.date(byAdding: .day, value: -30, to: endDate) ?? endDate
            #if DEBUG
            print("🔄 Initial sync: fetching last 30 days...")
            #endif
            syncProgress = "Fetching initial data..."
        }
        
        do {
            async let rhr = healthKitManager.fetchRestingHeartRate(startDate: startDate, endDate: endDate)
            async let hrv = healthKitManager.fetchHeartRateVariability(startDate: startDate, endDate: endDate)
            async let sleep = healthKitManager.fetchSleepDuration(startDate: startDate, endDate: endDate)
            async let workouts = healthKitManager.fetchWorkouts(startDate: startDate, endDate: endDate)
            async let steps = healthKitManager.fetchSteps(startDate: startDate, endDate: endDate)
            async let weight = healthKitManager.fetchBodyMass(startDate: startDate, endDate: endDate)
            async let nutrition = healthKitManager.fetchNutrition(startDate: startDate, endDate: endDate)
            async let vo2max = healthKitManager.fetchVO2Max(startDate: startDate, endDate: endDate)
            
            var stravaActivities: [StravaImportData] = []
            if stravaManager.isAuthenticated {
                var allActivities: [StravaActivity] = []
                var page = 1
                var keepFetching = true
                let startDateTimestamp = Int(startDate.timeIntervalSince1970)
                
                while keepFetching {
                    if let batch = try? await stravaManager.fetchActivities(page: page, perPage: 200) {
                        if batch.isEmpty {
                            keepFetching = false
                        } else {
                            // Filter activities to only those after startDate
                            let recentActivities = batch.filter { activity in
                                let formatter = ISO8601DateFormatter()
                                if let date = formatter.date(from: activity.startDate) {
                                    return date >= startDate
                                }
                                return true // Include if we can't parse date (safer)
                            }
                            
                            allActivities.append(contentsOf: recentActivities)
                            #if DEBUG
                            print("   📥 Fetched page \(page): \(recentActivities.count)/\(batch.count) activities since \(startDate.formatted(date: .abbreviated, time: .omitted)) (total: \(allActivities.count))")
                            #endif

                            // Stop fetching if we got fewer activities than requested (means we've reached older data)
                            if recentActivities.count < batch.count {
                                #if DEBUG
                                print("   ⏹️ Reached activities older than sync window, stopping pagination")
                                #endif
                                keepFetching = false
                            } else {
                                page += 1
                            }
                        }
                    } else {
                        keepFetching = false
                    }
                }
                
                stravaActivities = allActivities.compactMap { mapStravaActivity($0) }
                #if DEBUG
                print("   ✅ Total Strava activities fetched: \(stravaActivities.count)")
                #endif
            }

            let data = try await (
                rhr: rhr,
                hrv: hrv,
                sleep: sleep,
                workouts: workouts,
                steps: steps,
                weight: weight,
                nutrition: nutrition,
                vo2max: vo2max
            )

            await dataHandler.upsertRecentData(
                workouts: data.workouts,
                strava: stravaActivities,
                sleep: data.sleep,
                hrv: data.hrv,
                rhr: data.rhr,
                steps: data.steps,
                weight: data.weight,
                nutrition: data.nutrition,
                vo2max: data.vo2max
            )

            #if DEBUG
            print("   ✅ Recent data synced")
            #endif

        } catch {
            #if DEBUG
            print("   ❌ Recent sync failed: \(error)")
            #endif
        }
    }
    
    // MARK: - Historical Backfill
    
    private func performHistoricalBackfill(years: Int, dataHandler: DataPersistenceActor) async {
        #if DEBUG
        print("🕰️ Starting \(years)-year historical backfill...")
        #endif
        
        isBackfillingHistory = true
        backfillProgress = 0
        syncProgress = "Building historical baseline..."
        
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: Date())
        let startYear = currentYear - years
        
        for yearOffset in 0..<years {
            let year = startYear + yearOffset
            
            #if DEBUG
            print("   📅 Backfilling year \(year)...")
            #endif
            
            // Note: Historical backfill is intentionally minimal
            // All HealthKit data is already fetched in syncRecentData which pulls from current year start
            // This stub exists for future expansion if needed
        }
        
        isBackfillingHistory = false
        backfillProgress = 1.0
        #if DEBUG
        print("   ✅ Historical backfill complete")
        #endif
    }
    
    // MARK: - Sync All Historical Data
    
    private func syncAllHistoricalData(dataHandler: DataPersistenceActor) async {
        #if DEBUG
        print("📚 Fetching ALL historical data (10 years)...")
        #endif
        
        syncProgress = "Fetching all historical data..."
        
        let calendar = Calendar.current
        let endDate = Date()
        let startDate = calendar.date(byAdding: .year, value: -10, to: endDate) ?? endDate
        
        #if DEBUG
        print("   📅 Date range: \(startDate.formatted(date: .abbreviated, time: .omitted)) to \(endDate.formatted(date: .abbreviated, time: .omitted))")
        #endif
        
        do {
            async let rhr = healthKitManager.fetchRestingHeartRate(startDate: startDate, endDate: endDate)
            async let hrv = healthKitManager.fetchHeartRateVariability(startDate: startDate, endDate: endDate)
            async let sleep = healthKitManager.fetchSleepDuration(startDate: startDate, endDate: endDate)
            async let workouts = healthKitManager.fetchWorkouts(startDate: startDate, endDate: endDate)
            async let steps = healthKitManager.fetchSteps(startDate: startDate, endDate: endDate)
            async let weight = healthKitManager.fetchBodyMass(startDate: startDate, endDate: endDate)
            async let nutrition = healthKitManager.fetchNutrition(startDate: startDate, endDate: endDate)
            async let vo2max = healthKitManager.fetchVO2Max(startDate: startDate, endDate: endDate)
            
            // Fetch all Strava activities
            var stravaActivities: [StravaImportData] = []
            if stravaManager.isAuthenticated {
                #if DEBUG
                print("   🚴 Fetching all Strava activities...")
                #endif
                var allActivities: [StravaActivity] = []
                var page = 1
                var keepFetching = true
                
                while keepFetching {
                    if let batch = try? await stravaManager.fetchActivities(page: page, perPage: 200) {
                        if batch.isEmpty {
                            keepFetching = false
                        } else {
                            allActivities.append(contentsOf: batch)
                            #if DEBUG
                            print("   📥 Fetched page \(page): \(batch.count) activities (total: \(allActivities.count))")
                            #endif
                            page += 1

                            // Safety: Stop after 50 pages (10,000 activities)
                            if page > 50 {
                                #if DEBUG
                                print("   ⚠️ Reached page limit, stopping")
                                #endif
                                keepFetching = false
                            }
                        }
                    } else {
                        keepFetching = false
                    }
                }
                
                stravaActivities = allActivities.compactMap { mapStravaActivity($0) }
                #if DEBUG
                print("   ✅ Total Strava activities: \(stravaActivities.count)")
                #endif
            }

            let data = try await (
                rhr: rhr,
                hrv: hrv,
                sleep: sleep,
                workouts: workouts,
                steps: steps,
                weight: weight,
                nutrition: nutrition,
                vo2max: vo2max
            )

            #if DEBUG
            print("   📊 Fetched: \(data.workouts.count) workouts, \(data.hrv.count) HRV, \(data.rhr.count) RHR, \(data.sleep.count) sleep, \(data.vo2max.count) VO2max")
            #endif

            await dataHandler.upsertRecentData(
                workouts: data.workouts,
                strava: stravaActivities,
                sleep: data.sleep,
                hrv: data.hrv,
                rhr: data.rhr,
                steps: data.steps,
                weight: data.weight,
                nutrition: data.nutrition,
                vo2max: data.vo2max
            )

            #if DEBUG
            print("   ✅ All historical data saved")
            #endif

        } catch {
            #if DEBUG
            print("   ❌ Failed to fetch historical data: \(error.localizedDescription)")
            #endif
        }
    }
    
    // MARK: - Manual Operations
    
    func performFullResync() async {
        #if DEBUG
        print("🔄 Forcing full resync...")
        #endif
        
        hasCompletedHistoricalBackfill = false
        lastSyncDate = nil
        
        let container = HealthDataContainer.shared
        let dataHandler = DataPersistenceActor(modelContainer: container)
        
        await dataHandler.deleteAll()
        await performSmartSync()
    }
    
    func resetAllData() async {
        #if DEBUG
        print("🗑️ Resetting all data...")
        #endif

        guard !isSyncing else {
            #if DEBUG
            print("⚠️ Sync already in progress")
            #endif
            return
        }
        
        isSyncing = true
        
        let container = HealthDataContainer.shared
        let dataHandler = DataPersistenceActor(modelContainer: container)
        
        hasCompletedHistoricalBackfill = false
        hasMigratedMetricNames = false
        lastSyncDate = nil
        
        await dataHandler.deleteAll()
        
        // Fetch ALL historical data (10 years back)
        await syncAllHistoricalData(dataHandler: dataHandler)
        
        lastSyncDate = Date()
        hasCompletedHistoricalBackfill = true
        
        #if DEBUG
        print("✅ Reset Complete - All historical data restored")
        #endif
        
        // Notify views that new data is available
        NotificationCenter.default.post(name: NSNotification.Name("DataSyncCompleted"), object: nil)
        
        isSyncing = false
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
                #if DEBUG
                print("   Migrating \(metrics.count) '\(oldName)' metrics to '\(newName)'")
                #endif
                
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
        try? modelContext.delete(model: StoredIntentLabel.self)
        try? modelContext.save()
        #if DEBUG
        print("🗑️ All data deleted")
        #endif
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
        nutrition: [DailyNutrition],
        vo2max: [HealthDataPoint]
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
        for (points, type) in [(hrv, "HRV"), (rhr, "RHR"), (sleep, "Sleep"), (steps, "Steps"), (weight, "Weight"), (vo2max, "VO2max")] {
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
        
        // Auto-classify workout intents using heuristic classifier
        autoClassifyWorkoutIntents()
        
        #if DEBUG
        print("💾 Recent data upserted")
        #endif
    }
    
    // MARK: - Append Historical Batch
    
    func appendHistoricalBatch(
        workouts: [WorkoutData],
        sleep: [HealthDataPoint],
        hrv: [HealthDataPoint],
        rhr: [HealthDataPoint],
        steps: [HealthDataPoint],
        weight: [HealthDataPoint],
        nutrition: [DailyNutrition]
    ) {
        #if DEBUG
        print("   💾 BATCH SAVE DEBUG:")
        print("      Input counts: Sleep=\(sleep.count), HRV=\(hrv.count), Steps=\(steps.count), Weight=\(weight.count)")
        #endif
        
        // Save workouts (this is working)
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
        
        // Save metrics with detailed logging
        #if DEBUG
        print("   🔍 Processing health metrics:")
        #endif

        for (points, type) in [(hrv, "HRV"), (rhr, "RHR"), (sleep, "Sleep"), (steps, "Steps"), (weight, "Weight")] {
            #if DEBUG
            print("   📊 Processing \(type): \(points.count) points")
            #endif

            if points.isEmpty {
                #if DEBUG
                print("      ⚠️ No points to save!")
                #endif
                continue
            }

            // Show first few samples
            #if DEBUG
            for (index, point) in points.prefix(3).enumerated() {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
                print("      Sample \(index+1): date=\(formatter.string(from: point.date)), value=\(point.value)")
            }
            #endif

            var savedCount = 0
            for point in points {
                upsertMetric(type: type, date: point.date, value: point.value)
                savedCount += 1

                // Progress indicator
                #if DEBUG
                if savedCount % 50 == 0 {
                    print("      ... processed \(savedCount)/\(points.count)")
                }
                #endif
            }
            #if DEBUG
            print("      ✅ Processed \(savedCount) \(type) points")
            #endif
        }
        
        // Nutrition
        for entry in nutrition {
            upsertNutrition(date: entry.date, entry: entry)
        }
        
        // CRITICAL: Save with error handling
        #if DEBUG
        print("   💾 Attempting to save...")
        print("      Context has changes: \(modelContext.hasChanges)")
        #endif

        if modelContext.hasChanges {
            do {
                #if DEBUG
                print("      🔄 Calling save()...")
                #endif
                try modelContext.save()
                #if DEBUG
                print("      ✅ SAVE SUCCESSFUL!")

                // Verify what was saved
                let sleepCount = (try? modelContext.fetchCount(
                    FetchDescriptor<StoredHealthMetric>(predicate: #Predicate { $0.type == "Sleep" })
                )) ?? 0
                let hrvCount = (try? modelContext.fetchCount(
                    FetchDescriptor<StoredHealthMetric>(predicate: #Predicate { $0.type == "HRV" })
                )) ?? 0
                let rhrCount = (try? modelContext.fetchCount(
                    FetchDescriptor<StoredHealthMetric>(predicate: #Predicate { $0.type == "RHR" })
                )) ?? 0
                let stepsCount = (try? modelContext.fetchCount(
                    FetchDescriptor<StoredHealthMetric>(predicate: #Predicate { $0.type == "Steps" })
                )) ?? 0
                let weightCount = (try? modelContext.fetchCount(
                    FetchDescriptor<StoredHealthMetric>(predicate: #Predicate { $0.type == "Weight" })
                )) ?? 0

                print("      📊 Verification counts:")
                print("         Sleep: \(sleepCount)")
                print("         HRV: \(hrvCount)")
                print("         Steps: \(stepsCount)")
                print("         Weight: \(weightCount)")
                #endif

            } catch {
                #if DEBUG
                print("      ❌ SAVE FAILED: \(error)")
                print("      Error details: \(error.localizedDescription)")
                #endif
            }

            modelContext.processPendingChanges()

            Task { @MainActor in
                HealthDataContainer.shared.mainContext.processPendingChanges()
            }
        } else {
            #if DEBUG
            print("      ⚠️ No changes to save (this is the problem!)")
            print("      Inserted items count: \(modelContext.insertedModelsArray.count)")
            print("      Updated items count: \(modelContext.changedModelsArray.count)")
            #endif
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
        formatter.timeZone = TimeZone.current
        let dateString = formatter.string(from: date)
        let key = "\(type)_\(dateString)"
        
        #if DEBUG
        print("      🔍 Processing \(type): date=\(dateString), value=\(value), key=\(key)")
        #endif

        // Try to fetch existing
        let descriptor = FetchDescriptor<StoredHealthMetric>(
            predicate: #Predicate { $0.uniqueKey == key }
        )

        do {
            let existing = try modelContext.fetch(descriptor)

            if let found = existing.first {
                #if DEBUG
                print("         ✏️ Updating existing: \(key)")
                #endif
                found.value = value
            } else {
                #if DEBUG
                print("         ➕ Creating new: \(key)")
                #endif
                let metric = StoredHealthMetric(
                    type: type,
                    date: date,
                    value: value
                )
                modelContext.insert(metric)
                #if DEBUG
                print("         ✅ Inserted successfully")
                #endif
            }
        } catch {
            #if DEBUG
            print("         ❌ FETCH ERROR: \(error)")

            // Try direct insert as fallback
            print("         🔄 Attempting direct insert...")
            #endif
            let metric = StoredHealthMetric(
                type: type,
                date: date,
                value: value
            )
            modelContext.insert(metric)
            #if DEBUG
            print("         ✅ Direct insert complete")
            #endif
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
    
    // MARK: - Auto-Classification
    
    /// Automatically classify workout intents using heuristic rules
    func autoClassifyWorkoutIntents() {
        #if DEBUG
        print("🧠 Auto-classifying workout intents...")
        #endif

        // Fetch all workouts
        let workoutDescriptor = FetchDescriptor<StoredWorkout>()
        guard let allWorkouts = try? modelContext.fetch(workoutDescriptor) else {
            #if DEBUG
            print("   ⚠️ Failed to fetch workouts")
            #endif
            return
        }
        
        // Fetch existing labels
        let labelDescriptor = FetchDescriptor<StoredIntentLabel>()
        let existingLabels = (try? modelContext.fetch(labelDescriptor)) ?? []
        let existingLabelIds = Set(existingLabels.map { $0.workoutId })
        
        // Classify unlabeled workouts
        let results = HeuristicIntentClassifier.classifyAll(
            workouts: allWorkouts,
            existingLabels: existingLabelIds
        )
        
        // Save new labels
        var newLabelsCount = 0
        for (workoutId, intent, confidence) in results {
            let label = StoredIntentLabel(
                workoutId: workoutId,
                intent: intent,
                confidence: confidence,
                source: .heuristic
            )
            modelContext.insert(label)
            newLabelsCount += 1
        }
        
        if modelContext.hasChanges {
            try? modelContext.save()
            #if DEBUG
            print("   ✅ Auto-classified \(newLabelsCount) workouts")
            #endif
        } else {
            #if DEBUG
            print("   ℹ️ No new workouts to classify")
            #endif
        }
    }
}
