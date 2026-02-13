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
    @Published var formIndicator: ReadinessAnalyzer.FormIndicator?
    @Published var performanceWindows: [PerformancePatternAnalyzer.PerformanceWindow] = []
    @Published var optimalTimings: [PerformancePatternAnalyzer.OptimalTiming] = []
    @Published var workoutSequences: [PerformancePatternAnalyzer.WorkoutSequence] = []
    @Published var dailyInstruction: DailyInstruction?
    @Published var mlPrediction: PerformancePredictor.Prediction?
    @Published var mlFeatureWeights: PerformancePredictor.FeatureWeights?
    @Published var mlError: String?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var intentAwareAssessment: EnhancedIntentAwareReadinessService.EnhancedReadinessAssessment?
    @Published var temporalAnalysis: TemporalModelingService.TemporalAnalysis?
    private let intentAwareService = EnhancedIntentAwareReadinessService()

    // ML Training State
    private var trainedModels: [PerformancePredictor.TrainedModel] = []
    private var cachedPatterns: [PerformancePatternAnalyzer.PerformanceWindow]?
    private var lastPatternDiscovery: Date?
    private var lastMLTraining: Date?
    
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
            
            // PROFILE: Data Fetching
            let (storedWorkouts, storedHealthMetrics, storedNutrition) = try await PerformanceProfiler.measureAsync("📊 Data Fetch") {
                let workouts = try context.fetch(FetchDescriptor<StoredWorkout>())
                let metrics = try context.fetch(FetchDescriptor<StoredHealthMetric>())
                let nutrition = try context.fetch(FetchDescriptor<StoredNutrition>())
                return (workouts, metrics, nutrition)
            }
            
            // PROFILE: Data Conversion
            let (workouts, nutrition, sleepData, hrvData, rhrData) = PerformanceProfiler.measure("🔄 Data Conversion") {
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
                
                return (workouts, nutrition, sleepData, hrvData, rhrData)
            }
            
            print("\n📊 Data loaded: \(workouts.count) workouts, \(sleepData.count) sleep, \(hrvData.count) HRV\n")
            
            let primaryActivity = determinePrimaryActivity(from: workouts)
            
            // PROFILE: Readiness Analysis
            PerformanceProfiler.measure("🎯 Readiness Analysis") {
                let analyzer = ReadinessAnalyzer()
                if let readiness = analyzer.analyzeReadiness(
                    restingHR: rhrData,
                    hrv: hrvData,
                    sleep: sleepData,
                    workouts: workouts,
                    stravaActivities: [],
                    nutrition: nutrition
                ) {
                    readinessScore = readiness
                    formIndicator = generateFormIndicator(from: readiness)
                }
            }
            
            // PROFILE: Intent Labels Fetch
            let intentLabels = try await PerformanceProfiler.measureAsync("🏷️ Intent Labels Fetch") {
                try await fetchIntentLabels(modelContext: modelContext)
            }
            
            // PROFILE: Intent-Aware Readiness
            PerformanceProfiler.measure("💡 Intent-Aware Readiness") {
                calculateIntentAwareReadiness(
                    workouts: storedWorkouts,
                    labels: intentLabels,
                    sleep: sleepData,
                    hrv: hrvData
                )
            }
            
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
            
            // PROFILE: ML Training (cache models)
            await PerformanceProfiler.measureAsync("🤖 ML Training") {
                // Only retrain once per week
                let shouldRetrain = trainedModels.isEmpty ||
                    lastMLTraining == nil ||
                    Date().timeIntervalSince(lastMLTraining!) > 604800 // 7 days
                
                if shouldRetrain {
                    print("🤖 Training ML models...")
                    await trainMLModelsIfNeeded(
                        sleepData: sleepData,
                        hrvData: hrvData,
                        rhrData: rhrData,
                        workouts: workouts,
                        nutrition: nutrition
                    )
                    lastMLTraining = Date()
                } else {
                    print("✅ ML models already trained (\(trainedModels.count) models)")
                }
            }
            
            // PROFILE: ML Prediction
            PerformanceProfiler.measure("🔮 ML Prediction") {
                makePredictionWithUncertainty(
                    activityType: primaryActivity,
                    sleepData: sleepData,
                    hrvData: hrvData,
                    rhrData: rhrData,
                    workouts: workouts,
                    nutrition: nutrition
                )
            }
            
            // PROFILE: Temporal Analysis
            PerformanceProfiler.measure("🕐 Temporal Analysis") {
                let temporalService = TemporalModelingService()
                temporalAnalysis = temporalService.analyzeTemporalPatterns(
                    workouts: workouts,
                    activityType: primaryActivity
                )
            }

            // PROFILE: Daily Instruction
            PerformanceProfiler.measure("📝 Daily Instruction") {
                generateDailyInstruction(
                    primaryActivity: primaryActivity,
                    workouts: workouts,
                    hrvData: hrvData,
                    rhrData: rhrData
                )
            }
            
        } catch {
            errorMessage = "Failed to analyze readiness: \(error.localizedDescription)"
            print("❌ Readiness analysis error: \(error)")
        }
        
        isLoading = false
    }
    
    func calculateIntentAwareReadiness(
        workouts: [StoredWorkout],
        labels: [StoredIntentLabel],
        sleep: [HealthDataPoint],
        hrv: [HealthDataPoint]
    ) {
        // Only calculate if we have labeled workouts
        guard !labels.isEmpty else {
            intentAwareAssessment = nil
            return
        }
        
        intentAwareAssessment = intentAwareService.calculateEnhancedReadiness(
            workouts: workouts,
            labels: labels,
            sleep: sleep,
            hrv: hrv
        )
    }
    
    // Helper to fetch labels
    private func fetchIntentLabels(modelContext: ModelContext) async throws -> [StoredIntentLabel] {
        let descriptor = FetchDescriptor<StoredIntentLabel>()
        return try modelContext.fetch(descriptor)
    }
    
    // MARK: - Smart Activity Detection
    
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
        
        print("📊 Recent Activity Breakdown (90 days):")
        for (type, count) in counts.sorted(by: { $0.value > $1.value }) {
            print("   \(type): \(count) workouts")
        }
        
        return counts.max(by: { $0.value < $1.value })?.key ?? "Ride"
    }
    
    // MARK: - ML Training & Prediction
    
    private func trainMLModelsIfNeeded(
        sleepData: [HealthDataPoint],
        hrvData: [HealthDataPoint],
        rhrData: [HealthDataPoint],
        workouts: [WorkoutData],
        nutrition: [DailyNutrition]
    ) async {
        guard trainedModels.isEmpty else {
            print("✅ ML models already trained, skipping")
            return
        }
        
        print("🤖 Training ML models...")
        
        let readinessService = PredictiveReadinessService()
        
        do {
            trainedModels = try await PerformancePredictor.train(
                sleepData: sleepData,
                hrvData: hrvData,
                restingHRData: rhrData,
                healthKitWorkouts: workouts,
                stravaActivities: [],
                nutritionData: nutrition,
                readinessService: readinessService
            )
            
            print("✅ Trained \(trainedModels.count) ML model(s)")
            for model in trainedModels {
                print("   • \(model.activityType): \(model.sampleCount) samples, RMSE: \(String(format: "%.2f", model.rMeanSquaredError))")
            }
            
        } catch {
            mlError = error.localizedDescription
            print("❌ ML training failed: \(error)")
        }
    }
    
    private func makePredictionWithUncertainty(
        activityType: String,
        sleepData: [HealthDataPoint],
        hrvData: [HealthDataPoint],
        rhrData: [HealthDataPoint],
        workouts: [WorkoutData],
        nutrition: [DailyNutrition]
    ) {
        guard !trainedModels.isEmpty else {
            mlError = "Not enough data to train ML models yet. Need 10+ workouts with complete sleep, HRV, and RHR data."
            return
        }
        
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        
        // Get most recent metrics
        guard let sleep = sleepData.first(where: { calendar.isDate($0.date, inSameDayAs: yesterday) })?.value,
              let hrv = hrvData.first(where: { calendar.isDate($0.date, inSameDayAs: today) })?.value,
              let rhr = rhrData.first(where: { calendar.isDate($0.date, inSameDayAs: today) })?.value else {
            mlError = "Missing recent sleep, HRV, or resting HR data"
            return
        }
        
        // Calculate ACWR
        let readinessService = PredictiveReadinessService()
        let assessment = readinessService.calculateReadiness(
            stravaActivities: [],
            healthKitWorkouts: workouts
        )
        
        // Get recent carbs
        let recentCarbs = nutrition.first(where: { calendar.isDate($0.date, inSameDayAs: yesterday) })?.totalCarbs ?? 250.0
        
        do {
            // Get prediction with uncertainty
            let predictionWithUncertainty = try PerformancePredictor.predictWithUncertainty(
                models: trainedModels,
                activityType: activityType,
                sleepHours: sleep,
                hrvMs: hrv,
                restingHR: rhr,
                acwr: assessment.acwr,
                carbs: recentCarbs
            )
            
            mlPrediction = predictionWithUncertainty.prediction
            
            if let usedModel = trainedModels.first(where: { $0.activityType == predictionWithUncertainty.prediction.activityType }) {
                mlFeatureWeights = usedModel.featureWeights
            }
            
            // Log the uncertainty
            if let interval = predictionWithUncertainty.predictionInterval {
                print("✅ ML Prediction: \(predictionWithUncertainty.formattedPrediction)")
                print("   Uncertainty: \(predictionWithUncertainty.modelUncertainty.description)")
            } else {
                print("✅ ML Prediction: \(String(format: "%.1f", predictionWithUncertainty.prediction.predictedPerformance)) \(predictionWithUncertainty.prediction.unit)")
            }
            
        } catch {
            mlError = error.localizedDescription
            print("❌ ML prediction failed: \(error)")
        }
    }
    
    // MARK: - Daily Instruction
    
    private func generateDailyInstruction(
        primaryActivity: String,
        workouts: [WorkoutData],
        hrvData: [HealthDataPoint],
        rhrData: [HealthDataPoint]
    ) {
        guard let readiness = readinessScore else { return }
        
        let service = CoachingService()
        let readinessService = PredictiveReadinessService()
        
        let assessment = readinessService.calculateReadiness(
            stravaActivities: [],
            healthKitWorkouts: workouts
        )
        
        let correlationEngine = CorrelationEngine()
        let recoveryInsights = correlationEngine.analyzeRecoveryStatus(
            restingHRData: rhrData,
            hrvData: hrvData
        )
        
        let rawInstruction = service.generateDailyInstruction(
            readiness: assessment,
            insights: [],
            recovery: recoveryInsights,
            prediction: mlPrediction
        )
        
        // Enhance with activity-specific language
        let enhancedTargetAction: String?
        if let target = rawInstruction.targetAction {
            enhancedTargetAction = target.replacingOccurrences(of: "workout", with: primaryActivity.lowercased())
        } else {
            enhancedTargetAction = nil
        }
        
        dailyInstruction = DailyInstruction(
            status: rawInstruction.status,
            headline: rawInstruction.headline,
            subline: rawInstruction.subline,
            primaryInsight: rawInstruction.primaryInsight,
            targetAction: enhancedTargetAction
        )
    }
    
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
    
    // MARK: - Daily Instruction Model
    
    struct DailyInstruction {
        let status: CoachingService.DailyStatus
        let headline: String
        let subline: String
        let primaryInsight: String?
        let targetAction: String?
    }
}
