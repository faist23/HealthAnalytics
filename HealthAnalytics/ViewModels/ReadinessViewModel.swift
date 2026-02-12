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
    @Published var intentAwareAssessment: IntentAwareReadinessService.EnhancedReadinessAssessment?
    private let intentAwareService = IntentAwareReadinessService()

    // ML Training State
    private var trainedModels: [PerformancePredictor.TrainedModel] = []
    
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
            
            // Fetch all data
            let storedWorkouts = try context.fetch(FetchDescriptor<StoredWorkout>())
            let storedHealthMetrics = try context.fetch(FetchDescriptor<StoredHealthMetric>())
            let storedNutrition = try context.fetch(FetchDescriptor<StoredNutrition>())
            
            // Convert to working models
            let workouts = storedWorkouts.map { WorkoutData(from: $0) }
            let nutrition = storedNutrition.map { DailyNutrition(from: $0) }
            
            // Convert health metrics - using 'type' property
            let sleepData = storedHealthMetrics
                .filter { $0.type == "Sleep" }
                .map { HealthDataPoint(date: $0.date, value: $0.value) }
            
            let hrvData = storedHealthMetrics
                .filter { $0.type == "HRV" }
                .map { HealthDataPoint(date: $0.date, value: $0.value) }
            
            let rhrData = storedHealthMetrics
                .filter { $0.type == "RHR" }
                .map { HealthDataPoint(date: $0.date, value: $0.value) }
            
            // DEBUG: Check data availability
            print("\n🔍 DATA AVAILABILITY DEBUG:")
            print(String(repeating: "=", count: 50))
            print("Workouts: \(workouts.count)")
            print("Sleep points: \(sleepData.count)")
            print("HRV points: \(hrvData.count)")
            print("RHR points: \(rhrData.count)")
            
            if let firstWorkout = workouts.sorted(by: { $0.startDate > $1.startDate }).first {
                print("\n📅 MOST RECENT WORKOUT:")
                let formatter = DateFormatter()
                formatter.dateStyle = .short
                formatter.timeStyle = .short
                print("   Date: \(formatter.string(from: firstWorkout.startDate))")
                print("   Type: \(firstWorkout.workoutName)")
                
                let calendar = Calendar.current
                let workoutDay = calendar.startOfDay(for: firstWorkout.startDate)
                let prevDay = calendar.date(byAdding: .day, value: -1, to: workoutDay)!
                
                print("\n🔍 LOOKING FOR METRICS:")
                print("   Workout day (normalized): \(formatter.string(from: workoutDay))")
                print("   Previous day (for sleep): \(formatter.string(from: prevDay))")
                
                // Check sleep
                let sleepMatches = sleepData.filter {
                    calendar.isDate($0.date, inSameDayAs: prevDay)
                }
                print("\n💤 Sleep matches: \(sleepMatches.count)")
                if sleepMatches.isEmpty && !sleepData.isEmpty {
                    print("   ⚠️ No match! Sample sleep dates:")
                    for sleep in sleepData.prefix(3) {
                        print("      \(formatter.string(from: sleep.date)) = \(sleep.value)h")
                    }
                } else if let sleep = sleepMatches.first {
                    print("   ✅ Found: \(sleep.value)h on \(formatter.string(from: sleep.date))")
                }
                
                // Check HRV
                let hrvMatches = hrvData.filter {
                    calendar.isDate($0.date, inSameDayAs: workoutDay)
                }
                print("\n💚 HRV matches: \(hrvMatches.count)")
                if hrvMatches.isEmpty && !hrvData.isEmpty {
                    print("   ⚠️ No match! Sample HRV dates:")
                    for hrv in hrvData.prefix(3) {
                        print("      \(formatter.string(from: hrv.date)) = \(hrv.value)ms")
                    }
                } else if let hrv = hrvMatches.first {
                    print("   ✅ Found: \(hrv.value)ms on \(formatter.string(from: hrv.date))")
                }
                
                // Check RHR
                let rhrMatches = rhrData.filter {
                    calendar.isDate($0.date, inSameDayAs: workoutDay)
                }
                print("\n❤️ RHR matches: \(rhrMatches.count)")
                if rhrMatches.isEmpty && !rhrData.isEmpty {
                    print("   ⚠️ No match! Sample RHR dates:")
                    for rhr in rhrData.prefix(3) {
                        print("      \(formatter.string(from: rhr.date)) = \(rhr.value)bpm")
                    }
                } else if let rhr = rhrMatches.first {
                    print("   ✅ Found: \(rhr.value)bpm on \(formatter.string(from: rhr.date))")
                }
            }
            print(String(repeating: "=", count: 50) + "\n")
            
            // Determine primary activity
            let primaryActivity = determinePrimaryActivity(from: workouts)
            print("🎯 Primary Activity Detected: \(primaryActivity)")
            
            // Analyze readiness
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
            
            // Fetch intent labels
            let intentLabels = try await fetchIntentLabels(modelContext: modelContext)
            
            // Calculate intent-aware readiness
            calculateIntentAwareReadiness(
                workouts: storedWorkouts,
                labels: intentLabels,
                sleep: sleepData,
                hrv: hrvData
            )

            // Pattern analysis
            let patternAnalyzer = PerformancePatternAnalyzer()
            performanceWindows = patternAnalyzer.discoverPerformanceWindows(
                workouts: workouts,
                activities: [],
                sleep: sleepData,
                nutrition: nutrition
            )
            
            optimalTimings = patternAnalyzer.discoverOptimalTiming(
                workouts: workouts,
                activities: []
            )
            
            workoutSequences = patternAnalyzer.discoverWorkoutSequences(
                workouts: workouts,
                activities: []
            )
            
            // ML Prediction
            await trainMLModelsIfNeeded(
                sleepData: sleepData,
                hrvData: hrvData,
                rhrData: rhrData,
                workouts: workouts,
                nutrition: nutrition
            )
            
            makePrediction(
                activityType: primaryActivity,
                sleepData: sleepData,
                hrvData: hrvData,
                rhrData: rhrData,
                workouts: workouts,
                nutrition: nutrition
            )
            
            // Generate daily instruction
            generateDailyInstruction(
                primaryActivity: primaryActivity,
                workouts: workouts,
                hrvData: hrvData,
                rhrData: rhrData
            )
            
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
    
    private func makePrediction(
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
            let prediction = try PerformancePredictor.predict(
                models: trainedModels,
                activityType: activityType,
                sleepHours: sleep,
                hrvMs: hrv,
                restingHR: rhr,
                acwr: assessment.acwr,
                carbs: recentCarbs
            )
            
            mlPrediction = prediction
            
            if let usedModel = trainedModels.first(where: { $0.activityType == prediction.activityType }) {
                mlFeatureWeights = usedModel.featureWeights
            }
            
            print("✅ ML Prediction: \(String(format: "%.1f", prediction.predictedPerformance)) \(prediction.unit) for \(prediction.activityType)")
            
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
