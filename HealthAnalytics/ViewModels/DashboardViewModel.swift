//
//  DashboardViewModel.swift
//  HealthAnalytics
//
//  Created by Craig Faist on 1/25/26.
//


import Foundation
import Combine

@MainActor
class DashboardViewModel: ObservableObject {
    @Published var restingHeartRateData: [HealthDataPoint] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let healthKitManager = HealthKitManager.shared
    
    func loadData() async {
        isLoading = true
        errorMessage = nil
        
        // Get last 7 days
        let endDate = Date()
        let startDate = Calendar.current.date(byAdding: .day, value: -7, to: endDate) ?? endDate
        
        do {
            let data = try await healthKitManager.fetchRestingHeartRate(startDate: startDate, endDate: endDate)
            self.restingHeartRateData = data
        } catch {
            self.errorMessage = "Failed to load heart rate data: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
}