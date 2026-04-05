//
//  SleepViewModel.swift
//  HealthAnalytics
//

import Foundation
import HealthKit
import Combine

@MainActor
class SleepViewModel: ObservableObject {
    @Published var sleepStages: [SleepStageData] = []
    @Published var sleepHistory: [HealthDataPoint] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let healthStore = HKHealthStore()
    
    struct SleepStageData: Identifiable {
        let id = UUID()
        let stage: String
        let durationHours: Double
        let startDate: Date
        let endDate: Date
    }
    
    func fetchSleepData() async {
        isLoading = true
        errorMessage = nil
        
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.fetchLastNightSleepStages() }
            group.addTask { await self.fetchSleepHistory() }
        }
        
        isLoading = false
    }
    
    func fetchLastNightSleepStages() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            errorMessage = "HealthKit is not available on this device."
            return
        }
        
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            errorMessage = "Sleep analysis type is not available."
            return
        }
        
        do {
            let status = healthStore.authorizationStatus(for: sleepType)
            if status == .notDetermined {
                try await healthStore.requestAuthorization(toShare: [], read: [sleepType])
            }
            
            // Query last 24 hours
            let endDate = Date()
            let startDate = Calendar.current.date(byAdding: .day, value: -1, to: endDate)!
            let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictEndDate)
            
            let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            
            let samples = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[HKSample], Error>) in
                let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sortDescriptor]) { _, samples, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: samples ?? [])
                    }
                }
                healthStore.execute(query)
            }
            
            var stages: [SleepStageData] = []
            
            for sample in samples.compactMap({ $0 as? HKCategorySample }) {
                let duration = sample.endDate.timeIntervalSince(sample.startDate) / 3600.0
                guard duration > 0 else { continue }
                
                let stageName: String
                switch sample.value {
                case HKCategoryValueSleepAnalysis.asleepCore.rawValue:
                    stageName = "Core/Light"
                case HKCategoryValueSleepAnalysis.asleepDeep.rawValue:
                    stageName = "Deep"
                case HKCategoryValueSleepAnalysis.asleepREM.rawValue:
                    stageName = "REM"
                case HKCategoryValueSleepAnalysis.awake.rawValue:
                    stageName = "Awake"
                default:
                    // Ignore unspecified or "in bed" to avoid double counting if stages exist
                    continue
                }
                
                stages.append(SleepStageData(
                    stage: stageName,
                    durationHours: duration,
                    startDate: sample.startDate,
                    endDate: sample.endDate
                ))
            }
            
            self.sleepStages = stages
            
        } catch {
            errorMessage = "Failed to fetch sleep stages: \(error.localizedDescription)"
        }
    }
    
    func fetchSleepHistory() async {
        // Fetch last 30 days of sleep duration
        let endDate = Date()
        let startDate = Calendar.current.date(byAdding: .day, value: -30, to: endDate)!
        
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return }
        
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictEndDate)
        
        do {
            let samples = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[HKSample], Error>) in
                let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: samples ?? [])
                    }
                }
                healthStore.execute(query)
            }
            
            // Aggregate by day
            var dailyTotals: [Date: Double] = [:]
            let calendar = Calendar.current
            
            for sample in samples.compactMap({ $0 as? HKCategorySample }) {
                // Filter out "In Bed" and "Awake" for duration
                guard sample.value != HKCategoryValueSleepAnalysis.inBed.rawValue &&
                      sample.value != HKCategoryValueSleepAnalysis.awake.rawValue else { continue }
                
                let day = calendar.startOfDay(for: sample.startDate)
                let duration = sample.endDate.timeIntervalSince(sample.startDate) / 3600.0
                dailyTotals[day, default: 0] += duration
            }
            
            self.sleepHistory = dailyTotals.map { HealthDataPoint(date: $0.key, value: $0.value) }
                .sorted { $0.date < $1.date }
            
        } catch {
            print("Failed to fetch sleep history: \(error)")
        }
    }
    
    var totalSleepHours: Double {
        sleepStages.filter { $0.stage != "Awake" }.reduce(0) { $0 + $1.durationHours }
    }
    
    var totalSleepString: String {
        let totalHours = totalSleepHours
        let hours = Int(totalHours)
        let minutes = Int((totalHours - Double(hours)) * 60)
        return "\(hours)h \(minutes)m"
    }
}
