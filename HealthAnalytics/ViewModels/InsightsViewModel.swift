//
//  InsightsViewModel.swift (FIXED)
//  HealthAnalytics
//

import Foundation
import SwiftUI
import SwiftData
import HealthKit
import Combine

@MainActor
class InsightsViewModel: ObservableObject {
    
    // MARK: - Published Properties
    @Published var sleepPerformanceInsight: CorrelationEngine.SleepPerformanceInsight?
    @Published var activityTypeInsights: [CorrelationEngine.ActivityTypeInsight] = []
    @Published var dataSummary: [(activityType: String, goodSleep: Int, poorSleep: Int)] = []
    @Published var simpleInsights: [CorrelationEngine.SimpleInsight] = []
    @Published var recoveryInsights: [CorrelationEngine.RecoveryInsight] = []
    @Published var hrvPerformanceInsights: [CorrelationEngine.HRVPerformanceInsight] = []
    @Published var trainingLoadSummary: TrainingLoadCalculator.TrainingLoadSummary?
    @Published var metricTrends: [MetricTrend] = []
    @Published var recommendations: [ActionableRecommendations.Recommendation] = []
    @Published var readinessAssessment: PredictiveReadinessService.ReadinessAssessment?
    @Published var acwrTrend: [ACWRDataPoint] = []
    @Published var proteinRecoveryInsight: NutritionCorrelationEngine.ProteinRecoveryInsight?
    @Published var proteinPerformanceInsights: [NutritionCorrelationEngine.ProteinPerformanceInsight] = []
    @Published var carbPerformanceInsights: [NutritionCorrelationEngine.CarbPerformanceInsight] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var primaryActivity: String = "Ride"
    
    // SwiftData
    var modelContainer: ModelContainer?
    
    // MARK: - Configuration
    
    func configure(container: ModelContainer) {
        self.modelContainer = container
    }
    
    // MARK: - Main Analysis
    
    func analyzeData() async {
        guard let container = modelContainer else {
            errorMessage = "Database not configured"
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        do {
            let context = container.mainContext
            
            // Fetch all data (respecting data window)
            var workoutDescriptor: FetchDescriptor<StoredWorkout>
            var metricDescriptor: FetchDescriptor<StoredHealthMetric>
            var nutritionDescriptor: FetchDescriptor<StoredNutrition>
            
            // Apply data window filter if set
            if let cutoffDate = DataWindowManager.getCutoffDate() {
                workoutDescriptor = FetchDescriptor<StoredWorkout>(
                    predicate: #Predicate { workout in
                        workout.startDate >= cutoffDate
                    }
                )
                metricDescriptor = FetchDescriptor<StoredHealthMetric>(
                    predicate: #Predicate { metric in
                        metric.date >= cutoffDate
                    }
                )
                nutritionDescriptor = FetchDescriptor<StoredNutrition>(
                    predicate: #Predicate { nutrition in
                        nutrition.date >= cutoffDate
                    }
                )
            } else {
                workoutDescriptor = FetchDescriptor<StoredWorkout>()
                metricDescriptor = FetchDescriptor<StoredHealthMetric>()
                nutritionDescriptor = FetchDescriptor<StoredNutrition>()
            }
            
            let storedWorkouts = try context.fetch(workoutDescriptor)
            let storedHealthMetrics = try context.fetch(metricDescriptor)
            let storedNutrition = try context.fetch(nutritionDescriptor)
            
            // Convert to working models
            let workouts = storedWorkouts.map { WorkoutData(from: $0) }
            let nutrition = storedNutrition.map { DailyNutrition(from: $0) }
            
            // DEBUG: Check if today's workout is included
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            let todaysWorkouts = workouts.filter { calendar.isDate($0.startDate, inSameDayAs: today) }
            print("📊 DEBUG - Workouts Analysis:")
            print("   Total workouts: \(workouts.count)")
            print("   Today's workouts: \(todaysWorkouts.count)")
            if !todaysWorkouts.isEmpty {
                for workout in todaysWorkouts {
                    print("   - \(workout.workoutType): \(workout.duration/3600)h at \(workout.startDate.formatted(date: .omitted, time: .shortened))")
                }
            }
            
            // Convert health metrics - check what properties your StoredHealthMetric actually has
            let sleepData = storedHealthMetrics.filter { $0.type == "Sleep" }
                .map { HealthDataPoint(date: $0.date, value: $0.value) }
            let hrvData = storedHealthMetrics.filter { $0.type == "HRV" }
                .map { HealthDataPoint(date: $0.date, value: $0.value) }
            let rhrData = storedHealthMetrics.filter { $0.type == "RHR" }
                .map { HealthDataPoint(date: $0.date, value: $0.value) }
            let stepData = storedHealthMetrics.filter { $0.type == "Steps" }
                .map { HealthDataPoint(date: $0.date, value: $0.value) }
            let weightData = storedHealthMetrics.filter { $0.type == "Weight" }
                .map { HealthDataPoint(date: $0.date, value: $0.value) }
            
            // Determine primary activity
            primaryActivity = determinePrimaryActivity(from: workouts)
            print("🎯 Primary Activity: \(primaryActivity)")
            
            // Run all analyses
            let correlationEngine = CorrelationEngine()
            let nutritionEngine = NutritionCorrelationEngine()
            let loadCalculator = TrainingLoadCalculator()
            let trendDetector = TrendDetector()
            
            // Sleep & Performance
            sleepPerformanceInsight = correlationEngine.analyzeSleepVsPerformanceCombined(
                sleepData: sleepData,
                healthKitWorkouts: workouts,
                stravaActivities: []
            )
            
            activityTypeInsights = correlationEngine.analyzeSleepVsPerformanceByActivityType(
                sleepData: sleepData,
                healthKitWorkouts: workouts,
                stravaActivities: []
            )
            
            dataSummary = correlationEngine.getDataSummary(
                sleepData: sleepData,
                healthKitWorkouts: workouts,
                stravaActivities: []
            )
            
            // Simple insights
            simpleInsights = correlationEngine.generateSimpleInsights(
                sleepData: sleepData,
                healthKitWorkouts: workouts,
                stravaActivities: [],
                restingHRData: rhrData,
                hrvData: hrvData
            )
            
            // Recovery status
            recoveryInsights = correlationEngine.analyzeRecoveryStatus(
                restingHRData: rhrData,
                hrvData: hrvData
            )
            
            // HRV vs Performance
            hrvPerformanceInsights = correlationEngine.analyzeHRVVsPerformance(
                hrvData: hrvData,
                healthKitWorkouts: workouts,
                stravaActivities: []
            )
            
            // Training load
            trainingLoadSummary = loadCalculator.calculateTrainingLoad(
                healthKitWorkouts: workouts,
                stravaActivities: [],
                stepData: stepData
            )
            
            // Trends
            metricTrends = trendDetector.detectTrends(
                restingHRData: rhrData,
                hrvData: hrvData,
                sleepData: sleepData,
                stepData: stepData,
                weightData: weightData,
                workouts: workouts
            )
            
            // Nutrition
            proteinRecoveryInsight = nutritionEngine.analyzeProteinVsRecovery(
                nutritionData: nutrition,
                restingHRData: rhrData,
                hrvData: hrvData
            )
            
            proteinPerformanceInsights = nutritionEngine.analyzeProteinVsPerformance(
                nutritionData: nutrition,
                healthKitWorkouts: workouts,
                stravaActivities: []
            )
            
            carbPerformanceInsights = nutritionEngine.analyzeCarbsVsPerformance(
                nutritionData: nutrition,
                healthKitWorkouts: workouts,
                stravaActivities: []
            )
            
            // IMPROVED ACWR Calculation
            let readinessService = PredictiveReadinessService()
            readinessAssessment = readinessService.calculateReadiness(
                stravaActivities: [],
                healthKitWorkouts: workouts
            )
            
            acwrTrend = calculateImprovedACWRTrend(
                workouts: workouts,
                readinessService: readinessService
            )
            
            // Recommendations
            let injuryRisk = InjuryRiskCalculator().assessInjuryRisk(
                trainingLoad: trainingLoadSummary,
                recoveryStatus: recoveryInsights,
                trends: metricTrends
            )
            
            recommendations = ActionableRecommendations().generateRecommendations(
                trainingLoad: trainingLoadSummary,
                recoveryInsights: recoveryInsights,
                trends: metricTrends,
                injuryRisk: injuryRisk
            )
            
        } catch {
            errorMessage = "Failed to analyze data: \(error.localizedDescription)"
            print("❌ Analysis error: \(error)")
        }
        
        isLoading = false
    }
    
    // MARK: - Primary Activity Detection
    
    private func determinePrimaryActivity(from workouts: [WorkoutData]) -> String {
        let calendar = Calendar.current
        let now = Date()
        guard let ninetyDaysAgo = calendar.date(byAdding: .day, value: -90, to: now) else {
            return "Ride"
        }
        
        let recentWorkouts = workouts.filter { $0.startDate >= ninetyDaysAgo }
        
        var counts: [String: Int] = [:]
        for workout in recentWorkouts {
            let activityType: String
            switch workout.workoutType {
            case .cycling:
                activityType = "Ride"
            case .running:
                activityType = "Run"
            case .swimming:
                activityType = "Swim"
            default:
                continue
            }
            counts[activityType, default: 0] += 1
        }
        
        print("📊 Activity Breakdown (90 days):")
        for (type, count) in counts.sorted(by: { $0.value > $1.value }) {
            print("   \(type): \(count)")
        }
        
        return counts.max(by: { $0.value < $1.value })?.key ?? "Ride"
    }
    
    // MARK: - IMPROVED ACWR Trend Calculation
    
    private func calculateImprovedACWRTrend(
        workouts: [WorkoutData],
        readinessService: PredictiveReadinessService
    ) -> [ACWRDataPoint] {
        
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var trend: [ACWRDataPoint] = []
        
        // Calculate daily training loads
        var dailyLoads: [Date: Double] = [:]
        for workout in workouts {
            let day = calendar.startOfDay(for: workout.startDate)
            let load = calculateWorkoutLoad(workout)
            dailyLoads[day, default: 0] += load
        }
        
        // Calculate ACWR for each of the last 7 days
        for dayOffset in (0...6).reversed() {
            guard let targetDate = calendar.date(byAdding: .day, value: -dayOffset, to: today) else {
                continue
            }
            
            // Calculate acute load (7 days before target)
            var acuteSum: Double = 0
            for i in 0..<7 {
                if let day = calendar.date(byAdding: .day, value: -i, to: targetDate) {
                    acuteSum += dailyLoads[day] ?? 0
                }
            }
            let acuteLoad = acuteSum / 7.0
            
            // Calculate chronic load (28 days before target)
            var chronicSum: Double = 0
            for i in 0..<28 {
                if let day = calendar.date(byAdding: .day, value: -i, to: targetDate) {
                    chronicSum += dailyLoads[day] ?? 0
                }
            }
            let chronicLoad = chronicSum / 28.0
            
            // Calculate ratio
            let acwr = chronicLoad > 0 ? acuteLoad / chronicLoad : 0
            
            trend.append(ACWRDataPoint(date: targetDate, value: acwr))
        }
        
        print("📊 ACWR Trend (7 days):")
        let formatter = DateFormatter()
        formatter.dateFormat = "E"
        for day in trend {
            print("   \(formatter.string(from: day.date)): \(String(format: "%.2f", day.value))")
        }
        
        return trend
    }
    
    private func calculateWorkoutLoad(_ workout: WorkoutData) -> Double {
        let durationHours = workout.duration / 3600.0
        
        let baseLoad: Double
        switch workout.workoutType {
        case .running:
            baseLoad = durationHours * 65
        case .cycling:
            baseLoad = durationHours * 75
        case .swimming:
            baseLoad = durationHours * 70
        case .hiking, .walking:
            baseLoad = durationHours * 30
        case .functionalStrengthTraining, .traditionalStrengthTraining:
            baseLoad = durationHours * 50
        default:
            baseLoad = durationHours * 50
        }
        
        return baseLoad
    }
}
