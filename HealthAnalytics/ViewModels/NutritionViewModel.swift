//
//  NutritionViewModel.swift
//  HealthAnalytics
//
//  Updated for Local-First Architecture
//

import Foundation
import Combine
import SwiftData
import SwiftUI

@MainActor
class NutritionViewModel: ObservableObject {
    
    @Published var dailyNutrition: [DailyNutrition] = []
    @Published var selectedTimeRange: TimeRange = .week
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // Summary metrics for the view
    @Published var averageCalories: Double = 0
    @Published var averageProtein: Double = 0
    @Published var averageCarbs: Double = 0
    @Published var averageFat: Double = 0
    
    enum TimeRange: String, CaseIterable {
        case week = "Week"
        case month = "Month"
        case threeMonths = "3 Months"
        
        var days: Int {
            switch self {
            case .week: return 7
            case .month: return 30
            case .threeMonths: return 90
            }
        }
    }
    
    func loadNutritionData() async {
        isLoading = true
        errorMessage = nil
        
        // 1. Ensure Global Sync has run to backfill missing days
        await SyncManager.shared.performGlobalSync()
        
        do {
            print("🍎 Loading Nutrition from SwiftData...")
            
            // 2. Calculate Date Range
            let calendar = Calendar.current
            let endDate = Date()
            let startDate = calendar.date(byAdding: .day, value: -selectedTimeRange.days, to: endDate)!
            
            // 3. Fetch from SwiftData
            let context = HealthDataContainer.shared.mainContext
            
            // SwiftData predicate to filter by date
            let predicate = #Predicate<StoredNutrition> { item in
                item.date >= startDate && item.date <= endDate
            }
            
            let descriptor = FetchDescriptor<StoredNutrition>(
                predicate: predicate,
                sortBy: [SortDescriptor(\.date)]
            )
            
            let storedData = try context.fetch(descriptor)
            
            // 4. Map to Domain Model using your DomainMapping extension
            self.dailyNutrition = storedData.map { $0.toDailyNutrition() }
            
            // 5. Calculate Averages for the UI header
            calculateAverages()
            
            print("✅ Loaded \(self.dailyNutrition.count) nutrition entries from storage")
            isLoading = false
            
        } catch {
            errorMessage = "Failed to load nutrition: \(error.localizedDescription)"
            isLoading = false
            print("❌ Nutrition Load Error: \(error)")
        }
    }
    
    private func calculateAverages() {
        guard !dailyNutrition.isEmpty else {
            averageCalories = 0
            averageProtein = 0
            averageCarbs = 0
            averageFat = 0
            return
        }
        
        let count = Double(dailyNutrition.count)
        
        let totalCals = dailyNutrition.reduce(0) { $0 + $1.totalCalories }
        let totalProt = dailyNutrition.reduce(0) { $0 + $1.totalProtein }
        let totalCarb = dailyNutrition.reduce(0) { $0 + $1.totalCarbs }
        let totalFat  = dailyNutrition.reduce(0) { $0 + $1.totalFat }
        
        averageCalories = totalCals / count
        averageProtein = totalProt / count
        averageCarbs = totalCarb / count
        averageFat = totalFat / count
    }
    
    // Helper to update range and reload
    func updateTimeRange(_ range: TimeRange) async {
        selectedTimeRange = range
        await loadNutritionData()
    }
}
