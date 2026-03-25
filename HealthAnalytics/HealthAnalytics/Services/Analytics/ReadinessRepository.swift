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
    @Published private(set) var isAnalyzing = false
    
    // MARK: - Dependencies

    private let readinessAnalyzer = ReadinessAnalyzer()
    private let riskCalculator = InjuryRiskCalculator()
    private let recommendationService = DailyRecommendationService()
    private let loadCalculator = TrainingLoadCalculator()
    private let recoveryService = RecoveryDecayService()

    // ML sub-services (moved from ReadinessViewModel per GEMINI.md mandate)
    private let intentAwareService = EnhancedIntentAwareReadinessService()
    private let trendDetector = TrendDetector()
    private var trainedModels: [PerformancePredictor.TrainedModel] = []
    private var lastMLTraining: Date?

    private var lastFingerprint: PredictionCache.DataFingerprint?
    private var lastAnalysisDate: Date?
    
    private init() {}
    
    // MARK: - Models
    
    struct UnifiedReadiness {
        let score: Int
        let level: ReadinessLevel
        let recommendation: DailyRecommendationService.DailyRecommendation
        let injuryRisk: InjuryRiskCalculator.InjuryRiskAssessment
        let breakdown: ReadinessAnalyzer.ScoreBreakdown
        let trend: ReadinessAnalyzer.ReadinessScore.Trend
        let date: Date
        let intraDay: RecoveryDecayService.IntraDayReadiness

        // RECONCILED MESSAGE: The single "Master Coach" advice
        let coachAdvice: String

        // ML sub-service outputs (owned by Repository, not ViewModel)
        let mlPrediction: PerformancePredictor.Prediction?
        let mlFeatureWeights: PerformancePredictor.FeatureWeights?
        let mlError: String?
        let intentAwareAssessment: EnhancedIntentAwareReadinessService.EnhancedReadinessAssessment?
    }
    
    // MARK: - Main Analysis Entry Point
    
    func refreshIfNecessary(modelContext: ModelContext) async {
        // 1. Calculate current data fingerprint
        guard let fingerprint = try? calculateFingerprint(context: modelContext) else { return }
        
        // 2. Check if we can skip (Same data AND same day)
        if let lastDate = lastAnalysisDate,
           Calendar.current.isDateInToday(lastDate),
           fingerprint == lastFingerprint,
           currentReadiness != nil {
            print("✅ ReadinessRepository: Using cached unified analysis")
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
        isAnalyzing = true

        print("🔄 ReadinessRepository: Starting unified analysis...")

        do {
            // 1. Fetch data with STABLE calendar windows
            let calendar = Calendar.current
            let now = Date()
            let today = calendar.startOfDay(for: now)
            let baselineStart = calendar.date(byAdding: .day, value: -90, to: today)!

            let workoutDescriptor = FetchDescriptor<StoredWorkout>(
                predicate: #Predicate { $0.startDate >= baselineStart },
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
            let storedMetrics = try modelContext.fetch(metricDescriptor)
            let storedNutrition = try modelContext.fetch(nutritionDescriptor)
            let intentLabels = try modelContext.fetch(FetchDescriptor<StoredIntentLabel>())

            // Convert data
            let workouts = storedWorkouts.map { WorkoutData(from: $0) }
            let nutrition = storedNutrition.map { DailyNutrition(from: $0) }
            let hrvData = storedMetrics.filter { $0.type == "HRV" }.map { HealthDataPoint(date: $0.date, value: $0.value) }
            let rhrData = storedMetrics.filter { $0.type == "RHR" }.map { HealthDataPoint(date: $0.date, value: $0.value) }
            let sleepData = storedMetrics.filter { $0.type == "Sleep" }.map { HealthDataPoint(date: $0.date, value: $0.value) }

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
                stepData: [],
                weightData: [],
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
            let intraDay = recoveryService.calculateIntraDayReadiness(
                baselineScore: baseReadiness.score,
                todayWorkouts: workouts
            )

            // 5. ML Sub-services (moved from ReadinessViewModel per GEMINI.md)
            //    5a. Train PerformancePredictor (cache models 7 days)
            let primaryActivity = determinePrimaryActivity(from: workouts)
            let readinessService = PredictiveReadinessService()
            var mlError: String? = nil

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
                    trainedModels = try await Task.detached(priority: .utility) {
                        try await PerformancePredictor.train(
                            sleepData: capturedSleep,
                            hrvData: capturedHRV,
                            restingHRData: capturedRHR,
                            healthKitWorkouts: capturedWorkouts,
                            stravaActivities: [],
                            nutritionData: capturedNutrition,
                            readinessService: readinessService
                        )
                    }.value
                    lastMLTraining = Date()
                    print("✅ ReadinessRepository: Trained \(trainedModels.count) ML model(s)")
                } catch {
                    mlError = error.localizedDescription
                    print("❌ ReadinessRepository: ML training failed: \(error)")
                }
            }

            //    5b. Predict with uncertainty
            var mlPrediction: PerformancePredictor.Prediction? = nil
            var mlFeatureWeights: PerformancePredictor.FeatureWeights? = nil

            if !trainedModels.isEmpty {
                let acwr = readinessService.calculateReadiness(
                    stravaActivities: [],
                    healthKitWorkouts: workouts
                ).acwr
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

            // 6. Update Published State
            self.currentReadiness = UnifiedReadiness(
                score: intraDay.currentScore,
                level: mapScoreToLevel(intraDay.currentScore),
                recommendation: reconciledRecommendation,
                injuryRisk: riskAssessment,
                breakdown: baseReadiness.breakdown,
                trend: baseReadiness.trend,
                date: now,
                intraDay: intraDay,
                coachAdvice: reconciledAdvice,
                mlPrediction: mlPrediction,
                mlFeatureWeights: mlFeatureWeights,
                mlError: mlError,
                intentAwareAssessment: intentAwareAssessment
            )

            self.intraDayReadiness = intraDay
            self.lastFingerprint = fingerprint
            self.lastAnalysisDate = now

            print("✅ ReadinessRepository: Unified Analysis Complete. Score: \(baseReadiness.score)")

        } catch {
            print("❌ ReadinessRepository Error: \(error)")
        }

        isAnalyzing = false
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
}
