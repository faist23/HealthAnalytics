//
//  HealthKitManager.swift
//  HealthAnalytics
//
//  Created by Craig Faist on 1/25/26.
//


import Foundation
import HealthKit
import Combine

class HealthKitManager: ObservableObject {
    
    static let shared = HealthKitManager()
    
    private let healthStore = HKHealthStore()
    
    @Published var isAuthorized = false
    @Published var authorizationError: String?
    
    // Health data types we want to read
    private let readTypes: Set<HKObjectType> = [
        HKObjectType.quantityType(forIdentifier: .heartRate)!,
        HKObjectType.quantityType(forIdentifier: .restingHeartRate)!,
        HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!,
        HKObjectType.quantityType(forIdentifier: .stepCount)!,
        HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
        HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
        HKObjectType.quantityType(forIdentifier: .vo2Max)!,
        HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
        HKObjectType.workoutType()
    ]
    
    private init() {
        checkHealthKitAvailability()
    }
    
    // Check if HealthKit is available on this device
    private func checkHealthKitAvailability() {
        guard HKHealthStore.isHealthDataAvailable() else {
            authorizationError = "HealthKit is not available on this device"
            return
        }
    }
    
    // Request authorization from user
    func requestAuthorization() async {
        do {
            try await healthStore.requestAuthorization(toShare: [], read: readTypes)
            
            await MainActor.run {
                self.isAuthorized = true
                self.authorizationError = nil
            }
        } catch {
            await MainActor.run {
                self.authorizationError = error.localizedDescription
                self.isAuthorized = false
            }
        }
    }
    
    // Check current authorization status
    func checkAuthorizationStatus() -> HKAuthorizationStatus {
        guard let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate) else {
            return .notDetermined
        }
        return healthStore.authorizationStatus(for: heartRateType)
    }
    
    // MARK: - Data Fetching
    
    /// Fetch resting heart rate data for the specified date range
    func fetchRestingHeartRate(startDate: Date, endDate: Date) async throws -> [HealthDataPoint] {
        guard let restingHRType = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) else {
            throw HealthKitError.dataTypeNotAvailable
        }
        
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: restingHRType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, samples, error in
                
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let samples = samples as? [HKQuantitySample] else {
                    continuation.resume(returning: [])
                    return
                }
                
                let dataPoints = samples.map { sample in
                    HealthDataPoint(
                        date: sample.startDate,
                        value: sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                    )
                }
                
                continuation.resume(returning: dataPoints)
            }
            
            healthStore.execute(query)
        }
    }
    
    /// Fetch heart rate variability (HRV) data for the specified date range
    func fetchHeartRateVariability(startDate: Date, endDate: Date) async throws -> [HealthDataPoint] {
        guard let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else {
            throw HealthKitError.dataTypeNotAvailable
        }
        
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: hrvType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, samples, error in
                
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let samples = samples as? [HKQuantitySample] else {
                    continuation.resume(returning: [])
                    return
                }
                
                let dataPoints = samples.map { sample in
                    HealthDataPoint(
                        date: sample.startDate,
                        value: sample.quantity.doubleValue(for: HKUnit.secondUnit(with: .milli))
                    )
                }
                
                continuation.resume(returning: dataPoints)
            }
            
            healthStore.execute(query)
        }
    }
    
    /// Fetch sleep duration data for the specified date range with smart source prioritization
    func fetchSleepDuration(startDate: Date, endDate: Date) async throws -> [HealthDataPoint] {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            throw HealthKitError.dataTypeNotAvailable
        }
        
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, samples, error in
                
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let samples = samples as? [HKCategorySample] else {
                    continuation.resume(returning: [])
                    return
                }
                
                let calendar = Calendar.current
                
                // Group samples by "sleep night" (shift -6 hours so 11PM-7AM is same night)
                let samplesByNight = Dictionary(grouping: samples) { sample in
                    let adjustedDate = sample.startDate.addingTimeInterval(-6 * 3600)
                    return calendar.startOfDay(for: adjustedDate)
                }
                
                var dataPoints: [HealthDataPoint] = []
                
                for (night, nightSamples) in samplesByNight {
                    let duration = self.calculateEffectiveSleepDuration(samples: nightSamples)
                    
                    if duration > 0 {
                        let hours = duration / 3600.0
                        
                        // Use the next day (wake-up day) as the date
                        let wakeUpDay = calendar.date(byAdding: .day, value: 1, to: night) ?? night
                        
                        dataPoints.append(HealthDataPoint(
                            date: wakeUpDay,
                            value: hours
                        ))
                        
                        print("📊 Sleep for night of \(night.formatted(date: .abbreviated, time: .omitted)): \(String(format: "%.1f", hours))h")
                    }
                }
                
                let sortedDataPoints = dataPoints.sorted { $0.date < $1.date }
                
                continuation.resume(returning: sortedDataPoints)
            }
            
            healthStore.execute(query)
        }
    }
    
    // MARK: - Smart Sleep Calculation
    
    /// Calculates effective sleep duration with source prioritization
    /// Prioritizes AutoSleep when it has valid data, falls back to Apple Watch otherwise
    private func calculateEffectiveSleepDuration(samples: [HKCategorySample]) -> TimeInterval {
        // 1. Identify AutoSleep samples
        let autoSleepSamples = samples.filter {
            $0.sourceRevision.source.bundleIdentifier.lowercased().contains("autosleep")
        }
        
        let hasAutoSleep = !autoSleepSamples.isEmpty
        
        var targetSamples: [HKCategorySample] = []
        
        if hasAutoSleep {
            // Check if AutoSleep has actual "asleep" data (not just "in bed")
            let hasValidSleepData = autoSleepSamples.contains { sample in
                let val = sample.value
                return val == HKCategoryValueSleepAnalysis.asleepCore.rawValue ||
                val == HKCategoryValueSleepAnalysis.asleepDeep.rawValue ||
                val == HKCategoryValueSleepAnalysis.asleepREM.rawValue ||
                val == HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue
            }
            
            if hasValidSleepData {
                // AutoSleep has good data - use it exclusively
                targetSamples = autoSleepSamples
            } else {
                // AutoSleep exists but has no sleep data - fall back to Apple Watch
                print("   ⚠️ AutoSleep detected but empty. Falling back to Apple Watch.")
                targetSamples = samples.filter {
                    !$0.sourceRevision.source.bundleIdentifier.lowercased().contains("autosleep")
                }
            }
        } else {
            // No AutoSleep - use all available data (typically Apple Watch)
            targetSamples = samples
        }
        
        // 2. Filter for valid sleep stages (exclude "in bed" and "awake")
        let validSamples = targetSamples.filter { sample in
            let val = sample.value
            return val == HKCategoryValueSleepAnalysis.asleepCore.rawValue ||
            val == HKCategoryValueSleepAnalysis.asleepDeep.rawValue ||
            val == HKCategoryValueSleepAnalysis.asleepREM.rawValue ||
            val == HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue
        }
        
        // 3. Merge overlapping intervals to prevent double-counting
        return calculateUniqueDuration(validSamples)
    }
    
    /// Merges overlapping sleep intervals to prevent double-counting
    private func calculateUniqueDuration(_ samples: [HKCategorySample]) -> TimeInterval {
        guard !samples.isEmpty else { return 0 }
        
        // Sort by start time
        let sorted = samples.sorted { $0.startDate < $1.startDate }
        
        var totalDuration: TimeInterval = 0
        var currentStart = sorted[0].startDate
        var currentEnd = sorted[0].endDate
        
        // Merge overlapping intervals
        for i in 1..<sorted.count {
            let next = sorted[i]
            
            if next.startDate < currentEnd {
                // Overlapping - extend current interval if needed
                if next.endDate > currentEnd {
                    currentEnd = next.endDate
                }
            } else {
                // Not overlapping - add current interval to total and start new one
                totalDuration += currentEnd.timeIntervalSince(currentStart)
                currentStart = next.startDate
                currentEnd = next.endDate
            }
        }
        
        // Add the last interval
        totalDuration += currentEnd.timeIntervalSince(currentStart)
        
        return totalDuration
    }
    
    /// Fetch step count data for the specified date range
    func fetchStepCount(startDate: Date, endDate: Date) async throws -> [HealthDataPoint] {
        guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else {
            throw HealthKitError.dataTypeNotAvailable
        }
        
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        
        return try await withCheckedThrowingContinuation { continuation in
            // Use statistics collection to get daily totals
            let interval = DateComponents(day: 1)
            let query = HKStatisticsCollectionQuery(
                quantityType: stepType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: startDate,
                intervalComponents: interval
            )
            
            query.initialResultsHandler = { _, results, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let results = results else {
                    continuation.resume(returning: [])
                    return
                }
                
                var dataPoints: [HealthDataPoint] = []
                
                results.enumerateStatistics(from: startDate, to: endDate) { statistics, _ in
                    if let sum = statistics.sumQuantity() {
                        let steps = sum.doubleValue(for: .count())
                        dataPoints.append(HealthDataPoint(
                            date: statistics.startDate,
                            value: steps
                        ))
                    }
                }
                
                continuation.resume(returning: dataPoints)
            }
            
            healthStore.execute(query)
        }
    }
    
    /// Fetch workouts for the specified date range
    func fetchWorkouts(startDate: Date, endDate: Date) async throws -> [WorkoutData] {
        let workoutType = HKObjectType.workoutType()
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: workoutType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]) { _, samples, error in
                
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let workouts = samples as? [HKWorkout] else {
                    continuation.resume(returning: [])
                    return
                }
                
                let workoutData = workouts.map { workout in
                    // Handle energy burned for iOS 18+
                    var energyBurned: Double?
                    if #available(iOS 18.0, *) {
                        if let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned),
                           let statistics = workout.statistics(for: energyType),
                           let sum = statistics.sumQuantity() {
                            energyBurned = sum.doubleValue(for: .kilocalorie())
                        }
                    } else {
                        energyBurned = workout.totalEnergyBurned?.doubleValue(for: .kilocalorie())
                    }
                    
                    return WorkoutData(
                        workoutType: workout.workoutActivityType,
                        startDate: workout.startDate,
                        endDate: workout.endDate,
                        duration: workout.duration,
                        totalEnergyBurned: energyBurned,
                        totalDistance: workout.totalDistance?.doubleValue(for: .meter())
                    )
                }
                
                continuation.resume(returning: workoutData)
            }
            
            healthStore.execute(query)
        }
    }
    
}

enum HealthKitError: Error {
    case dataTypeNotAvailable
    case authorizationDenied
    case noData
}
