//
//  ReadinessViewModel.swift (FIXED)
//  HealthAnalytics
//

import Foundation
import SwiftUI
import SwiftData
import HealthKit
import Combine

@MainActor
class ReadinessViewModel: ObservableObject {
    
    // MARK: - Published Properties
    @Published var readinessScore: ReadinessAnalyzer.ReadinessScore?
    @Published var intraDayReadiness: RecoveryDecayService.IntraDayReadiness?
    @Published var formIndicator: ReadinessAnalyzer.FormIndicator?
    @Published var performanceWindows: [PerformancePatternAnalyzer.PerformanceWindow] = []
    @Published var optimalTimings: [PerformancePatternAnalyzer.OptimalTiming] = []
    @Published var workoutSequences: [PerformancePatternAnalyzer.WorkoutSequence] = []
    @Published var dailyInstruction: CoachingService.DailyInstruction?
    @Published var mlPrediction: PerformancePredictor.Prediction?
    @Published var mlFeatureWeights: PerformancePredictor.FeatureWeights?
    @Published var mlError: String?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var intentAwareAssessment: EnhancedIntentAwareReadinessService.EnhancedReadinessAssessment?
    @Published var temporalAnalysis: TemporalModelingService.TemporalAnalysis?
    @Published var dailyRecommendation: DailyRecommendationService.DailyRecommendation?
    @Published var injuryRiskAssessment: InjuryRiskCalculator.InjuryRiskAssessment?
    @Published var zoneAnalysis: TrainingZoneAnalyzer.ZoneAnalysis?
    @Published var fitnessAnalysis: FitnessTrendAnalyzer.FitnessAnalysis?
    
    private var repositoryCancellable: AnyCancellable?
    private var repositoryErrorCancellable: AnyCancellable?

    init() {
        setupRepositorySubscription()
    }

    private func setupRepositorySubscription() {
        repositoryCancellable = ReadinessRepository.shared.$currentReadiness
            .receive(on: DispatchQueue.main)
            .sink { [weak self] unified in
                guard let self = self, let unified = unified else { return }
                self.updateFromUnifiedReadiness(unified)
            }

        repositoryErrorCancellable = ReadinessRepository.shared.$analysisError
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                guard let self else { return }
                guard let error else {
                    self.errorMessage = nil
                    return
                }
                self.errorMessage = error.contains("Insufficient data")
                    ? "Add some workouts and sleep data to see your readiness score."
                    : "Something went wrong. Pull to refresh or try again later."
            }
    }

    private func updateFromUnifiedReadiness(_ unified: ReadinessRepository.UnifiedReadiness) {
        self.readinessScore = ReadinessAnalyzer.ReadinessScore(
            score: unified.score,
            trend: unified.trend,
            recommendation: unified.coachAdvice,
            confidence: .high,
            breakdown: unified.breakdown,
            trajectory: []
        )
        self.intraDayReadiness = unified.intraDay
        self.dailyRecommendation = unified.recommendation
        self.injuryRiskAssessment = unified.injuryRisk
        self.formIndicator = generateFormIndicator(from: self.readinessScore!)

        // ML outputs — now owned by ReadinessRepository
        self.mlPrediction = unified.mlPrediction
        self.mlFeatureWeights = unified.mlFeatureWeights
        self.mlError = unified.mlError
        self.intentAwareAssessment = unified.intentAwareAssessment

        // Training load & zone outputs — now owned by ReadinessRepository (GEMINI.md mandate)
        self.temporalAnalysis = unified.temporalAnalysis
        self.zoneAnalysis = unified.zoneAnalysis
        self.fitnessAnalysis = unified.fitnessAnalysis
        self.trainingLoadSummary = unified.trainingLoadSummary
        self.readinessAssessment = unified.readinessAssessment
        self.acwrTrend = unified.acwrTrend
        self.loadVisualization = unified.loadVisualization
        self.primaryActivity = unified.primaryActivity

        // Coaching output — now owned by ReadinessRepository (GEMINI.md mandate)
        self.dailyInstruction = unified.dailyInstruction
    }
    
    // Training Load (moved from InsightsViewModel)
    @Published var trainingLoadSummary: TrainingLoadCalculator.TrainingLoadSummary?
    @Published var readinessAssessment: PredictiveReadinessService.ReadinessAssessment?
    @Published var acwrTrend: [ACWRDataPoint] = []
    @Published var loadVisualization: TrainingLoadVisualizationService.LoadVisualizationData?
    @Published var primaryActivity: String = "Ride"
    @Published var dailyTSSData: [DailyTSSData] = []
    @Published var selectedPeriod: TimePeriod = .quarter

    // Pattern Discovery State
    private var cachedPatterns: [PerformancePatternAnalyzer.PerformanceWindow]?
    private var lastPatternDiscovery: Date?

    // SwiftData
    var modelContainer: ModelContainer?
    
    // MARK: - Configuration
    
    func configure(container: ModelContainer) {
        self.modelContainer = container
    }
    
    // MARK: - Main Analysis
    
    @MainActor
    func analyze(modelContext: ModelContext) async {
        guard let container = modelContainer else {
            errorMessage = "Database not configured"
            return
        }
        
        isLoading = true
        errorMessage = nil
        mlError = nil
        
        do {
            let context = container.mainContext

            // Clear pattern cache when data changes
            cachedPatterns = nil
            lastPatternDiscovery = nil
            
            // PROFILE: Data Fetching (respecting data window)
            let (storedWorkouts, storedHealthMetrics, storedNutrition) = try await PerformanceProfiler.measureAsync("📊 Data Fetch") {
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
                
                let workouts = try context.fetch(workoutDescriptor)
                let metrics = try context.fetch(metricDescriptor)
                let nutrition = try context.fetch(nutritionDescriptor)
                return (workouts, metrics, nutrition)
            }
            
            // PROFILE: Data Conversion
            let (workouts, nutrition, sleepData, hrvData, rhrData, _) = PerformanceProfiler.measure("🔄 Data Conversion") {
                let workouts = storedWorkouts.map { WorkoutData(from: $0) }
                let nutrition = storedNutrition.map { DailyNutrition(from: $0) }
                
                let sleepData = storedHealthMetrics
                    .filter { $0.type == "Sleep" }
                    .map { HealthDataPoint(date: $0.date, value: $0.value) }
                
                let hrvData = storedHealthMetrics
                    .filter { $0.type == "HRV" }
                    .map { HealthDataPoint(date: $0.date, value: $0.value) }
                
                let rhrData = storedHealthMetrics
                    .filter { $0.type == "RHR" }
                    .map { HealthDataPoint(date: $0.date, value: $0.value) }
                
                let vo2maxData = storedHealthMetrics
                    .filter { $0.type == "VO2max" }
                    .map { HealthDataPoint(date: $0.date, value: $0.value) }
                
                return (workouts, nutrition, sleepData, hrvData, rhrData, vo2maxData)
            }
            
            // PROFILE: Unified Readiness Analysis (Master Coach)
            // Also computes: primaryActivity, temporalAnalysis, trainingLoadSummary,
            // readinessAssessment, acwrTrend, loadVisualization, zoneAnalysis, fitnessAnalysis
            await ReadinessRepository.shared.refreshIfNecessary(modelContext: modelContext)

            // PROFILE: Pattern Discovery (sample recent data only)
            PerformanceProfiler.measure("🔍 Pattern Discovery") {
                let shouldRediscover = cachedPatterns == nil ||
                    lastPatternDiscovery == nil ||
                    Date().timeIntervalSince(lastPatternDiscovery!) > 86400

                if shouldRediscover {
                    print("🔬 Discovering patterns from recent workouts only...")

                    // Only analyze last 365 days of data
                    let calendar = Calendar.current
                    let oneYearAgo = calendar.date(byAdding: .day, value: -365, to: Date())!
                    let recentWorkouts = workouts.filter { $0.startDate >= oneYearAgo }
                    let recentSleep = sleepData.filter { $0.date >= oneYearAgo }
                    let recentNutrition = nutrition.filter { $0.date >= oneYearAgo }

                    print("   Analyzing \(recentWorkouts.count) recent workouts (vs \(workouts.count) total)")

                    let statPatternAnalyzer = StatisticalPerformancePatternAnalyzer()
                    let validatedWindows = statPatternAnalyzer.discoverValidatedPatterns(
                        workouts: recentWorkouts,
                        activities: [],
                        sleep: recentSleep,
                        nutrition: recentNutrition
                    )
                    cachedPatterns = validatedWindows.map { $0.pattern }
                    lastPatternDiscovery = Date()
                    print("   Cached \(cachedPatterns?.count ?? 0) new patterns")
                } else {
                    print("   ✅ Using cached patterns from \(lastPatternDiscovery!)")
                }

                performanceWindows = cachedPatterns ?? []
                optimalTimings = []
                workoutSequences = []
            }

            // ML training + prediction now handled by ReadinessRepository (GEMINI.md mandate)
            // Training load, zone, fitness, temporal now handled by ReadinessRepository (GEMINI.md mandate)

            // Daily TSS chart data (period-dependent, stays in ViewModel)
            let stepData = storedHealthMetrics.filter { $0.type == "Steps" }
                .map { HealthDataPoint(date: $0.date, value: $0.value) }
            dailyTSSData = calculateDailyTSS(workouts: workouts, stepData: stepData)
            
        } catch {
            errorMessage = "Failed to analyze readiness: \(error.localizedDescription)"
            print("❌ Readiness analysis error: \(error)")
        }
        
        isLoading = false
    }
    
    // calculateIntentAwareReadiness / fetchIntentLabels / determinePrimaryActivity removed — logic moved to ReadinessRepository
    // trainMLModelsIfNeeded / makePredictionWithUncertainty removed — logic moved to ReadinessRepository
    // generateDailyInstruction removed — logic moved to ReadinessRepository (GEMINI.md mandate)

    // MARK: - Helper: Form Indicator
    
    private func generateFormIndicator(from readiness: ReadinessAnalyzer.ReadinessScore) -> ReadinessAnalyzer.FormIndicator {
        let status: ReadinessAnalyzer.FormIndicator.FormStatus
        let actionWindow: String
        let risk: ReadinessAnalyzer.FormIndicator.RiskLevel
        
        switch readiness.score {
        case 80...100:
            status = .primed
            actionWindow = "Optimal window for breakthrough efforts"
            risk = .low
        case 70..<80:
            status = .fresh
            actionWindow = "Good for quality intervals or tempo work"
            risk = .low
        case 55..<70:
            status = .functional
            actionWindow = "Stick to moderate endurance work"
            risk = .moderate
        case 40..<55:
            status = .fatigued
            actionWindow = "Easy aerobic only, or rest"
            risk = .high
        default:
            status = .depleted
            actionWindow = "Complete rest advised"
            risk = .veryHigh
        }
        
        return ReadinessAnalyzer.FormIndicator(
            status: status,
            daysInStatus: 1,
            optimalActionWindow: actionWindow,
            riskLevel: risk
        )
    }
    
    // calculateTrainingZones / calculateFitnessTrends / calculateTrainingLoad / calculateImprovedACWRTrend
    // removed — logic moved to ReadinessRepository per GEMINI.md mandate

    private func calculateDailyTSS(workouts: [WorkoutData], stepData: [HealthDataPoint]) -> [DailyTSSData] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        // Determine days back based on selected period
        let daysBack: Int
        switch selectedPeriod {
        case .week: daysBack = 7
        case .month: daysBack = 30
        case .quarter: daysBack = 90
        case .sixMonths: daysBack = 180
        case .year: daysBack = 365
        case .all: daysBack = 730 // 2 years max
        }
        
        var dailyData: [DailyTSSData] = []
        var ctlRunning: Double = 0  // Chronic Training Load (42-day EWMA)
        var atlRunning: Double = 0  // Acute Training Load (7-day EWMA)
        
        let ctlAlpha = 2.0 / 43.0  // 42-day time constant
        let atlAlpha = 2.0 / 8.0   // 7-day time constant
        
        let loadCalculator = TrainingLoadCalculator()
        
        for dayOffset in (0..<daysBack).reversed() {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: today) else {
                continue
            }
            
            // Get workouts for this day
            let dayWorkouts = workouts.filter {
                calendar.isDate($0.startDate, inSameDayAs: date)
            }
            
            // Calculate TSS for this day
            var dailyTSS: Double = 0
            for workout in dayWorkouts {
                dailyTSS += loadCalculator.calculateWorkoutLoad(workout)
            }
            
            // Add light load for high step days if no workout
            if dailyTSS == 0 {
                if let stepPoint = stepData.first(where: { calendar.isDate($0.date, inSameDayAs: date) }),
                   stepPoint.value >= 10000 {
                    dailyTSS = (stepPoint.value - 10000) / 5000.0
                }
            }
            
            // Update EWMA values
            ctlRunning = (dailyTSS * ctlAlpha) + (ctlRunning * (1.0 - ctlAlpha))
            atlRunning = (dailyTSS * atlAlpha) + (atlRunning * (1.0 - atlAlpha))
            
            dailyData.append(DailyTSSData(
                date: date,
                tss: dailyTSS,
                ctl: ctlRunning,
                atl: atlRunning
            ))
        }
        
        return dailyData
    }
    
}
