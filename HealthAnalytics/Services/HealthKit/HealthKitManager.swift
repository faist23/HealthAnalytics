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
    
    /// Fetch sleep duration data for the specified date range
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
                
                // Group sleep samples by day and calculate total duration
                var sleepByDay: [Date: TimeInterval] = [:]
                let calendar = Calendar.current
                
                for sample in samples {
                    // Only count "asleep" states (not awake or in bed)
                    if sample.value == HKCategoryValueSleepAnalysis.asleepCore.rawValue ||
                        sample.value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue ||
                        sample.value == HKCategoryValueSleepAnalysis.asleepREM.rawValue ||
                        sample.value == HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue {
                        
                        let dayStart = calendar.startOfDay(for: sample.startDate)
                        let duration = sample.endDate.timeIntervalSince(sample.startDate)
                        sleepByDay[dayStart, default: 0] += duration
                    }
                }
                
                // Convert to data points (hours)
                let dataPoints = sleepByDay.map { date, duration in
                    HealthDataPoint(
                        date: date,
                        value: duration / 3600.0 // Convert seconds to hours
                    )
                }.sorted { $0.date < $1.date }
                
                continuation.resume(returning: dataPoints)
            }
            
            healthStore.execute(query)
        }
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
    
}

enum HealthKitError: Error {
    case dataTypeNotAvailable
    case authorizationDenied
    case noData
}
