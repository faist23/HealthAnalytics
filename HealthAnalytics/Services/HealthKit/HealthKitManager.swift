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
}
