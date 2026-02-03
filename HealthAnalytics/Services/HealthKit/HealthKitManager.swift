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
        HKObjectType.quantityType(forIdentifier: .bodyMass)!,
        HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
        HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
        HKObjectType.quantityType(forIdentifier: .vo2Max)!,
        HKObjectType.quantityType(forIdentifier: .cyclingPower)!,
        HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
        HKObjectType.workoutType(),
        
        // Nutrition types
        HKObjectType.quantityType(forIdentifier: .dietaryEnergyConsumed)!,
        HKObjectType.quantityType(forIdentifier: .dietaryProtein)!,
        HKObjectType.quantityType(forIdentifier: .dietaryCarbohydrates)!,
        HKObjectType.quantityType(forIdentifier: .dietaryFatTotal)!,
        HKObjectType.quantityType(forIdentifier: .dietaryFiber)!,
        HKObjectType.quantityType(forIdentifier: .dietarySugar)!,
        HKObjectType.quantityType(forIdentifier: .dietaryWater)!
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
                
                // Group samples by "sleep night"
                // Sleep before noon belongs to the previous night
                // Sleep after noon belongs to tonight
                let samplesByNight = Dictionary(grouping: samples) { sample in
                    let hour = calendar.component(.hour, from: sample.startDate)
                    
                    if hour < 12 {
                        // Before noon - belongs to previous night
                        // So shift back one day
                        return calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: sample.startDate))!
                    } else {
                        // After noon - belongs to tonight
                        return calendar.startOfDay(for: sample.startDate)
                    }
                }
                
                var dataPoints: [HealthDataPoint] = []
                
                for (night, nightSamples) in samplesByNight {
                    let duration = self.calculateEffectiveSleepDuration(samples: nightSamples)
                    
                    if duration > 0 {
                        let hours = duration / 3600.0
                        
                        // The wake-up day is the day after the "night" date
                        // Since we already shifted morning sleep back one day
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
    
    /// Fetch body weight data for the specified date range
    func fetchWeight(startDate: Date, endDate: Date) async throws -> [HealthDataPoint] {
        guard let weightType = HKQuantityType.quantityType(forIdentifier: .bodyMass) else {
            throw HealthKitError.dataTypeNotAvailable
        }
        
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: weightType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, error in
                
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let samples = samples as? [HKQuantitySample] else {
                    continuation.resume(returning: []) // Ensure it returns even if empty
                    return
                }
                
                let dataPoints = samples.map { sample in
                    HealthDataPoint(
                        date: sample.startDate,
                        value: sample.quantity.doubleValue(for: HKUnit.pound())
                    )
                }
                
                continuation.resume(returning: dataPoints)
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
 //               print("   ⚠️ AutoSleep detected but empty. Falling back to Apple Watch.")
                targetSamples = samples.filter {
                    !$0.sourceRevision.source.bundleIdentifier.lowercased().contains("autosleep")
                }
            }
        } else {
            // No AutoSleep - use all available data (typically Apple Watch)
            targetSamples = samples
        }
        
        // DEBUG: Print details for Jan 26, 2026
        if !targetSamples.isEmpty {
            let calendar = Calendar.current
            let firstSample = targetSamples[0]
            let hour = calendar.component(.hour, from: firstSample.startDate)
            
            let nightDate: Date
            if hour < 12 {
                // Before noon - belongs to previous night
                nightDate = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: firstSample.startDate))!
            } else {
                // After noon - belongs to tonight
                nightDate = calendar.startOfDay(for: firstSample.startDate)
            }
            
            // Check if this is Jan 25, 2026 (night of Jan 25 = wakes up Jan 26)
            _ = calendar.dateComponents([.year, .month, .day], from: nightDate)
/*            if components.year == 2026 && components.month == 1 && components.day == 25 {
                print("   🔍 DEBUG Jan 26 ALL samples (including awake):")
                print("      Total samples: \(targetSamples.count)")
                
                // Sort all samples by time for readability
                let sortedAll = targetSamples.sorted { $0.startDate < $1.startDate }
                for (index, sample) in sortedAll.enumerated() {
                    let duration = sample.endDate.timeIntervalSince(sample.startDate) / 3600.0
                    let stageName: String
                    if sample.value == HKCategoryValueSleepAnalysis.asleepCore.rawValue {
                        stageName = "Core"
                    } else if sample.value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue {
                        stageName = "Deep"
                    } else if sample.value == HKCategoryValueSleepAnalysis.asleepREM.rawValue {
                        stageName = "REM"
                    } else if sample.value == HKCategoryValueSleepAnalysis.awake.rawValue {
                        stageName = "AWAKE"
                    } else if sample.value == HKCategoryValueSleepAnalysis.inBed.rawValue {
                        stageName = "InBed"
                    } else {
                        stageName = "Unspecified"
                    }
                    print("      [\(index+1)] \(stageName): \(String(format: "%.2f", duration))h | \(sample.startDate.formatted(date: .omitted, time: .shortened)) - \(sample.endDate.formatted(date: .omitted, time: .shortened))")
                }
            }*/
        }
        
        // 2. Sort all samples by time and stop counting after significant wake period
        // This matches Apple Health's behavior of only counting the main sleep session
        let sortedSamples = targetSamples.sorted { $0.startDate < $1.startDate }
        var validSamples: [HKCategorySample] = []
        let significantWakeThreshold: TimeInterval = 30 * 60 // 30 minutes
        
        for sample in sortedSamples {
            let val = sample.value
            let isSleep = val == HKCategoryValueSleepAnalysis.asleepCore.rawValue ||
                         val == HKCategoryValueSleepAnalysis.asleepDeep.rawValue ||
                         val == HKCategoryValueSleepAnalysis.asleepREM.rawValue ||
                         val == HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue
            
            let isAwake = val == HKCategoryValueSleepAnalysis.awake.rawValue
            
            if isSleep {
                validSamples.append(sample)
            } else if isAwake {
                // Check if this is a significant wake period (30+ minutes)
                let awakeDuration = sample.endDate.timeIntervalSince(sample.startDate)
                if awakeDuration >= significantWakeThreshold {
                    // Stop counting - main sleep session is over
                    break
                }
            }
        }
        
        // DEBUG: Show only sleep samples
        if !validSamples.isEmpty {
            let calendar = Calendar.current
            let firstSample = validSamples[0]
            let hour = calendar.component(.hour, from: firstSample.startDate)
            
            let nightDate: Date
            if hour < 12 {
                nightDate = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: firstSample.startDate))!
            } else {
                nightDate = calendar.startOfDay(for: firstSample.startDate)
            }
            
            _ = calendar.dateComponents([.year, .month, .day], from: nightDate)
/*            if components.year == 2026 && components.month == 1 && components.day == 25 {
                print("   🔍 DEBUG Jan 26 SLEEP-ONLY samples (stopped at long wake):")

                print("      Total samples: \(validSamples.count)")
                
                // Sort by time for readability
                let sortedSleep = validSamples.sorted { $0.startDate < $1.startDate }
                for (index, sample) in sortedSleep.enumerated() {
                    let duration = sample.endDate.timeIntervalSince(sample.startDate) / 3600.0
                    let stageName: String
                    if sample.value == HKCategoryValueSleepAnalysis.asleepCore.rawValue {
                        stageName = "Core"
                    } else if sample.value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue {
                        stageName = "Deep"
                    } else if sample.value == HKCategoryValueSleepAnalysis.asleepREM.rawValue {
                        stageName = "REM"
                    } else {
                        stageName = "Unspecified"
                    }
                    print("      [\(index+1)] \(stageName): \(String(format: "%.2f", duration))h | \(sample.startDate.formatted(date: .omitted, time: .shortened)) - \(sample.endDate.formatted(date: .omitted, time: .shortened))")
                }
            }*/
        }
        
        // 3. Merge overlapping intervals to prevent double-counting
        let duration = calculateUniqueDuration(validSamples)
        
/*       // DEBUG: Show merge result for Jan 25 night
        if let first = validSamples.first {
            let calendar = Calendar.current
            let hour = calendar.component(.hour, from: first.startDate)
            
            let nightDate: Date
            if hour < 12 {
                nightDate = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: first.startDate))!
            } else {
                nightDate = calendar.startOfDay(for: first.startDate)
            }
            
            let components = calendar.dateComponents([.year, .month, .day], from: nightDate)
            if components.year == 2026 && components.month == 1 && components.day == 25 {
                let hours = duration / 3600.0
                print("      ✅ After merge: \(String(format: "%.2f", hours))h")
            }
        }
*/
        return duration
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
                
                // We need to fetch power data for each workout
                let group = DispatchGroup()
                var workoutDataArray: [WorkoutData] = []
                
                for workout in workouts {
                    group.enter()
                    
                    // Detect workout source
                    let bundleId = workout.sourceRevision.source.bundleIdentifier.lowercased()
                    let source: WorkoutSource
                    if bundleId.contains("apple") || bundleId.contains("watch") {
                        source = .appleWatch
                    } else if bundleId.contains("strava") {
                        source = .strava
                    } else {
                        source = .other
                    }
                    
                    // Fetch average power for this workout
                    self.fetchAveragePower(for: workout) { averagePower in
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
                        
                        let data = WorkoutData(
                            workoutType: workout.workoutActivityType,
                            startDate: workout.startDate,
                            endDate: workout.endDate,
                            duration: workout.duration,
                            totalEnergyBurned: energyBurned,
                            totalDistance: workout.totalDistance?.doubleValue(for: .meter()),
                            averagePower: averagePower,
                            source: source
                        )
                        
                        workoutDataArray.append(data)
                        group.leave()
                    }
                }
                
                group.notify(queue: .main) {
                    // Sort by start date (descending) to match original behavior
                    let sortedData = workoutDataArray.sorted { $0.startDate > $1.startDate }
                    continuation.resume(returning: sortedData)
                }
            }
            
            healthStore.execute(query)
        }
    }
    
    // MARK: - Power Data Fetching
    
    /// Fetches average power for a specific workout
    private func fetchAveragePower(for workout: HKWorkout, completion: @escaping (Double?) -> Void) {
        guard let powerType = HKQuantityType.quantityType(forIdentifier: .cyclingPower) else {
            completion(nil)
            return
        }
        
        let predicate = HKQuery.predicateForSamples(
            withStart: workout.startDate,
            end: workout.endDate,
            options: .strictStartDate
        )
        
        let query = HKStatisticsQuery(
            quantityType: powerType,
            quantitySamplePredicate: predicate,
            options: .discreteAverage
        ) { _, statistics, error in
            
            // Silently handle errors - workout just won't have power data
            if error != nil {
                completion(nil)
                return
            }
            
            guard let statistics = statistics,
                  let averageQuantity = statistics.averageQuantity() else {
                completion(nil)
                return
            }
            
            let averagePower = averageQuantity.doubleValue(for: .watt())
            completion(averagePower)
        }
        
        healthStore.execute(query)
    }
    
    // MARK: - Nutrition Data Fetching
    
    /// Fetches complete nutrition data for a specific date
    func fetchDailyNutrition(for date: Date) async -> DailyNutrition {
        let calendar = Calendar.current
        let startDate = calendar.startOfDay(for: date)
        guard let endDate = calendar.date(byAdding: .day, value: 1, to: startDate) else {
            return DailyNutrition(
                date: startDate,
                totalCalories: 0,
                totalProtein: 0,
                totalCarbs: 0,
                totalFat: 0,
                totalFiber: nil,
                totalSugar: nil,
                totalWater: nil,
                breakfast: nil, lunch: nil, dinner: nil, snacks: nil
            )
        }
        
        print("📅 Fetching nutrition for \(startDate.formatted(date: .abbreviated, time: .omitted))")
        
        // Fetch all nutrition data concurrently - no longer throws
        let totalCal = await fetchNutritionSum(for: .dietaryEnergyConsumed, startDate: startDate, endDate: endDate, unit: .kilocalorie())
        let totalPro = await fetchNutritionSum(for: .dietaryProtein, startDate: startDate, endDate: endDate, unit: .gram())
        let totalCarb = await fetchNutritionSum(for: .dietaryCarbohydrates, startDate: startDate, endDate: endDate, unit: .gram())
        let totalFat = await fetchNutritionSum(for: .dietaryFatTotal, startDate: startDate, endDate: endDate, unit: .gram())
        let totalFib = await fetchNutritionSum(for: .dietaryFiber, startDate: startDate, endDate: endDate, unit: .gram())
        let totalSug = await fetchNutritionSum(for: .dietarySugar, startDate: startDate, endDate: endDate, unit: .gram())
        let totalH2O = await fetchNutritionSum(for: .dietaryWater, startDate: startDate, endDate: endDate, unit: .liter())
        
        if totalCal > 0 {
            print("   ✅ Found data: \(Int(totalCal)) cal, \(Int(totalPro))g P, \(Int(totalCarb))g C, \(Int(totalFat))g F")
        }
        
        return DailyNutrition(
            date: startDate,
            totalCalories: totalCal,
            totalProtein: totalPro,
            totalCarbs: totalCarb,
            totalFat: totalFat,
            totalFiber: totalFib > 0 ? totalFib : nil,
            totalSugar: totalSug > 0 ? totalSug : nil,
            totalWater: totalH2O > 0 ? totalH2O : nil,
            breakfast: nil,
            lunch: nil,
            dinner: nil,
            snacks: nil
        )
    }
    
    /// Fetches nutrition data for a date range
    func fetchNutrition(startDate: Date, endDate: Date) async -> [DailyNutrition] {
        let calendar = Calendar.current
        var nutrition: [DailyNutrition] = []
        
        var currentDate = calendar.startOfDay(for: startDate)
        let end = calendar.startOfDay(for: endDate)
        
        print("🔄 Fetching nutrition from \(currentDate.formatted(date: .abbreviated, time: .omitted)) to \(end.formatted(date: .abbreviated, time: .omitted))")
        
        while currentDate <= end {
            let dayNutrition = await fetchDailyNutrition(for: currentDate)
            nutrition.append(dayNutrition)
            
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: currentDate) else { break }
            currentDate = nextDay
        }
        
        return nutrition
    }
    
    // MARK: - Helper Methods
    
    private func fetchNutritionSum(
        for identifier: HKQuantityTypeIdentifier,
        startDate: Date,
        endDate: Date,
        unit: HKUnit
    ) async -> Double {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: identifier) else {
            print("⚠️ Nutrition type not available: \(identifier.rawValue)")
            return 0
        }
        
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, error in
                if let error = error {
                    print("⚠️ Error fetching \(identifier.rawValue): \(error.localizedDescription)")
                    continuation.resume(returning: 0)
                    return
                }
                
                let sum = statistics?.sumQuantity()?.doubleValue(for: unit) ?? 0
                if sum > 0 {
//                    print("✅ Found \(identifier.rawValue): \(String(format: "%.1f", sum)) \(unit)")
                } else {
                    print("⚠️ No data for \(identifier.rawValue)")
                }
                continuation.resume(returning: sum)
            }
            
            healthStore.execute(query)
        }
    }
    
    private func fetchNutritionByMeal(
        startDate: Date,
        endDate: Date
    ) async throws -> [MealNutrition] {
        
        // Simplified: Just return empty array for now
        // We'll focus on daily totals first, then add meal breakdown later
        print("📊 Skipping meal-level data for now - focusing on daily totals")
        return []
    }
    
}

enum HealthKitError: Error {
    case dataTypeNotAvailable
    case authorizationDenied
    case noData
}
