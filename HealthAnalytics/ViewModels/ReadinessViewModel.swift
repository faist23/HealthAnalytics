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
    @Published var dailyRecommendation: DailyRecommendationService.DailyRecommendation?
    @Published var injuryRiskAssessment: InjuryRiskCalculator.InjuryRiskAssessment?
    @Published var zoneAnalysis: TrainingZoneAnalyzer.ZoneAnalysis?
    @Published var fitnessAnalysis: FitnessTrendAnalyzer.FitnessAnalysis?
    
    // Training Load (moved from InsightsViewModel)
    @Published var trainingLoadSummary: TrainingLoadCalculator.TrainingLoadSummary?
    @Published var readinessAssessment: PredictiveReadinessService.ReadinessAssessment?
    @Published var acwrTrend: [ACWRDataPoint] = []
    @Published var loadVisualization: TrainingLoadVisualizationService.LoadVisualizationData?
    @Published var primaryActivity: String = "Ride"
    @Published var dailyTSSData: [DailyTSSData] = []
    @Published var selectedPeriod: TimePeriod = .quarter

    // ML Training State
    private var trainedModels: [PerformancePredictor.TrainedModel] = []
    private let intentAwareService = EnhancedIntentAwareReadinessService()
    private var cachedPatterns: [PerformancePatternAnalyzer.PerformanceWindow]?
    private var lastPatternDiscovery: Date?
    private var lastMLTraining: Date?
    
    // Data fingerprint for cache checking
    private var lastDataFingerprint: (workouts: Int, sleep: Int, hrv: Int, rhr: Int)?
    
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
            
            // CACHE CHECK: Count records to see if data changed
            var workoutDescriptor: FetchDescriptor<StoredWorkout>
            var metricDescriptor: FetchDescriptor<StoredHealthMetric>
            
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
            } else {
                workoutDescriptor = FetchDescriptor<StoredWorkout>()
                metricDescriptor = FetchDescriptor<StoredHealthMetric>()
            }
            
            let workoutCount = try context.fetchCount(workoutDescriptor)
            let sleepCount = try context.fetchCount(FetchDescriptor<StoredHealthMetric>(
                predicate: #Predicate { $0.type == "Sleep" }
            ))
            let hrvCount = try context.fetchCount(FetchDescriptor<StoredHealthMetric>(
                predicate: #Predicate { $0.type == "HRV" }
            ))
            let rhrCount = try context.fetchCount(FetchDescriptor<StoredHealthMetric>(
                predicate: #Predicate { $0.type == "RHR" }
            ))
            
            let currentFingerprint = (workoutCount, sleepCount, hrvCount, rhrCount)
            
            // If data hasn't changed AND we have existing results, skip analysis
            if let lastFingerprint = lastDataFingerprint,
               lastFingerprint == currentFingerprint,
               dailyRecommendation != nil || dailyInstruction != nil {
                print("✅ Data unchanged - using cached analysis results")
                isLoading = false
                return
            }
            
            print("🔄 Data changed or no cache - running full analysis")
            print("   Workouts: \(workoutCount), Sleep: \(sleepCount), HRV: \(hrvCount), RHR: \(rhrCount)")
            
            // Store fingerprint for next check
            lastDataFingerprint = currentFingerprint
            
            // Clear pattern cache when data changes, but keep ML models
            cachedPatterns = nil
            lastPatternDiscovery = nil
            // Note: We DON'T clear lastMLTraining - models persist across analyses
            
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
            let (workouts, nutrition, sleepData, hrvData, rhrData, vo2maxData) = PerformanceProfiler.measure("🔄 Data Conversion") {
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
            
            print("\n📊 Data loaded: \(workouts.count) workouts, \(sleepData.count) sleep, \(hrvData.count) HRV\n")
            
            // RIGHT AFTER "Data loaded" print statement, add:
            print("\n🔍 HR DATA AUDIT:")
            let ridesWithHR = workouts.filter { workout in
                workout.workoutType == .cycling && workout.averageHeartRate != nil && workout.averageHeartRate! > 0
            }
            print("   Total cycling workouts: \(workouts.filter { $0.workoutType == .cycling }.count)")
            print("   Rides WITH HR: \(ridesWithHR.count)")

            // Show date range of rides with HR
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            if let earliest = ridesWithHR.min(by: { $0.startDate < $1.startDate }) {
                print("   Earliest ride with HR: \(formatter.string(from: earliest.startDate))")
            }
            if let latest = ridesWithHR.max(by: { $0.startDate < $1.startDate }) {
                print("   Latest ride with HR: \(formatter.string(from: latest.startDate))")
            }

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

            // PROFILE: Training Load (moved from Insights)
            PerformanceProfiler.measure("📊 Training Load") {
                let stepData = storedHealthMetrics.filter { $0.type == "Steps" }
                    .map { HealthDataPoint(date: $0.date, value: $0.value) }
                
                calculateTrainingLoad(
                    workouts: workouts,
                    stepData: stepData,
                    hrvData: hrvData,
                    rhrData: rhrData,
                    intentLabels: intentLabels
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
            
            // PROFILE: Daily Recommendation (HRV-Guided)
            PerformanceProfiler.measure("🎯 Daily Recommendation") {
                generateDailyRecommendation(
                    hrvData: hrvData,
                    sleepData: sleepData,
                    rhrData: rhrData,
                    workouts: workouts
                )
            }
            
            // PROFILE: Injury Risk Assessment
            PerformanceProfiler.measure("🏥 Injury Risk") {
                calculateInjuryRisk(
                    workouts: workouts,
                    hrvData: hrvData,
                    rhrData: rhrData
                )
            }
            
            // PROFILE: Training Zone Analysis
            PerformanceProfiler.measure("🎯 Training Zones") {
                calculateTrainingZones(workouts: workouts)
            }
            
            // PROFILE: Fitness Trend Analysis
            PerformanceProfiler.measure("📊 Fitness Trends") {
                calculateFitnessTrends(
                    vo2maxData: vo2maxData,
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
    
    // MARK: - Daily Recommendation (HRV-Guided)
    
    private func generateDailyRecommendation(
        hrvData: [HealthDataPoint],
        sleepData: [HealthDataPoint],
        rhrData: [HealthDataPoint],
        workouts: [WorkoutData]
    ) {
        let service = DailyRecommendationService()
        
        dailyRecommendation = service.generateDailyRecommendation(
            hrvData: hrvData,
            sleepData: sleepData,
            rhrData: rhrData,
            workouts: workouts,
            readinessScore: readinessScore?.score
        )
    }
    
    // MARK: - Injury Risk Assessment
    
    private func calculateInjuryRisk(
        workouts: [WorkoutData],
        hrvData: [HealthDataPoint],
        rhrData: [HealthDataPoint]
    ) {
        // Calculate training load with enhanced EWMA metrics
        let calculator = TrainingLoadCalculator()
        let trainingLoad = calculator.calculateTrainingLoad(
            healthKitWorkouts: workouts,
            stravaActivities: [],
            stepData: []
        )
        
        // Get recovery status from correlation engine
        let correlationEngine = CorrelationEngine()
        let recoveryInsights = correlationEngine.analyzeRecoveryStatus(
            restingHRData: rhrData,
            hrvData: hrvData
        )
        
        // Generate trends for the past 14 days
        let trendDetector = TrendDetector()
        let trends = trendDetector.detectTrends(
            restingHRData: rhrData,
            hrvData: hrvData,
            sleepData: [],
            stepData: [],
            weightData: [],
            workouts: workouts
        )
        
        // Calculate injury risk
        let riskCalculator = InjuryRiskCalculator()
        injuryRiskAssessment = riskCalculator.assessInjuryRisk(
            trainingLoad: trainingLoad,
            recoveryStatus: recoveryInsights,
            trends: trends
        )
    }
    
    // MARK: - Training Zone Analysis
    
    private func calculateTrainingZones(workouts: [WorkoutData]) {
        let analyzer = TrainingZoneAnalyzer()
        zoneAnalysis = analyzer.analyzeTrainingZones(workouts: workouts)
    }
    
    // MARK: - Fitness Trend Analysis
    
    private func calculateFitnessTrends(
        vo2maxData: [HealthDataPoint],
        workouts: [WorkoutData],
        hrvData: [HealthDataPoint],
        rhrData: [HealthDataPoint]
    ) {
        // Get user age and biological sex from HealthKit
        let healthKitManager = HealthKitManager.shared
        let userAge = healthKitManager.getUserAge() ?? 35  // Fallback to 35 if not available
        let userGender = healthKitManager.getUserBiologicalSex()
        
        let analyzer = FitnessTrendAnalyzer()
        fitnessAnalysis = analyzer.analyzeFitnessTrends(
            vo2maxData: vo2maxData,
            workouts: workouts,
            hrvData: hrvData,
            rhrData: rhrData,
            userAge: userAge,
            userGender: userGender
        )
    }
    
    // MARK: - Training Load Calculation
    
    private func calculateTrainingLoad(
        workouts: [WorkoutData],
        stepData: [HealthDataPoint],
        hrvData: [HealthDataPoint],
        rhrData: [HealthDataPoint],
        intentLabels: [StoredIntentLabel]
    ) {
        let loadCalculator = TrainingLoadCalculator()
        let correlationEngine = CorrelationEngine()
        
        // Get recovery insights first (needed for training load recommendations)
        let recoveryInsights = correlationEngine.analyzeRecoveryStatus(
            restingHRData: rhrData,
            hrvData: hrvData
        )
        
        // Calculate training load with recovery insights
        trainingLoadSummary = loadCalculator.calculateTrainingLoad(
            healthKitWorkouts: workouts,
            stravaActivities: [],
            stepData: stepData,
            recoveryInsights: recoveryInsights
        )
        
        // Calculate readiness assessment
        let readinessService = PredictiveReadinessService()
        readinessAssessment = readinessService.calculateReadiness(
            stravaActivities: [],
            healthKitWorkouts: workouts
        )
        
        // Calculate ACWR trend
        acwrTrend = calculateImprovedACWRTrend(
            workouts: workouts,
            readinessService: readinessService
        )
        
        // Generate extended visualization data
        let loadService = TrainingLoadVisualizationService()
        loadVisualization = loadService.generateLoadVisualization(
            workouts: workouts,
            labels: intentLabels,
            daysBack: 90
        )
        
        // Generate daily TSS data for chart
        dailyTSSData = calculateDailyTSS(workouts: workouts, stepData: stepData)
    }
    
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
    
    private func calculateImprovedACWRTrend(
        workouts: [WorkoutData],
        readinessService: PredictiveReadinessService
    ) -> [ACWRDataPoint] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        var dataPoints: [ACWRDataPoint] = []
        
        print("🔵 calculateImprovedACWRTrend: Starting calculation for last 7 days")
        
        // Calculate ACWR for last 7 days
        for dayOffset in (0..<7).reversed() {
            guard let targetDate = calendar.date(byAdding: .day, value: -dayOffset, to: today) else {
                continue
            }
            
            // Get workouts up to this date
            let workoutsUpToDate = workouts.filter { $0.startDate <= targetDate }
            
            // Calculate readiness for this date
            let assessment = readinessService.calculateReadiness(
                stravaActivities: [],
                healthKitWorkouts: workoutsUpToDate
            )
            
            let dataPoint = ACWRDataPoint(
                date: targetDate,
                value: assessment.acwr
            )
            dataPoints.append(dataPoint)
            
            print("🔵   Day \(dayOffset): \(targetDate) -> ACWR: \(assessment.acwr)")
        }
        
        print("🔵 calculateImprovedACWRTrend: Created \(dataPoints.count) data points")
        return dataPoints
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
