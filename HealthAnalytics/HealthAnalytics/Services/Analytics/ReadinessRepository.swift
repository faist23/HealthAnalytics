//
//  ReadinessRepository.swift
//  HealthAnalytics
//
//  The "Master Coach" layer. Centralizes all analysis services,
//  reconciles competing advice, and ensures UI consistency.
//

import Foundation
import SwiftUI
import SwiftData
import HealthKit
import Combine

@MainActor
class ReadinessRepository: ObservableObject {
    static let shared = ReadinessRepository()
    
    // MARK: - Published State
    
    @Published private(set) var currentReadiness: UnifiedReadiness?
    @Published private(set) var intraDayReadiness: RecoveryDecayService.IntraDayReadiness?
    @Published private(set) var forecast: [ReadinessForecastDay]?
    @Published private(set) var isAnalyzing = false
    /// Non-nil when analysis fails; nil on success. Views branch on this to show
    /// "add workouts" vs "something went wrong" vs normal content.
    @Published private(set) var analysisError: String?
    
    // MARK: - Dependencies

    private let readinessAnalyzer = ReadinessAnalyzer()
    private let riskCalculator = InjuryRiskCalculator()
    private let recommendationService = DailyRecommendationService()
    private let loadCalculator = TrainingLoadCalculator()
    private let recoveryService = RecoveryDecayService()

    // ML sub-services (moved from ReadinessViewModel per GEMINI.md mandate)
    private let intentAwareService = EnhancedIntentAwareReadinessService()
    private let trendDetector = TrendDetector()

    // Training load & zone sub-services (moved from ReadinessViewModel per GEMINI.md mandate)
    private let predictiveReadinessService = PredictiveReadinessService()
    private let coachingService            = CoachingService()
    private let correlationEngineRepo      = CorrelationEngine()
    private let loadVizService             = TrainingLoadVisualizationService()
    private let zoneAnalyzer               = TrainingZoneAnalyzer()
    private let fitnessTrendAnalyzer       = FitnessTrendAnalyzer()
    private let temporalService            = TemporalModelingService()

    // Insights sub-services (moved from InsightsViewModel per GEMINI.md mandate)
    private let nutritionEngine            = NutritionCorrelationEngine()
    private let agingService               = BiologicalAgingService()
    private let actionableRecommendations  = ActionableRecommendations()
    private let cyclingPowerAnalyzer       = CyclingPowerAnalyzer()

    // Per-tab sub-services (moved from ReadinessViewModel + DashboardViewModel — Phase 1.2)
    private let cardiovascularStrainService = CardiovascularStrainService()
    private let metAnalyzer                 = METAnalyzer()
    private let balanceAnalyzer             = BalancedTrainingAnalyzer()

    // maxHR cache (was on ReadinessViewModel — Phase 1.2 migration)
    private static let maxHRCacheKey = "cachedPersonalMaxHR"
    private static let maxHRCacheDateKey = "cachedPersonalMaxHRDate"
    private static let maxHRCacheTTL: TimeInterval = 7 * 86400 // 7 days

    // Phase 2 — Pattern Engine sub-service
    private var trainingDNAAnalyzer: TrainingDNAAnalyzer?

    private var trainedModels: [PerformancePredictor.TrainedModel] = []
    private var lastMLTraining: Date?

    private var lastFingerprint: PredictionCache.DataFingerprint?
    private var lastAnalysisDate: Date?

    /// Set when a refresh arrives while `performFullAnalysis` is mid-flight, so the
    /// run can re-check the store on the way out instead of the request being lost.
    private var pendingRefreshRequested = false

    private var syncCompletedObserver: NSObjectProtocol?

    private static let dailyScoreDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone.current
        return f
    }()

    private init() {}

    /// Wires the repository to refresh whenever sync completes. Idempotent — safe
    /// to call multiple times; only the first call subscribes. Pulls the model
    /// context fresh from `HealthDataContainer.shared` at each refresh so a
    /// `resetAllData()` flow doesn't leave us holding a stale context.
    func bootstrap() {
        guard syncCompletedObserver == nil else { return }
        syncCompletedObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("DataSyncCompleted"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                await self.refreshIfNecessary(
                    modelContext: HealthDataContainer.shared.mainContext
                )
            }
        }
    }

    #if DEBUG
    /// Resets published state to a clean baseline. Use in unit tests to prevent
    /// cross-test contamination through ReadinessRepository.shared.
    func resetForTesting() {
        currentReadiness = nil
        forecast = nil
    }
    #endif

    // MARK: - Pattern Analysis (Phase 2)

    /// Primary trigger: called from InsightsView.onAppear (7-day staleness check)
    /// and from the toolbar refresh button (unconditional).
    func runPatternAnalysis(container: ModelContainer, force: Bool = false) async {
        let lastRun = UserDefaults.standard.object(forKey: "lastPatternAnalysisDate") as? Date
        guard force || lastRun == nil || Date().timeIntervalSince(lastRun!) > 7 * 86400 else { return }

        UserDefaults.standard.set(Date(), forKey: "lastPatternAnalysisDate")

        if trainingDNAAnalyzer == nil {
            trainingDNAAnalyzer = TrainingDNAAnalyzer(modelContainer: container)
        }

        let analyzer = trainingDNAAnalyzer!
        let preference = HRVSourcePreference(
            rawValue: UserDefaults.standard.string(forKey: "preferredHRVSource") ?? HRVSourcePreference.auto.rawValue
        ) ?? .auto

        do {
            let historyDays = try await analyzer.analyze(sourcePreference: preference)
            UserDefaults.standard.set(historyDays, forKey: "healthKitHistoryDays")
        } catch PatternAnalysisError.insufficientData {
            // < 60 days of history — silent, no error surfaced
        } catch {
            await MainActor.run { self.analysisError = "Pattern analysis failed: \(error.localizedDescription)" }
        }
    }
    
    // MARK: - Models

    /// One day in the 7-day readiness forecast.
    struct ReadinessForecastDay: Identifiable {
        let id = UUID()
        let date: Date
        let predictedReadiness: Int   // 0–100, clamped
        let confidenceLow: Int        // predictedReadiness - σ(day)
        let confidenceHigh: Int       // predictedReadiness + σ(day)
        let coaching: String          // "Hard effort OK" / "Moderate training" / "Easy only" / "Rest recommended"
    }

    struct UnifiedReadiness {
        let score: Int
        let morningScore: Int
        let level: ReadinessLevel
        let recommendation: DailyRecommendationService.DailyRecommendation
        let injuryRisk: InjuryRiskCalculator.InjuryRiskAssessment
        let breakdown: ReadinessAnalyzer.ScoreBreakdown
        let trend: ReadinessAnalyzer.ReadinessScore.Trend
        let date: Date
        let intraDay: RecoveryDecayService.IntraDayReadiness

        // RECONCILED MESSAGE: The single "Master Coach" advice
        let coachAdvice: String

        /// Overnight recovery rate multiplier derived from yesterday's combined load.
        /// Passed to EnergyBankChart so the projected curve reflects the same rate used for today's score.
        let overnightRecoveryMultiplier: Double

        /// TSS-equivalent load from today's excess steps (above personal 30-day baseline).
        /// Capped at 20% of today's workout TSS. Passed to EnergyBankChart for consistent curve rendering.
        let todayStepExcessTSS: Double

        // ML sub-service outputs (owned by Repository, not ViewModel)
        let mlPrediction: PerformancePredictor.Prediction?
        let mlFeatureWeights: PerformancePredictor.FeatureWeights?
        let mlError: String?
        let intentAwareAssessment: EnhancedIntentAwareReadinessService.EnhancedReadinessAssessment?

        // Training load & zone outputs (moved from ReadinessViewModel per GEMINI.md mandate)
        let primaryActivity: String
        let trainingLoadSummary: TrainingLoadCalculator.TrainingLoadSummary?
        let readinessAssessment: PredictiveReadinessService.ReadinessAssessment?
        let acwrTrend: [ACWRDataPoint]
        let loadVisualization: TrainingLoadVisualizationService.LoadVisualizationData?
        let temporalAnalysis: TemporalModelingService.TemporalAnalysis?
        let zoneAnalysis: TrainingZoneAnalyzer.ZoneAnalysis?
        let fitnessAnalysis: FitnessTrendAnalyzer.FitnessAnalysis?

        // Coaching output (moved from ReadinessViewModel per GEMINI.md mandate)
        let dailyInstruction: CoachingService.DailyInstruction?
        
        // Phase 4: Smart Routing Activity Readiness
        let activityReadiness: [String: Int]?

        // Insights sub-service outputs (moved from InsightsViewModel per GEMINI.md mandate)
        let metricTrends: [MetricTrend]
        let sleepPerformanceInsight: CorrelationEngine.SleepPerformanceInsight?
        let activityTypeInsights: [CorrelationEngine.ActivityTypeInsight]
        let dataSummary: [(activityType: String, goodSleep: Int, poorSleep: Int)]
        let simpleInsights: [CorrelationEngine.SimpleInsight]
        let hrvPerformanceInsights: [CorrelationEngine.HRVPerformanceInsight]
        let proteinRecoveryInsight: NutritionCorrelationEngine.ProteinRecoveryInsight?
        let proteinPerformanceInsights: [NutritionCorrelationEngine.ProteinPerformanceInsight]
        let carbPerformanceInsights: [NutritionCorrelationEngine.CarbPerformanceInsight]
        let recommendations: [ActionableRecommendations.Recommendation]
        let agingAssessment: BiologicalAgingService.AgingAssessment?
        let compoundScoreAnalysis: CyclingPowerAnalyzer.CompoundScoreAnalysis?

        // Per-tab outputs (moved from ReadinessViewModel + DashboardViewModel — Phase 1.2)
        let todayWorkouts: [WorkoutData]
        let todaySteps: Int
        let cardiovascularStrain: CardiovascularStrainService.Result?
        let holisticMetrics: HealthMetrics?

        // Raw chart-source arrays (consumed by view-derivation logic that depends on selectedPeriod)
        let hrvData: [HealthDataPoint]
        let rhrData: [HealthDataPoint]
        let sleepData: [HealthDataPoint]
        let stepCountData: [HealthDataPoint]
        let workouts: [WorkoutData]
        let weightData: [HealthDataPoint]
    }
    
    // MARK: - Main Analysis Entry Point
    
    func refreshIfNecessary(modelContext: ModelContext) async {
        // Backfill StoredDailyScore from HealthKit history on first launch.
        await backfillHistoricalScores(modelContext: modelContext)
        // One-time migration: populate dailyLoad on existing rows (default was 0.0 from schema add).
        backfillDailyLoad(modelContext: modelContext)

        // 1. Calculate current data fingerprint
        guard let fingerprint = try? calculateFingerprint(context: modelContext) else { return }
        
        // 2. Check if we can skip (Same data AND same day)
        if let lastDate = lastAnalysisDate,
           Calendar.current.isDateInToday(lastDate),
           fingerprint == lastFingerprint,
           currentReadiness != nil {
            #if DEBUG
            print("✅ ReadinessRepository: Using cached unified analysis")
            #endif
            return
        }
        
        await performFullAnalysis(modelContext: modelContext, fingerprint: fingerprint)
    }
    
    func forceRefresh(modelContext: ModelContext) async {
        guard let fingerprint = try? calculateFingerprint(context: modelContext) else { return }
        await performFullAnalysis(modelContext: modelContext, fingerprint: fingerprint)
    }
    
    // MARK: - Core Analysis Logic
    
    private func performFullAnalysis(modelContext: ModelContext, fingerprint: PredictionCache.DataFingerprint) async {
        // Re-entrancy guard: multiple views call refreshIfNecessary simultaneously on first load.
        // All pass the currentReadiness == nil check before any run sets it — without this guard
        // all three enter here concurrently, producing interleaved SwiftData writes.
        //
        // A run takes a long time (ML training, MasterCoachEngine, HealthKit reads), and a
        // workout finishing sync lands squarely inside that window. Dropping the request
        // outright left the published snapshot describing pre-ride data — the Load tab kept
        // showing yesterday's ACWR until some unrelated trigger happened along. Record the
        // request instead and re-check once this run finishes.
        guard !isAnalyzing else {
            pendingRefreshRequested = true
            #if DEBUG
            print("⏳ ReadinessRepository: refresh requested mid-analysis — queued")
            #endif
            return
        }
        isAnalyzing = true
        analysisError = nil

        #if DEBUG
        print("🔄 ReadinessRepository: Starting unified analysis...")
        #endif

        do {
            // 1. Fetch data with STABLE calendar windows
            let calendar = Calendar.current
            let now = Date()
            let today = calendar.startOfDay(for: now)
            let baselineStart = calendar.date(byAdding: .day, value: -90, to: today)!
            // The 90-day ACWR history chart needs a 28-day chronic lead-in before
            // its first plotted day (day D's ACWR windows [D-28, D]). Fetch workouts
            // 118 days back for the visualization so, after the cold-start trim,
            // the chart fills a full 90 days instead of 62. Metrics/nutrition stay
            // at 90 — widening those would shift readiness baselines elsewhere.
            let loadHistoryStart = calendar.date(byAdding: .day, value: -118, to: today)!

            let workoutDescriptor = FetchDescriptor<StoredWorkout>(
                predicate: #Predicate { $0.startDate >= baselineStart },
                sortBy: [SortDescriptor(\.startDate)]
            )
            let loadHistoryWorkoutDescriptor = FetchDescriptor<StoredWorkout>(
                predicate: #Predicate { $0.startDate >= loadHistoryStart },
                sortBy: [SortDescriptor(\.startDate)]
            )
            let metricDescriptor = FetchDescriptor<StoredHealthMetric>(
                predicate: #Predicate { $0.date >= baselineStart },
                sortBy: [SortDescriptor(\.date)]
            )
            let nutritionDescriptor = FetchDescriptor<StoredNutrition>(
                predicate: #Predicate { $0.date >= baselineStart },
                sortBy: [SortDescriptor(\.date)]
            )

            let storedWorkouts = try modelContext.fetch(workoutDescriptor)
            let loadHistoryWorkouts = (try? modelContext.fetch(loadHistoryWorkoutDescriptor))?
                .map { WorkoutData(from: $0) } ?? []
            let storedMetrics = try modelContext.fetch(metricDescriptor)
            let storedNutrition = try modelContext.fetch(nutritionDescriptor)
            let intentLabels = try modelContext.fetch(FetchDescriptor<StoredIntentLabel>())

            // Convert data
            let workouts = storedWorkouts.map { WorkoutData(from: $0) }
            let nutrition = storedNutrition.map { DailyNutrition(from: $0) }
            let hrvData = storedMetrics.filter { $0.type == "HRV" }.map { HealthDataPoint(date: $0.date, value: $0.value) }
            let rhrData = storedMetrics.filter { $0.type == "RHR" }.map { HealthDataPoint(date: $0.date, value: $0.value) }
            let sleepData  = storedMetrics.filter { $0.type == "Sleep"  }.map { HealthDataPoint(date: $0.date, value: $0.value) }
            let stepData   = storedMetrics.filter { $0.type == "Steps"  }.map { HealthDataPoint(date: $0.date, value: $0.value) }
            let vo2maxData   = storedMetrics.filter { $0.type == "VO2max"  }.map { HealthDataPoint(date: $0.date, value: $0.value) }
            let weightData   = storedMetrics.filter { $0.type == "Weight" }.map { HealthDataPoint(date: $0.date, value: $0.value) }

            // 2. Run Individual Services
            // A: Base Readiness Score
            guard let baseReadiness = readinessAnalyzer.analyzeReadiness(
                restingHR: rhrData,
                hrv: hrvData,
                sleep: sleepData,
                workouts: workouts,
                stravaActivities: [],
                nutrition: []
            ) else {
                throw NSError(domain: "ReadinessRepository", code: 1, userInfo: [NSLocalizedDescriptionKey: "Insufficient data"])
            }

            // B: Injury Risk
            let trainingLoad = loadCalculator.calculateTrainingLoad(
                healthKitWorkouts: workouts,
                stravaActivities: [],
                stepData: []
            )

            let trends = trendDetector.detectTrends(
                restingHRData: rhrData,
                hrvData: hrvData,
                sleepData: sleepData,
                stepData: stepData,
                weightData: weightData,
                workouts: workouts
            )

            let riskAssessment = riskCalculator.assessInjuryRisk(
                trainingLoad: trainingLoad,
                recoveryStatus: [],
                trends: trends
            )

            // C: HRV-Guided Recommendation
            guard let hrvRec = recommendationService.generateDailyRecommendation(
                hrvData: hrvData,
                sleepData: sleepData,
                rhrData: rhrData,
                workouts: workouts,
                readinessScore: baseReadiness.score
            ) else {
                throw NSError(domain: "ReadinessRepository", code: 2, userInfo: [NSLocalizedDescriptionKey: "Recommendation failed"])
            }

            // 3. THE MASTER COACH: Reconcile Advice
            let reconciledAdvice = reconcileAdvice(
                readiness: baseReadiness,
                risk: riskAssessment,
                hrvRec: hrvRec
            )

            let reconciledRecommendation = DailyRecommendationService.DailyRecommendation(
                status: hrvRec.status,
                headline: (riskAssessment.riskLevel == .high || riskAssessment.riskLevel == .veryHigh) ? "RESTRICTED: " + hrvRec.headline : hrvRec.headline,
                guidance: reconciledAdvice,
                targetZones: hrvRec.targetZones,
                avoidZones: hrvRec.avoidZones,
                confidence: hrvRec.confidence,
                reasoning: hrvRec.reasoning
            )

            // 4. Intra-Day Recovery Decay (Dynamic Score)
            // Carry-forward: fatigueScore of 30 = no debt; less than 30 = points suppressed by prior strain.
            let priorDayFatigueImpact = Double(30 - baseReadiness.breakdown.fatigueScore)

            // Mechanism 2 (NEAT): yesterday's combined load (workout + step excess) may impair
            // overnight recovery, slowing how quickly prior-day fatigue resolves today.
            let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
            let yesterdayWorkouts = workouts.filter { calendar.isDate($0.startDate, inSameDayAs: yesterday) }
            let yesterdayWorkoutTSS = yesterdayWorkouts.reduce(0.0) { $0 + loadCalculator.calculateWorkoutLoad($1) }
            let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: today)!
            let recentSteps = stepData.filter { $0.date >= thirtyDaysAgo && $0.date < today }
            let stepBaseline: Double = recentSteps.isEmpty ? 5000 : recentSteps.map(\.value).reduce(0, +) / Double(recentSteps.count)
            let yesterdayStepCount = stepData.first(where: { calendar.isDate($0.date, inSameDayAs: yesterday) })?.value ?? 0
            let yesterdayStepExcess = max(0, yesterdayStepCount - stepBaseline)
            // Rest-day cap: 2.0 TSS absolute ceiling when no workout — steps are supporting load, not primary stress.
            let cap = yesterdayWorkoutTSS > 0 ? yesterdayWorkoutTSS * 0.20 : 2.0
            let yesterdayStepExcessTSS = min(yesterdayStepExcess / 3000.0, cap)
            let recoveryMultiplier = RecoveryDecayService.overnightRecoveryMultiplier(
                workoutTSS: yesterdayWorkoutTSS,
                stepExcessTSS: yesterdayStepExcessTSS
            )

            // Mechanism 1 (NEAT): today's excess steps above personal baseline add to intra-day strain.
            // 3000 steps ≈ 1.0 TSS; capped at 20% of today's total workout TSS.
            // Rest-day cap: 2.0 TSS absolute ceiling — steps are supporting load, not primary stress.
            let todayStepCount = stepData.first(where: { calendar.isDate($0.date, inSameDayAs: today) })?.value ?? 0
            let todayStepExcess = max(0, todayStepCount - stepBaseline)
            let todayWorkoutTSS = workouts
                .filter { calendar.isDate($0.startDate, inSameDayAs: today) }
                .reduce(0.0) { $0 + loadCalculator.calculateWorkoutLoad($1) }
            let todayStepCap = todayWorkoutTSS > 0 ? todayWorkoutTSS * 0.20 : 2.0
            let todayStepExcessTSS = min(todayStepExcess / 3000.0, todayStepCap)

            let intraDay = recoveryService.calculateIntraDayReadiness(
                baselineScore: baseReadiness.score,
                todayWorkouts: workouts,
                priorDayFatigueImpact: max(0, priorDayFatigueImpact),
                todayStepExcessTSS: todayStepExcessTSS,
                overnightRecoveryMultiplier: recoveryMultiplier
            )

            // 5. ML Sub-services (moved from ReadinessViewModel per GEMINI.md)
            //    5a. Train PerformancePredictor (cache models 7 days)
            let primaryActivity = determinePrimaryActivity(from: workouts)
            var mlError: String? = nil

            // Fetch FTP snapshot history once — passed to every load calculation so that
            // each workout is evaluated against the FTP that was in effect on its date.
            let ftpSnapshots = (try? modelContext.fetch(FetchDescriptor<StoredFTPSnapshot>())) ?? []

            let readinessAssessmentResult = predictiveReadinessService.calculateReadiness(
                stravaActivities: [],
                healthKitWorkouts: workouts,
                ftpSnapshots: ftpSnapshots
            )

            let shouldRetrain = trainedModels.isEmpty
                || lastMLTraining == nil
                || Date().timeIntervalSince(lastMLTraining!) > 604_800 // 7 days

            if shouldRetrain {
                do {
                    // Training is CPU-bound CreateML work — run off the main actor.
                    // Prediction (< 1ms inference) stays on main actor.
                    let capturedSleep = sleepData
                    let capturedHRV = hrvData
                    let capturedRHR = rhrData
                    let capturedWorkouts = workouts
                    let capturedNutrition = nutrition
                    let capturedReadinessService = predictiveReadinessService
                    trainedModels = try await Task.detached(priority: .utility) {
                        try await PerformancePredictor.train(
                            sleepData: capturedSleep,
                            hrvData: capturedHRV,
                            restingHRData: capturedRHR,
                            healthKitWorkouts: capturedWorkouts,
                            stravaActivities: [],
                            nutritionData: capturedNutrition,
                            readinessService: capturedReadinessService
                        )
                    }.value
                    lastMLTraining = Date()
                    #if DEBUG
                    print("✅ ReadinessRepository: Trained \(trainedModels.count) ML model(s)")
                    #endif
                } catch {
                    mlError = error.localizedDescription
                    #if DEBUG
                    print("❌ ReadinessRepository: ML training failed: \(error)")
                    #endif
                }
            }

            //    5b. Predict with uncertainty
            var mlPrediction: PerformancePredictor.Prediction? = nil
            var mlFeatureWeights: PerformancePredictor.FeatureWeights? = nil

            if !trainedModels.isEmpty {
                let acwr = readinessAssessmentResult.acwr
                let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!

                if let sleep = sleepData.first(where: { calendar.isDate($0.date, inSameDayAs: yesterday) })?.value,
                   let hrv = hrvData.first(where: { calendar.isDate($0.date, inSameDayAs: today) })?.value,
                   let rhr = rhrData.first(where: { calendar.isDate($0.date, inSameDayAs: today) })?.value {
                    let recentCarbs = nutrition.first(where: { calendar.isDate($0.date, inSameDayAs: yesterday) })?.totalCarbs ?? 250.0
                    do {
                        let result = try PerformancePredictor.predictWithUncertainty(
                            models: trainedModels,
                            activityType: primaryActivity,
                            sleepHours: sleep,
                            hrvMs: hrv,
                            restingHR: rhr,
                            acwr: acwr,
                            carbs: recentCarbs
                        )
                        mlPrediction = result.prediction
                        mlFeatureWeights = trainedModels.first(where: { $0.activityType == result.prediction.activityType })?.featureWeights
                    } catch {
                        mlError = mlError ?? error.localizedDescription
                    }
                } else {
                    mlError = mlError ?? "Missing recent sleep, HRV, or resting HR data"
                }
            }

            //    5c. Intent-Aware Readiness
            let intentAwareAssessment: EnhancedIntentAwareReadinessService.EnhancedReadinessAssessment? = intentLabels.isEmpty ? nil :
                intentAwareService.calculateEnhancedReadiness(
                    workouts: storedWorkouts,
                    labels: intentLabels,
                    sleep: sleepData,
                    hrv: hrvData
                )

            // 6. Training Zone, Fitness Trend, Temporal, Load Analysis
            //    (moved from ReadinessViewModel per GEMINI.md mandate)
            let zoneAnalysis = zoneAnalyzer.analyzeTrainingZones(workouts: workouts)

            let healthKitManager = HealthKitManager.shared
            let userAge = healthKitManager.getUserAge() ?? 35
            let userGender = healthKitManager.getUserBiologicalSex()
            let fitnessAnalysis = fitnessTrendAnalyzer.analyzeFitnessTrends(
                vo2maxData: vo2maxData,
                workouts: workouts,
                hrvData: hrvData,
                rhrData: rhrData,
                userAge: userAge,
                userGender: userGender
            )

            let temporalAnalysis = temporalService.analyzeTemporalPatterns(
                workouts: workouts,
                activityType: primaryActivity
            )

            let recoveryInsights = correlationEngineRepo.analyzeRecoveryStatus(
                restingHRData: rhrData,
                hrvData: hrvData
            )
            
            let storedDailyScores = (try? modelContext.fetch(FetchDescriptor<StoredDailyScore>())) ?? []
            let dailyReadinessDict = storedDailyScores.reduce(into: [Date: Int]()) { result, score in
                let day = calendar.startOfDay(for: score.date)
                result[day] = score.readinessScore
            }
            
            let trainingLoadSummary = loadCalculator.calculateTrainingLoad(
                healthKitWorkouts: workouts,
                stravaActivities: [],
                stepData: stepData,
                recoveryInsights: recoveryInsights,
                dailyReadiness: dailyReadinessDict
            )

            let acwrTrend = calculateImprovedACWRTrend(workouts: workouts, ftpSnapshots: ftpSnapshots)

            let loadVisualization = loadVizService.generateLoadVisualization(
                workouts: loadHistoryWorkouts,
                labels: intentLabels,
                ftpSnapshots: ftpSnapshots,
                daysBack: 90
            )

            // 7. Coaching Instruction (moved from ReadinessViewModel per GEMINI.md mandate)
            let rawInstruction = coachingService.generateDailyInstruction(
                readiness: readinessAssessmentResult,
                insights: [],
                recovery: recoveryInsights,
                prediction: mlPrediction
            )
            let dailyInstruction = CoachingService.DailyInstruction(
                status: rawInstruction.status,
                headline: rawInstruction.headline,
                subline: rawInstruction.subline,
                primaryInsight: rawInstruction.primaryInsight,
                targetAction: rawInstruction.targetAction?.replacingOccurrences(of: "workout", with: primaryActivity.lowercased())
            )

            // 8. Insights Sub-services (moved from InsightsViewModel per GEMINI.md mandate)
            let sleepPerformanceInsight = correlationEngineRepo.analyzeSleepVsPerformanceCombined(
                sleepData: sleepData, healthKitWorkouts: workouts, stravaActivities: []
            )
            let activityTypeInsights = correlationEngineRepo.analyzeSleepVsPerformanceByActivityType(
                sleepData: sleepData, healthKitWorkouts: workouts, stravaActivities: []
            )
            let insightDataSummary = correlationEngineRepo.getDataSummary(
                sleepData: sleepData, healthKitWorkouts: workouts, stravaActivities: []
            )
            let simpleInsights = correlationEngineRepo.generateSimpleInsights(
                sleepData: sleepData, healthKitWorkouts: workouts, stravaActivities: [],
                restingHRData: rhrData, hrvData: hrvData
            )
            let hrvPerformanceInsights = correlationEngineRepo.analyzeHRVVsPerformance(
                hrvData: hrvData, healthKitWorkouts: workouts, stravaActivities: []
            )
            let proteinRecoveryInsight = nutritionEngine.analyzeProteinVsRecovery(
                nutritionData: nutrition, restingHRData: rhrData, hrvData: hrvData
            )
            let proteinPerformanceInsights = nutritionEngine.analyzeProteinVsPerformance(
                nutritionData: nutrition, healthKitWorkouts: workouts, stravaActivities: []
            )
            let carbPerformanceInsights = nutritionEngine.analyzeCarbsVsPerformance(
                nutritionData: nutrition, healthKitWorkouts: workouts, stravaActivities: []
            )
            let insightsRecommendations = actionableRecommendations.generateRecommendations(
                trainingLoad: trainingLoadSummary,
                recoveryInsights: recoveryInsights,
                trends: trends,
                injuryRisk: riskAssessment
            )
            let agingAssessment = await agingService.calculateAgingAlpha(modelContext: modelContext)
            
            let powerAnalysis = await cyclingPowerAnalyzer.analyzeCompoundScore(
                workouts: workouts,
                weightData: weightData
            )

            // 9. Generate Master Coach Message
            let computedForecast = compute7DayForecast(modelContext: modelContext, overrideACWR: readinessAssessmentResult.acwr)
            let nextDay = calendar.date(byAdding: .day, value: 1, to: today) ?? Date()
            let nextDayCoaching = computedForecast?.first(where: { calendar.isDate($0.date, inSameDayAs: nextDay) })?.coaching
            let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: today) ?? today
            let allStoredPatterns = (try? modelContext.fetch(FetchDescriptor<TrainingPattern>())) ?? []
            let activePatternTypes = allStoredPatterns
                .filter { $0.detectedAt >= sevenDaysAgo }
                .map(\.patternType)
            
            let allMemories = (try? modelContext.fetch(FetchDescriptor<CoachMemoryNote>())) ?? []
            
            let coachState = MasterCoachEngine.StateVector(
                morningScore: baseReadiness.score,
                currentScore: intraDay.currentScore,
                nextDayForecast: nextDayCoaching,
                acwr: readinessAssessmentResult.acwr,
                injuryRisk: riskAssessment.riskLevel,
                activePatterns: activePatternTypes.map(\.rawValue),
                memories: allMemories
            )
            let masterCoachMessage = await MasterCoachEngine.generateMessage(state: coachState)
            
            // Phase 4: Smart Routing Activity Readiness
            let activityReadinessScores = SmartRoutingEngine.generateActivityReadiness(baseScore: intraDay.currentScore, memories: allMemories)

            // Per-tab outputs (Phase 1.2)
            let todayWorkouts = workouts.filter { calendar.isDate($0.startDate, inSameDayAs: today) }
            let todayStepsValue = stepData
                .filter { calendar.isDate($0.date, inSameDayAs: today) }
                .map(\.value)
                .reduce(0, +)
            let todaySteps = Int(todayStepsValue)
            let cardiovascularStrain = await computeCardiovascularStrain(rhrData: rhrData)
            let holisticMetrics = buildHolisticMetrics(
                workouts: workouts,
                stepData: stepData,
                hrvData: hrvData,
                sleepData: sleepData,
                trainingLoad: trainingLoad,
                readinessScore: baseReadiness.score
            )

            // 10. Update Published State
            self.currentReadiness = UnifiedReadiness(
                score: intraDay.currentScore,
                morningScore: baseReadiness.score,
                level: mapScoreToLevel(intraDay.currentScore),
                recommendation: reconciledRecommendation,
                injuryRisk: riskAssessment,
                breakdown: baseReadiness.breakdown,
                trend: baseReadiness.trend,
                date: now,
                intraDay: intraDay,
                coachAdvice: masterCoachMessage,
                overnightRecoveryMultiplier: recoveryMultiplier,
                todayStepExcessTSS: todayStepExcessTSS,
                mlPrediction: mlPrediction,
                mlFeatureWeights: mlFeatureWeights,
                mlError: mlError,
                intentAwareAssessment: intentAwareAssessment,
                primaryActivity: primaryActivity,
                trainingLoadSummary: trainingLoadSummary,
                readinessAssessment: readinessAssessmentResult,
                acwrTrend: acwrTrend,
                loadVisualization: loadVisualization,
                temporalAnalysis: temporalAnalysis,
                zoneAnalysis: zoneAnalysis,
                fitnessAnalysis: fitnessAnalysis,
                dailyInstruction: dailyInstruction,
                activityReadiness: activityReadinessScores,
                metricTrends: trends,
                sleepPerformanceInsight: sleepPerformanceInsight,
                activityTypeInsights: activityTypeInsights,
                dataSummary: insightDataSummary,
                simpleInsights: simpleInsights,
                hrvPerformanceInsights: hrvPerformanceInsights,
                proteinRecoveryInsight: proteinRecoveryInsight,
                proteinPerformanceInsights: proteinPerformanceInsights,
                carbPerformanceInsights: carbPerformanceInsights,
                recommendations: insightsRecommendations,
                agingAssessment: agingAssessment,
                compoundScoreAnalysis: powerAnalysis,
                todayWorkouts: todayWorkouts,
                todaySteps: todaySteps,
                cardiovascularStrain: cardiovascularStrain,
                holisticMetrics: holisticMetrics,
                hrvData: hrvData,
                rhrData: rhrData,
                sleepData: sleepData,
                stepCountData: stepData,
                workouts: workouts,
                weightData: weightData
            )

            self.intraDayReadiness = intraDay
            self.lastFingerprint = fingerprint
            self.lastAnalysisDate = now

            // Persist today's readiness score for 90-day back-to-back crash pattern detection.
            let todayWorkoutsForLoad = workouts.filter { calendar.isDate($0.startDate, inSameDayAs: today) }
            let ftpSnapshotsForLoad = (try? modelContext.fetch(FetchDescriptor<StoredFTPSnapshot>())) ?? []
            let todayTotalLoad = todayWorkoutsForLoad.reduce(0.0) {
                $0 + predictiveReadinessService.calculateWorkoutLoad($1, ftpSnapshots: ftpSnapshotsForLoad)
            }
            upsertDailyScore(
                date: today,
                score: baseReadiness.score,
                acwr: readinessAssessmentResult.acwr,
                workoutCount: todayWorkoutsForLoad.count,
                dailyLoad: todayTotalLoad,
                modelContext: modelContext
            )

            // 7-day readiness forecast (requires 14 days of stored scores).
            // If nil, force a HealthKit backfill to fill any gaps and retry once.
            if let f = computedForecast {
                self.forecast = f
            } else {
                await backfillHistoricalScores(modelContext: modelContext, force: true)
                self.forecast = compute7DayForecast(modelContext: modelContext, overrideACWR: readinessAssessmentResult.acwr)
            }

            #if DEBUG
            print("✅ ReadinessRepository: Unified Analysis Complete. Score: \(baseReadiness.score)")
            #endif

        } catch {
            #if DEBUG
            print("❌ ReadinessRepository Error: \(error)")
            #endif
            analysisError = error.localizedDescription
        }

        isAnalyzing = false

        // Data changed while we were working — re-run against it. refreshIfNecessary
        // recomputes the fingerprint, so this is a no-op unless the store actually
        // moved, which bounds the recursion to real changes.
        if pendingRefreshRequested {
            pendingRefreshRequested = false
            await refreshIfNecessary(modelContext: modelContext)
        }
    }

    // MARK: - Daily Score Persistence

    /// Upserts today's readiness score into StoredDailyScore for 90-day pattern analysis.
    /// Dedup is in-memory (dateString equality) — avoids @Attribute(.unique) migration risk.
    private func upsertDailyScore(
        date: Date,
        score: Int,
        acwr: Double,
        workoutCount: Int,
        dailyLoad: Double,
        modelContext: ModelContext
    ) {
        let dateStr = Self.dailyScoreDateFormatter.string(from: date)

        // Fetch only today's record via predicate rather than all records.
        let predicate = #Predicate<StoredDailyScore> { $0.dateString == dateStr }
        let todayScores = (try? modelContext.fetch(FetchDescriptor(predicate: predicate))) ?? []
        if let existing = todayScores.first {
            existing.readinessScore = score
            existing.dailyStrain = acwr
            existing.workoutCount = workoutCount
            existing.dailyLoad = dailyLoad
        } else {
            let record = StoredDailyScore(
                date: date,
                readinessScore: score,
                dailyStrain: acwr,
                workoutCount: workoutCount,
                dailyLoad: dailyLoad
            )
            modelContext.insert(record)
        }
        try? modelContext.save()
    }

    // MARK: - Historical Score Backfill

    /// Populates StoredDailyScore for the last 90 days from already-synced SwiftData records.
    /// Runs once on first launch (UserDefaults gate) and re-runs whenever fewer than 14 records
    /// exist (e.g. after a data clear). This unlocks the 7-day forecast and 14-Day Signature
    /// without requiring 14 consecutive days of app opens.
    private func backfillHistoricalScores(modelContext: ModelContext, force: Bool = false) async {
        // V5: diagnose existingDates vs per-day filter failure.
        let udKey = "historicalScoreBackfillV5Done"
        let existingCount = (try? modelContext.fetchCount(FetchDescriptor<StoredDailyScore>())) ?? 0

        // Re-run if there are gap days since the last stored score — covers the case where
        // the user doesn't open the app every day and recent history has holes.
        let hasRecentGap: Bool = {
            let cal = Calendar.current
            let yday = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: Date())) ?? Date()
            let allScores = (try? modelContext.fetch(FetchDescriptor<StoredDailyScore>())) ?? []
            guard let lastDate = allScores.map({ cal.startOfDay(for: $0.date) }).max() else { return true }
            return (cal.dateComponents([.day], from: lastDate, to: yday).day ?? 0) >= 1
        }()

        guard force || !UserDefaults.standard.bool(forKey: udKey) || existingCount < 14 || hasRecentGap else { return }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let ninetyDaysAgo  = calendar.date(byAdding: .day, value: -90, to: today),
              let yesterday       = calendar.date(byAdding: .day, value:  -1, to: today),
              let fetchStart      = calendar.date(byAdding: .day, value: -28, to: ninetyDaysAgo)
        else { return }

        let hk = HealthKitManager.shared

        // Pull 90+28 days of biometrics straight from HealthKit — this is the only source
        // that has historical data predating the app install.
        async let rhrFetch  = try? hk.fetchRestingHeartRate(startDate: fetchStart, endDate: today)
        async let hrvFetch  = try? hk.fetchHeartRateVariability(startDate: fetchStart, endDate: today)
        async let sleepFetch = try? hk.fetchSleepDuration(startDate: fetchStart, endDate: today)
        async let hkWorkoutFetch = try? hk.fetchWorkouts(startDate: fetchStart, endDate: today)

        let (allRHR, allHRV, allSleep, hkWorkouts) = await (
            rhrFetch ?? [],
            hrvFetch ?? [],
            sleepFetch ?? [],
            hkWorkoutFetch ?? []
        )


        // Workouts: merge HealthKit history with StoredWorkout (has Strava power data).
        // StoredWorkout wins on overlap via date-key dedup so zone-weighted loads are preserved.
        let workoutDescriptor = FetchDescriptor<StoredWorkout>(
            predicate: #Predicate { $0.startDate >= fetchStart },
            sortBy: [SortDescriptor(\.startDate)]
        )
        let storedWorkouts = (try? modelContext.fetch(workoutDescriptor)) ?? []
        let ftpSnapshots   = (try? modelContext.fetch(FetchDescriptor<StoredFTPSnapshot>())) ?? []

        // Build a merged workout list: prefer StoredWorkout (richer data), fill gaps from HK.
        let storedWorkoutDates = Set(storedWorkouts.map { calendar.startOfDay(for: $0.startDate) })
        let hkOnlyWorkouts = hkWorkouts.filter { !storedWorkoutDates.contains(calendar.startOfDay(for: $0.startDate)) }
        let allWorkouts = storedWorkouts.map { WorkoutData(from: $0) } + hkOnlyWorkouts

        // Skip dates that already have a StoredDailyScore.
        let allExisting  = (try? modelContext.fetch(FetchDescriptor<StoredDailyScore>())) ?? []
        let existingDates = Set(allExisting.map { $0.dateString })

        let formatter = Self.dailyScoreDateFormatter
        var inserted = 0

        var day = ninetyDaysAgo
        while day <= yesterday {
            let dateStr = formatter.string(from: day)
            defer { day = calendar.date(byAdding: .day, value: 1, to: day) ?? today }

            guard !existingDates.contains(dateStr) else { continue }

            guard let dayEnd          = calendar.date(byAdding: .day, value:  1, to: day),
                  let window7Start    = calendar.date(byAdding: .day, value:  -7, to: day),
                  let window28Start   = calendar.date(byAdding: .day, value: -28, to: day),
                  let biometricStart  = calendar.date(byAdding: .day, value:  -1, to: day)
            else { continue }

            // ±1-day biometric window — HK records timestamps vary (midnight, morning, etc.)
            let rhrDay   = allRHR.filter   { $0.date >= biometricStart && $0.date < dayEnd }
            let hrvDay   = allHRV.filter   { $0.date >= biometricStart && $0.date < dayEnd }
            let sleepDay = allSleep.filter { $0.date >= biometricStart && $0.date < dayEnd }

            guard (!hrvDay.isEmpty || !rhrDay.isEmpty), !sleepDay.isEmpty else { continue }

            let workoutsInWindow = allWorkouts.filter { $0.startDate >= window28Start && $0.startDate < dayEnd }
            let todayWorkouts    = allWorkouts.filter { calendar.isDate($0.startDate, inSameDayAs: day) }

            guard let readiness = readinessAnalyzer.analyzeReadiness(
                restingHR: rhrDay,
                hrv: hrvDay,
                sleep: sleepDay,
                workouts: workoutsInWindow,
                stravaActivities: [],
                nutrition: []
            ) else { continue }

            // ACWR computed with date-relative windows (PredictiveReadinessService uses Date()).
            let acuteLoad   = allWorkouts.filter { $0.startDate >= window7Start  && $0.startDate < dayEnd }
                .reduce(0.0) { $0 + predictiveReadinessService.calculateWorkoutLoad($1, ftpSnapshots: ftpSnapshots) } / 7.0
            let chronicLoad = allWorkouts.filter { $0.startDate >= window28Start && $0.startDate < dayEnd }
                .reduce(0.0) { $0 + predictiveReadinessService.calculateWorkoutLoad($1, ftpSnapshots: ftpSnapshots) } / 28.0
            let acwr = chronicLoad > 0 ? acuteLoad / chronicLoad : 1.0

            let dayLoad = todayWorkouts.reduce(0.0) {
                $0 + predictiveReadinessService.calculateWorkoutLoad($1, ftpSnapshots: ftpSnapshots)
            }
            modelContext.insert(StoredDailyScore(
                date: day,
                readinessScore: readiness.score,
                dailyStrain: acwr,
                workoutCount: todayWorkouts.count,
                dailyLoad: dayLoad
            ))
            inserted += 1
        }

        if inserted > 0 {
            try? modelContext.save()
        }

        UserDefaults.standard.removeObject(forKey: "lastPatternAnalysisDate")
        UserDefaults.standard.set(true, forKey: udKey)

        #if DEBUG
        if inserted > 0 { print("📅 Backfill: inserted \(inserted) historical StoredDailyScore records") }
        #endif
    }

    /// One-time migration: populates dailyLoad on all existing StoredDailyScore rows from StoredWorkout.
    /// Existing rows got dailyLoad=0.0 from the lightweight SwiftData migration — this fixes them so
    /// the back-to-back crash detector can distinguish warmups (< 1.0 TSS) from real training days.
    private func backfillDailyLoad(modelContext: ModelContext) {
        let udKey = "dailyLoadBackfillV1Done"
        guard !UserDefaults.standard.bool(forKey: udKey) else { return }

        let allScores = (try? modelContext.fetch(FetchDescriptor<StoredDailyScore>())) ?? []
        let ftpSnapshots = (try? modelContext.fetch(FetchDescriptor<StoredFTPSnapshot>())) ?? []
        let storedWorkouts = (try? modelContext.fetch(FetchDescriptor<StoredWorkout>())) ?? []

        #if DEBUG
        if allScores.isEmpty { print("⚠️ backfillDailyLoad: no StoredDailyScore records found — migration skipped") }
        #endif

        let calendar = Calendar.current
        for score in allScores {
            let dayStart = calendar.startOfDay(for: score.date)
            guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { continue }
            let load = storedWorkouts
                .filter { $0.startDate >= dayStart && $0.startDate < dayEnd }
                .reduce(0.0) {
                    $0 + predictiveReadinessService.calculateWorkoutLoad(WorkoutData(from: $1), ftpSnapshots: ftpSnapshots)
                }
            score.dailyLoad = load
        }

        try? modelContext.save()
        UserDefaults.standard.set(true, forKey: udKey)
    }

    // MARK: - 7-Day Readiness Forecast

    /// Computes a 7-day readiness forecast from the last 14 StoredDailyScore entries.
    /// Returns nil when fewer than 14 stored scores exist (insufficient trend window).
    /// Published as `self.forecast` at the end of performFullAnalysis().
    /// `overrideACWR` is exposed for unit testing only — pass nil in production.
    /// In production the ACWR is read from `currentReadiness?.readinessAssessment?.acwr`.
    func compute7DayForecast(modelContext: ModelContext, overrideACWR: Double? = nil) -> [ReadinessForecastDay]? {
        let calendar = Calendar.current
        let cutoff = calendar.date(byAdding: .day, value: -14, to: Date()) ?? Date()
        let predicate = #Predicate<StoredDailyScore> { $0.date >= cutoff }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.sortBy = [SortDescriptor(\.date)]
        let recent = (try? modelContext.fetch(descriptor)) ?? []
        // Deduplicate by calendar day — duplicate-day rows from a race condition or
        // schema migration would corrupt the OLS input (two identical X-coords).
        let deduped = Dictionary(
            recent.map { (Self.dailyScoreDateFormatter.string(from: $0.date), $0) },
            uniquingKeysWith: { $1 }
        ).values.sorted { $0.date < $1.date }
        guard deduped.count >= 14 else { return nil }
        let last14 = Array(deduped.suffix(14))

        // Linear regression on last 14 readiness scores
        let xVals = (0..<14).map { Double($0) }
        let yVals = last14.map { Double($0.readinessScore) }
        guard let reg = StatisticalValidator.linearRegression(x: xVals, y: yVals) else { return nil }

        // Baseline standard deviation for confidence bands
        let meanY = yVals.reduce(0, +) / Double(yVals.count)
        let variance = yVals.map { ($0 - meanY) * ($0 - meanY) }.reduce(0, +) / Double(yVals.count)
        let baselineSigma = (variance > 0 ? sqrt(variance) : 5.0) / 2.0

        // ACWR modifier from current published readiness (or test override)
        let acwr = overrideACWR ?? currentReadiness?.readinessAssessment?.acwr

        // Pure regression + ACWR modifier. No intra-forecast workout simulation:
        // a coaching-label feedback loop here (hard day → -25 next day) turns a
        // flat history into a sawtooth forecast and breaks the documented
        // contract (flat trend → near baseline; ACWR>1.3 → monotonic decay).
        var days: [ReadinessForecastDay] = []
        for d in 1...7 {
            let xDay = Double(13 + d)  // extends the trend beyond the 14-day window
            var predicted = reg.slope * xDay + reg.intercept

            if let acwr {
                if acwr > 1.3 {
                    predicted -= predicted * 0.03 * Double(d)  // decay 3%/day under overload
                } else if acwr < 0.8 {
                    predicted += predicted * 0.02 * Double(d)  // improve 2%/day during underload
                } else {
                    // Homeostasis: in the sweet spot, naturally drift back towards optimal baseline (75)
                    predicted += (75.0 - predicted) * 0.10 * Double(d)
                }
            } else {
                predicted += (75.0 - predicted) * 0.10 * Double(d)
            }

            let clamped = max(20.0, min(100.0, predicted))
            let sigma = min(15.0, baselineSigma * sqrt(Double(d)))
            let lo = max(0,   Int((clamped - sigma).rounded()))
            let hi = min(100, Int((clamped + sigma).rounded()))

            let coaching: String
            let score = Int(clamped.rounded())
            if score >= 80 {
                coaching = "Hard effort OK"
            } else if score >= 70 {
                coaching = "Moderate training"
            } else if score >= 60 {
                coaching = "Easy only"
            } else {
                coaching = "Rest recommended"
            }

            let date = calendar.date(byAdding: .day, value: d, to: calendar.startOfDay(for: Date())) ?? Date()
            days.append(ReadinessForecastDay(
                date: date,
                predictedReadiness: score,
                confidenceLow: lo,
                confidenceHigh: hi,
                coaching: coaching
            ))
        }
        return days
    }

    // MARK: - Primary Activity Detection (moved from ReadinessViewModel)

    private func determinePrimaryActivity(from workouts: [WorkoutData]) -> String {
        let calendar = Calendar.current
        let ninetyDaysAgo = calendar.date(byAdding: .day, value: -90, to: Date()) ?? Date()
        var counts: [String: Int] = [:]
        for workout in workouts where workout.startDate >= ninetyDaysAgo {
            switch workout.workoutType {
            case .cycling: counts["Ride", default: 0] += 1
            case .running:  counts["Run",  default: 0] += 1
            case .swimming: counts["Swim", default: 0] += 1
            default: break
            }
        }
        return counts.max(by: { $0.value < $1.value })?.key ?? "Ride"
    }

    private func calculateImprovedACWRTrend(workouts: [WorkoutData], ftpSnapshots: [StoredFTPSnapshot]) -> [ACWRDataPoint] {
        // Delegates to the one ACWR engine. This loop used to live here and passed
        // `startOfDay(targetDate)` as the reference date, which closed every day's
        // window at midnight *before* that day's training: the chart's last point
        // ignored today's ride entirely and sat below the assessment printed
        // beside it, and each earlier point was shifted a day late.
        predictiveReadinessService.calculateACWRTrend(
            healthKitWorkouts: workouts,
            ftpSnapshots: ftpSnapshots,
            days: 7
        )
    }

    // MARK: - Reconciler
    
    private func reconcileAdvice(
        readiness: ReadinessAnalyzer.ReadinessScore,
        risk: InjuryRiskCalculator.InjuryRiskAssessment,
        hrvRec: DailyRecommendationService.DailyRecommendation
    ) -> String {
        
        // 1. HARD OVERRIDE: High or Very High risk always wins
        if risk.riskLevel == .high || risk.riskLevel == .veryHigh {
            if hrvRec.status == .goHard || hrvRec.status == .quality {
                return "Your nervous system is ready, but your training load spike is risky (High Injury Risk). Play it safe: swap today's hard session for easy aerobic work."
            }
            return risk.recommendation
        }
        
        // 2. MODERATE TEMPERING: If HRV is pushing but load is building
        if risk.riskLevel == .moderate && (hrvRec.status == .goHard || hrvRec.status == .quality) {
            return "You're fresh, but injury risk is moderate due to recent load spikes. You can do quality work, but avoid back-to-back hard days and focus on recovery."
        }
        
        // 3. LOW HRV OVERRIDE: If HRV says rest, we listen even if load is low
        if hrvRec.status == .rest || hrvRec.status == .easy {
            return hrvRec.guidance
        }
        
        // 4. SYNERGY: If both are good, give the green light
        if readiness.score >= 70 && (hrvRec.status == .goHard || hrvRec.status == .quality) {
            return hrvRec.guidance
        }
        
        // Fallback
        return hrvRec.guidance
    }
    
    // MARK: - Helpers
    
    private func calculateFingerprint(context: ModelContext) throws -> PredictionCache.DataFingerprint {
        let workoutCount = try context.fetchCount(FetchDescriptor<StoredWorkout>())
        let sleepCount   = try context.fetchCount(FetchDescriptor<StoredHealthMetric>(predicate: #Predicate { $0.type == "Sleep" }))
        let hrvCount     = try context.fetchCount(FetchDescriptor<StoredHealthMetric>(predicate: #Predicate { $0.type == "HRV" }))
        let rhrCount     = try context.fetchCount(FetchDescriptor<StoredHealthMetric>(predicate: #Predicate { $0.type == "RHR" }))

        // Fetch most-recent date per signal to detect new records that arrive without changing counts.
        var workoutLatestDesc = FetchDescriptor<StoredWorkout>(sortBy: [SortDescriptor(\.startDate, order: .reverse)])
        workoutLatestDesc.fetchLimit = 1

        var sleepLatestDesc = FetchDescriptor<StoredHealthMetric>(
            predicate: #Predicate { $0.type == "Sleep" },
            sortBy: [SortDescriptor(\.date, order: .reverse)])
        sleepLatestDesc.fetchLimit = 1

        var hrvLatestDesc = FetchDescriptor<StoredHealthMetric>(
            predicate: #Predicate { $0.type == "HRV" },
            sortBy: [SortDescriptor(\.date, order: .reverse)])
        hrvLatestDesc.fetchLimit = 1

        var rhrLatestDesc = FetchDescriptor<StoredHealthMetric>(
            predicate: #Predicate { $0.type == "RHR" },
            sortBy: [SortDescriptor(\.date, order: .reverse)])
        rhrLatestDesc.fetchLimit = 1

        let latestWorkout = try context.fetch(workoutLatestDesc).first?.startDate
        let latestSleep   = try context.fetch(sleepLatestDesc).first?.date
        let latestHRV     = try context.fetch(hrvLatestDesc).first?.date
        let latestRHR     = try context.fetch(rhrLatestDesc).first?.date

        return PredictionCache.DataFingerprint(
            workoutCount:      workoutCount,
            sleepCount:        sleepCount,
            hrvCount:          hrvCount,
            rhrCount:          rhrCount,
            latestWorkoutDate: latestWorkout,
            latestSleepDate:   latestSleep,
            latestHRVDate:     latestHRV,
            latestRHRDate:     latestRHR
        )
    }
    
    private func mapScoreToLevel(_ score: Int) -> ReadinessLevel {
        if score >= 80 { return .excellent }
        if score >= 70 { return .good }
        if score >= 60 { return .moderate }
        return .poor
    }

    // MARK: - Cardiovascular Strain (moved from ReadinessViewModel — Phase 1.2)

    /// Returns maxHR from UserDefaults cache if < 7 days old, otherwise queries HealthKit
    /// and refreshes the cache. Falls back to 220-age only if HealthKit returns no data.
    private func resolvedMaxHR() async -> Double {
        let defaults = UserDefaults.standard
        let cacheDate = defaults.object(forKey: Self.maxHRCacheDateKey) as? Date ?? .distantPast
        let isFresh = Date().timeIntervalSince(cacheDate) < Self.maxHRCacheTTL
        let cached = defaults.double(forKey: Self.maxHRCacheKey)

        if isFresh, cached > 100 {
            return cached
        }

        if let personal = try? await HealthKitManager.shared.fetchPersonalMaxHR(over: 90), personal > 100 {
            defaults.set(personal, forKey: Self.maxHRCacheKey)
            defaults.set(Date(), forKey: Self.maxHRCacheDateKey)
            return personal
        }

        let age = HealthKitManager.shared.getUserAge() ?? 35
        return 220.0 - Double(age)
    }

    private func computeCardiovascularStrain(rhrData: [HealthDataPoint]) async -> CardiovascularStrainService.Result? {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        let now = Date()

        async let hrSamplesTask = HealthKitManager.shared.fetchRawHeartRateSamples(
            startDate: todayStart, endDate: now
        )
        let maxHR = await resolvedMaxHR()
        let hrSamples = (try? await hrSamplesTask) ?? []
        let restingHR = rhrData.last?.value ?? 55.0

        let sensitivityOffset = UserDefaults.standard.double(forKey: "strainSensitivityOffset")
        return cardiovascularStrainService.compute(
            todayHRSamples: hrSamples,
            estimatedMaxHR: maxHR,
            restingHR: restingHR,
            sensitivityOffset: sensitivityOffset
        )
    }

    // MARK: - Holistic Metrics (moved from DashboardViewModel — Phase 1.2)

    private func buildHolisticMetrics(
        workouts: [WorkoutData],
        stepData: [HealthDataPoint],
        hrvData: [HealthDataPoint],
        sleepData: [HealthDataPoint],
        trainingLoad: TrainingLoadCalculator.TrainingLoadSummary?,
        readinessScore: Int
    ) -> HealthMetrics {
        let metSummary = metAnalyzer.analyzeMETActivity(
            healthKitWorkouts: workouts,
            stravaActivities: [],
            stepData: stepData
        )
        let balance = balanceAnalyzer.analyzeTrainingBalance(
            healthKitWorkouts: workouts,
            stravaActivities: []
        )

        let metStatus: MetricStatus = {
            guard let summary = metSummary else { return .needsAttention }
            switch summary.status {
            case .excellent: return .excellent
            case .good: return .good
            case .moderate: return .moderate
            case .insufficient: return .needsAttention
            }
        }()

        let trainingBalanceStatus: MetricStatus = {
            guard let bal = balance else { return .needsAttention }
            switch bal.balance {
            case .optimal: return .excellent
            case .enduranceDominant, .strengthDominant: return .moderate
            case .missingStrength, .missingEndurance: return .needsAttention
            case .needsMobility: return .good
            }
        }()

        let hrvBaselineMs: Double? = {
            let thirtyDayData = hrvData.suffix(30).map(\.value)
            guard thirtyDayData.count >= 7 else { return nil }
            return thirtyDayData.reduce(0, +) / Double(thirtyDayData.count)
        }()

        let hrvStatus: MetricStatus = {
            let recentHRVData = hrvData.suffix(7).map(\.value)
            guard !recentHRVData.isEmpty else { return .needsAttention }
            let recentHRV = recentHRVData.reduce(0, +) / Double(recentHRVData.count)
            if recentHRV >= 60 { return .excellent }
            if recentHRV >= 45 { return .good }
            if recentHRV >= 30 { return .moderate }
            return .needsAttention
        }()

        let loadStatus: MetricStatus = {
            guard let ld = trainingLoad else { return .good }
            switch ld.status {
            case .optimal: return .excellent
            case .fresh: return .good
            case .fatigued: return .moderate
            case .overreaching: return .needsAttention
            }
        }()

        let sleepStatus: MetricStatus = {
            let recentSleepData = sleepData.suffix(7).map(\.value)
            guard !recentSleepData.isEmpty else { return .needsAttention }
            let avgSleep = recentSleepData.reduce(0, +) / Double(recentSleepData.count)
            if avgSleep >= 8 { return .excellent }
            if avgSleep >= 7 { return .good }
            if avgSleep >= 6 { return .moderate }
            return .needsAttention
        }()

        let readinessStatus: MetricStatus = {
            if readinessScore >= 80 { return .excellent }
            if readinessScore >= 70 { return .good }
            if readinessScore >= 60 { return .moderate }
            return .needsAttention
        }()

        let recentSleepWindow = sleepData.suffix(7).map(\.value)
        let averageSleep = recentSleepWindow.isEmpty
            ? 0
            : recentSleepWindow.reduce(0, +) / Double(recentSleepWindow.count)

        return HealthMetrics(
            weeklyMETMinutes: metSummary?.weeklyMETMinutes ?? 0,
            metStatus: metStatus,
            strengthPercentage: balance?.strengthPercentage ?? 0,
            trainingBalance: trainingBalanceStatus,
            currentHRV: hrvData.last?.value ?? 0,
            hrvStatus: hrvStatus,
            hrvBaselineMs: hrvBaselineMs,
            acwr: trainingLoad?.acuteChronicRatio ?? 1.0,
            loadStatus: loadStatus,
            averageSleep: averageSleep,
            sleepStatus: sleepStatus,
            readinessScore: readinessScore,
            readinessStatus: readinessStatus
        )
    }
}
