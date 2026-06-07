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
            breakdown: unified.breakdown
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
        self.overnightRecoveryMultiplier = unified.overnightRecoveryMultiplier
        self.todayStepExcessTSS = unified.todayStepExcessTSS

        // Per-tab outputs (Phase 1.2 — now owned by ReadinessRepository)
        self.todayWorkouts = unified.todayWorkouts
        self.todaySteps = unified.todaySteps
        self.cardiovascularStrain = unified.cardiovascularStrain
        self.dailyTSSData = calculateDailyTSS(workouts: unified.workouts, stepData: unified.stepCountData)
    }
    
    // Training Load (moved from InsightsViewModel)
    @Published var trainingLoadSummary: TrainingLoadCalculator.TrainingLoadSummary?
    @Published var readinessAssessment: PredictiveReadinessService.ReadinessAssessment?
    @Published var acwrTrend: [ACWRDataPoint] = []
    @Published var loadVisualization: TrainingLoadVisualizationService.LoadVisualizationData?
    @Published var primaryActivity: String = "Ride"
    @Published var dailyTSSData: [DailyTSSData] = []
    @Published var selectedPeriod: TimePeriod = .quarter
    @Published var todayWorkouts: [WorkoutData] = []
    @Published var cardiovascularStrain: CardiovascularStrainService.Result?
    @Published var todaySteps: Int = 0
    @Published var overnightRecoveryMultiplier: Double = 1.0
    @Published var todayStepExcessTSS: Double = 0

    // UserDefaults keys for maxHR cache (refresh weekly — doesn't change fast).
    private static let maxHRCacheKey = "cachedPersonalMaxHR"
    private static let maxHRCacheDateKey = "cachedPersonalMaxHRDate"
    private static let maxHRCacheTTL: TimeInterval = 7 * 86400 // 7 days

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
                    #if DEBUG
                    print("🔬 Discovering patterns from recent workouts only...")
                    #endif

                    // Only analyze last 365 days of data
                    let calendar = Calendar.current
                    let oneYearAgo = calendar.date(byAdding: .day, value: -365, to: Date())!
                    let recentWorkouts = workouts.filter { $0.startDate >= oneYearAgo }
                    let recentSleep = sleepData.filter { $0.date >= oneYearAgo }
                    let recentNutrition = nutrition.filter { $0.date >= oneYearAgo }

                    #if DEBUG
                    print("   Analyzing \(recentWorkouts.count) recent workouts (vs \(workouts.count) total)")
                    #endif

                    let statPatternAnalyzer = StatisticalPerformancePatternAnalyzer()
                    let validatedWindows = statPatternAnalyzer.discoverValidatedPatterns(
                        workouts: recentWorkouts,
                        activities: [],
                        sleep: recentSleep,
                        nutrition: recentNutrition
                    )
                    cachedPatterns = validatedWindows.map { $0.pattern }
                    lastPatternDiscovery = Date()
                    #if DEBUG
                    print("   Cached \(cachedPatterns?.count ?? 0) new patterns")
                    #endif
                } else {
                    #if DEBUG
                    print("   ✅ Using cached patterns from \(lastPatternDiscovery!)")
                    #endif
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
            
            // Populate todayWorkouts and today's step count
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            todayWorkouts = workouts.filter { calendar.isDate($0.startDate, inSameDayAs: today) }
            let todayStepValue = storedHealthMetrics
                .filter { $0.type == "Steps" && calendar.isDate($0.date, inSameDayAs: today) }
                .map(\.value).reduce(0, +)
            todaySteps = Int(todayStepValue)

            // Cardiovascular strain — live HealthKit query (not stored; too many raw samples).
            await computeCardiovascularStrain(rhrData: rhrData)
            
        } catch {
            errorMessage = "Failed to analyze readiness: \(error.localizedDescription)"
            #if DEBUG
            print("❌ Readiness analysis error: \(error)")
            #endif
        }
        
        isLoading = false
    }
    
    // calculateIntentAwareReadiness / fetchIntentLabels / determinePrimaryActivity removed — logic moved to ReadinessRepository
    // trainMLModelsIfNeeded / makePredictionWithUncertainty removed — logic moved to ReadinessRepository
    // generateDailyInstruction removed — logic moved to ReadinessRepository (GEMINI.md mandate)

    // MARK: - Cardiovascular Strain

    @MainActor
    private func computeCardiovascularStrain(rhrData: [HealthDataPoint]) async {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        let now = Date()

        // Fetch today's raw HR samples (lightweight — just today).
        async let hrSamplesTask = HealthKitManager.shared.fetchRawHeartRateSamples(
            startDate: todayStart, endDate: now
        )

        // MaxHR: use cached value if fresh, otherwise query HealthKit.
        let maxHR = await resolvedMaxHR()

        let hrSamples = (try? await hrSamplesTask) ?? []
        let restingHR = rhrData.last?.value ?? 55.0

        let sensitivityOffset = UserDefaults.standard.double(forKey: "strainSensitivityOffset")
        cardiovascularStrain = CardiovascularStrainService().compute(
            todayHRSamples: hrSamples,
            estimatedMaxHR: maxHR,
            restingHR: restingHR,
            sensitivityOffset: sensitivityOffset
        )
    }

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

        // Query HealthKit for the user's personal peak HR.
        if let personal = try? await HealthKitManager.shared.fetchPersonalMaxHR(over: 90), personal > 100 {
            defaults.set(personal, forKey: Self.maxHRCacheKey)
            defaults.set(Date(), forKey: Self.maxHRCacheDateKey)
            #if DEBUG
            print("✅ Personal maxHR updated: \(Int(personal)) bpm")
            #endif
            return personal
        }

        // Fallback: age-based formula (acknowledged as population average, not personal).
        let age = HealthKitManager.shared.getUserAge() ?? 35
        return 220.0 - Double(age)
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
        
        // Personal step baseline: 30-day rolling average (never hardcode 10k).
        // Falls back to 7,500 if there's no history yet (conservative, research-supported floor).
        let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: today)!
        let recentStepData = stepData.filter { $0.date >= thirtyDaysAgo }
        let stepBaseline: Double = recentStepData.isEmpty
            ? 7500
            : recentStepData.map(\.value).reduce(0, +) / Double(recentStepData.count)

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

            // Add NEAT load from steps above personal baseline.
            // Cap: on workout days steps ≤ 20% of workout load; on rest days ≤ 5 points.
            // This keeps steps as supporting load, never primary strain.
            if let stepPoint = stepData.first(where: { calendar.isDate($0.date, inSameDayAs: date) }) {
                let excessSteps = max(0, stepPoint.value - stepBaseline)
                if excessSteps > 0 {
                    // 3,000 excess steps ≈ 1 TSS point (mild linear ramp)
                    let rawStepTSS = excessSteps / 3000.0
                    let cap = dailyTSS > 0 ? dailyTSS * 0.20 : 5.0
                    dailyTSS += min(rawStepTSS, cap)
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
