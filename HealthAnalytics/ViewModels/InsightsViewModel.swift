//
//  InsightsViewModel.swift
//  HealthAnalytics
//
//  Created by Craig Faist on 1/25/26.
//  Fixed: Corrected TrainingLoadCalculator.TrainingLoadSummary.LoadStatus type access.
//

import Foundation
import SwiftData
import SwiftUI
import HealthKit
import Combine

@MainActor
class InsightsViewModel: ObservableObject {
    
    // MARK: - UI State
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedTrendDuration: Int = 90
    
    // MARK: - Data Properties for View
    
    // Recommendations
    @Published var recommendations: [ActionableRecommendations.Recommendation] = []
    
    // ACWR & Readiness
    struct ReadinessAssessment {
        let state: (label: String, color: Color)
        let acwr: Double
    }
    @Published var readinessAssessment: ReadinessAssessment?
    @Published var acwrTrend: [TrendPoint] = []
    
    // Insight Arrays
    @Published var simpleInsights: [CorrelationEngine.SimpleInsight] = []
    @Published var recoveryInsights: [CorrelationEngine.RecoveryInsight] = []
    @Published var metricTrends: [MetricTrend] = []
    @Published var hrvPerformanceInsights: [CorrelationEngine.HRVPerformanceInsight] = []
    @Published var activityTypeInsights: [CorrelationEngine.ActivityTypeInsight] = []
    
    // Nutrition Specific
    @Published var proteinRecoveryInsight: NutritionCorrelationEngine.ProteinRecoveryInsight?
    @Published var proteinPerformanceInsights: [NutritionCorrelationEngine.ProteinPerformanceInsight] = []
    @Published var carbPerformanceInsights: [NutritionCorrelationEngine.CarbPerformanceInsight] = []
    @Published var nutritionCorrelations: [NutritionCorrelation] = []
    
    // Charts
    @Published var sleepVsPowerData: [CorrelationPoint] = []
    @Published var weeklyTrends: [TrendPoint] = []
    
    @Published var trainingLoadSummary: TrainingLoadCalculator.TrainingLoadSummary?
    @Published var dataSummary: [(activityType: String, goodSleep: Int, poorSleep: Int)] = []

    // MARK: - Internal Structs
    struct CorrelationPoint: Identifiable {
        let id = UUID()
        let xValue: Double
        let yValue: Double
        let date: Date
        let category: String
    }
    
    struct NutritionCorrelation: Identifiable {
        let id = UUID()
        let nutrient: String
        let correlationScore: Double
        let insight: String
    }
    
    struct TrendPoint: Identifiable {
        let id = UUID()
        let date: Date
        let value: Double
        let metric1: Double?
        let metric2: Double?
    }

    // MARK: - Engines
    private let correlationEngine = CorrelationEngine()
    private let nutritionEngine = NutritionCorrelationEngine()
    private let trainingLoadCalc = TrainingLoadCalculator()
    private let trendDetector = TrendDetector()
    private let recommendationEngine = ActionableRecommendations()

    // MARK: - Main Actions
    
    func analyzeData() async {
        await loadInsights()
    }
    
    func updateTimeRange(_ days: Int) async {
        selectedTrendDuration = days
        await loadInsights()
    }
    
    func loadInsights() async {
        isLoading = true
        errorMessage = nil
        
        await SyncManager.shared.performGlobalSync()
        
        do {
            print("📈 Calculating Insights from SwiftData...")
            let context = HealthDataContainer.shared.mainContext
            let endDate = Date()
            guard let startDate = Calendar.current.date(byAdding: .day, value: -120, to: endDate) else { return }
            
            // 1. Fetch Data
            let storedWorkouts = try context.fetch(FetchDescriptor<StoredWorkout>(predicate: #Predicate { $0.startDate >= startDate }, sortBy: [SortDescriptor(\.startDate)]))
            let storedMetrics = try context.fetch(FetchDescriptor<StoredHealthMetric>(predicate: #Predicate { $0.date >= startDate }, sortBy: [SortDescriptor(\.date)]))
            let storedNutrition = try context.fetch(FetchDescriptor<StoredNutrition>(predicate: #Predicate { $0.date >= startDate }, sortBy: [SortDescriptor(\.date)]))
            
            // 2. Map to Domain Models
            let workouts = storedWorkouts.map { $0.toWorkoutData() }
            let nutrition = storedNutrition.map { $0.toDailyNutrition() }
            let hrv = storedMetrics.filter { $0.type == "HRV" }.map { $0.toHealthDataPoint() }
            let rhr = storedMetrics.filter { $0.type == "RHR" }.map { $0.toHealthDataPoint() }
            let sleep = storedMetrics.filter { $0.type == "Sleep" }.map { $0.toHealthDataPoint() }
            let steps = storedMetrics.filter { $0.type == "Steps" }.map { $0.toHealthDataPoint() }
            let weight = storedMetrics.filter { $0.type == "BodyMass" }.map { $0.toHealthDataPoint() }
            
            // 3. Run Internal Analysis Logic
            calculateACWR(workouts: workouts)
            
            // Call external engines
            self.simpleInsights = correlationEngine.generateSimpleInsights(
                sleepData: sleep,
                healthKitWorkouts: workouts,
                stravaActivities: [],
                restingHRData: rhr,
                hrvData: hrv
            )
            
            self.recoveryInsights = correlationEngine.analyzeRecoveryStatus(
                restingHRData: rhr,
                hrvData: hrv
            )
            
            self.activityTypeInsights = correlationEngine.analyzeSleepVsPerformanceByActivityType(
                sleepData: sleep,
                healthKitWorkouts: workouts,
                stravaActivities: []
            )
            
            self.hrvPerformanceInsights = correlationEngine.analyzeHRVVsPerformance(
                hrvData: hrv,
                healthKitWorkouts: workouts,
                stravaActivities: []
            )
            
            // Nutrition engines
            self.proteinRecoveryInsight = nutritionEngine.analyzeProteinVsRecovery(
                nutritionData: nutrition,
                restingHRData: rhr,
                hrvData: hrv
            )
            
            self.carbPerformanceInsights = nutritionEngine.analyzeCarbsVsPerformance(
                nutritionData: nutrition,
                healthKitWorkouts: workouts,
                stravaActivities: []
            )
            
            self.proteinPerformanceInsights = nutritionEngine.analyzeProteinVsPerformance(
                nutritionData: nutrition,
                healthKitWorkouts: workouts,
                stravaActivities: []
            )
            
            // Trends & Recs
            self.metricTrends = trendDetector.detectTrends(
                restingHRData: rhr,
                hrvData: hrv,
                sleepData: sleep,
                stepData: steps,
                weightData: weight,
                workouts: workouts
            )
            
            self.recommendations = recommendationEngine.generateRecommendations(
                trainingLoad: self.trainingLoadSummary,
                recoveryInsights: self.recoveryInsights,
                trends: self.metricTrends,
                injuryRisk: nil
            )
            
            // Internal chart helpers
            generateSleepVsPower(workouts: workouts, sleep: sleep)
            generateNutritionCorrelations(workouts: workouts, nutrition: nutrition)
            generateRecoveryTrends(hrv: hrv, rhr: rhr)
            
            self.dataSummary = correlationEngine.getDataSummary(
                sleepData: sleep,
                healthKitWorkouts: workouts,
                stravaActivities: []
            )
            
            isLoading = false
            print("✅ Full Insights Generated")
            
        } catch {
            errorMessage = "Analysis error: \(error.localizedDescription)"
            isLoading = false
            print("❌ Insights error: \(error)")
        }
    }
    
    // MARK: - Internal Logic Implementation
    
    private func calculateACWR(workouts: [WorkoutData]) {
        let today = Date()
        guard let acuteDate = Calendar.current.date(byAdding: .day, value: -7, to: today),
              let chronicDate = Calendar.current.date(byAdding: .day, value: -28, to: today) else { return }
        
        var acuteLoad = 0.0
        var chronicLoad = 0.0
        
        for w in workouts {
            // Simplified Load = Duration (mins) * Intensity Factor (0.8)
            let load = (w.duration / 60.0) * 50.0
            if w.startDate >= acuteDate { acuteLoad += load }
            if w.startDate >= chronicDate { chronicLoad += load }
        }
        
        let acuteAvg = acuteLoad / 7.0
        let chronicAvg = chronicLoad / 28.0
        let ratio = chronicAvg > 0 ? acuteAvg / chronicAvg : 0.0
        
        // FIXED: Use correct enum Type
        let status: TrainingLoadCalculator.TrainingLoadSummary.LoadStatus
        let label: String
        let color: Color
        
        // Determine status based on ratio ranges matching TrainingLoadCalculator.swift
        if ratio < 0.8 {
            status = .fresh
            label = "Fresh"
            color = .blue
        } else if ratio <= 1.3 {
            status = .optimal
            label = "Optimal"
            color = .green
        } else if ratio <= 1.5 {
            status = .fatigued
            label = "Fatigued"
            color = .orange
        } else {
            status = .overreaching
            label = "Overreaching"
            color = .red
        }
        
        // Update Published Properties
        self.readinessAssessment = ReadinessAssessment(state: (label, color), acwr: ratio)
        
        self.trainingLoadSummary = TrainingLoadCalculator.TrainingLoadSummary(
            acuteLoad: acuteAvg,
            chronicLoad: chronicAvg,
            acuteChronicRatio: ratio,
            status: status,
            recommendation: "Maintain current volume."
        )
        
        // Build flat trend for chart
        self.acwrTrend = (0..<7).compactMap { i in
            Calendar.current.date(byAdding: .day, value: -i, to: today).map {
                TrendPoint(date: $0, value: ratio, metric1: nil as Double?, metric2: nil as Double?)
            }
        }.reversed()
    }
    
    private func generateRecoveryTrends(hrv: [HealthDataPoint], rhr: [HealthDataPoint]) {
        let daysToSubtract = -selectedTrendDuration
        guard let cutoffDate = Calendar.current.date(byAdding: .day, value: daysToSubtract, to: Date()) else { return }
        
        var validHRV: [HealthDataPoint] = []
        for p in hrv {
            if p.date >= cutoffDate { validHRV.append(p) }
        }
        
        var trends: [TrendPoint] = []
        for p in validHRV {
            var rhrVal = 0.0
            for r in rhr {
                if Calendar.current.isDate(r.date, inSameDayAs: p.date) {
                    rhrVal = r.value
                    break
                }
            }
            
            trends.append(TrendPoint(
                date: p.date,
                value: p.value,
                metric1: p.value,
                metric2: rhrVal
            ))
        }
        self.weeklyTrends = trends
    }
    
    private func generateSleepVsPower(workouts: [WorkoutData], sleep: [HealthDataPoint]) {
        var points: [CorrelationPoint] = []
        for w in workouts {
            let wDate = Calendar.current.startOfDay(for: w.startDate)
            
            // Explicit loop for finding sleep
            var matchedSleep: HealthDataPoint?
            for s in sleep {
                if Calendar.current.isDate(s.date, inSameDayAs: wDate) {
                    matchedSleep = s
                    break
                }
            }
            
            if let s = matchedSleep {
                // Unwrap optional values safely
                let sleepVal = s.value
                let powerVal = w.averagePower ?? 0
                
                if powerVal > 0 {
                    points.append(CorrelationPoint(xValue: sleepVal, yValue: powerVal, date: w.startDate, category: w.workoutType == .cycling ? "Ride" : "Run"))
                }
            }
        }
        self.sleepVsPowerData = points
    }
    
    private func generateNutritionCorrelations(workouts: [WorkoutData], nutrition: [DailyNutrition]) {
        var highCarbDates: Set<Date> = []
        
        for entry in nutrition {
            // totalCarbs is Double (non-optional based on previous logs)
            if entry.totalCarbs > 300.0 {
                highCarbDates.insert(Calendar.current.startOfDay(for: entry.date))
            }
        }
        
        var highCarbWorkouts: [WorkoutData] = []
        for w in workouts {
            let wDate = Calendar.current.startOfDay(for: w.startDate)
            if highCarbDates.contains(wDate) {
                highCarbWorkouts.append(w)
            }
        }
        
        var totalPower = 0.0
        for w in highCarbWorkouts {
            totalPower += (w.averagePower ?? 0)
        }
        
        let count = Double(highCarbWorkouts.count)
        let avg = count > 0 ? totalPower / count : 0
        
        if avg > 0 {
            self.nutritionCorrelations = [
                NutritionCorrelation(nutrient: "Carbohydrates", correlationScore: 0.8, insight: "High carb days avg \(Int(avg))W power")
            ]
        } else {
            self.nutritionCorrelations = []
        }
    }
}
