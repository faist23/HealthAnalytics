//
//  NutritionViewModel.swift
//  HealthAnalytics
//
//  Created by Craig Faist on 1/26/26.
//


import Foundation
import Combine

@MainActor
class NutritionViewModel: ObservableObject {
    @Published var nutritionData: [DailyNutrition] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let healthKitManager = HealthKitManager.shared
    
    func loadNutrition() async {
        isLoading = true
        errorMessage = nil
        
        // Get last 60 days (excluding today since it's incomplete)
        let endDate = Date()
        let startDate = Calendar.current.date(byAdding: .day, value: -60, to: endDate) ?? endDate
        
        print("📅 Loading nutrition data:")
        print("   Start: \(startDate.formatted(date: .abbreviated, time: .omitted))")
        print("   End: \(endDate.formatted(date: .abbreviated, time: .omitted))")
        
        nutritionData = await healthKitManager.fetchNutrition(startDate: startDate, endDate: endDate)
        
        let completeDays = nutritionData.filter { $0.isComplete }
        let daysWithAnyData = nutritionData.filter { $0.totalCalories > 0 }
        
        print("📊 Nutrition Data Loaded:")
        print("   Total days: \(nutritionData.count)")
        print("   Days with any data: \(daysWithAnyData.count)")
        print("   Complete days: \(completeDays.count)")
        
        if daysWithAnyData.isEmpty {
            errorMessage = "No nutrition data found in Health app for the last 7 days. Make sure LoseIt is syncing to Apple Health and that nutrition permissions are granted."
        }
        
        isLoading = false
    }
}
