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
            
            let storedWorkouts = try modelContext.fetch(workoutDescriptor)
            let storedMetrics = try modelContext.fetch(metricDescriptor)
            
            // Convert data
            let workouts = storedWorkouts.map { WorkoutData(from: $0) }
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
            
            let trendDetector = TrendDetector()
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
                recoveryStatus: [], // Will be refined in future to pass insights
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
            
            // 5. Update Published State
            self.currentReadiness = UnifiedReadiness(
                score: intraDay.currentScore, // Use the dynamic score
                level: mapScoreToLevel(intraDay.currentScore),
                recommendation: reconciledRecommendation,
                injuryRisk: riskAssessment,
                breakdown: baseReadiness.breakdown,
                trend: baseReadiness.trend,
                date: now,
                intraDay: intraDay,
                coachAdvice: reconciledAdvice
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
        let sleepCount = try context.fetchCount(FetchDescriptor<StoredHealthMetric>(predicate: #Predicate { $0.type == "Sleep" }))
        let hrvCount = try context.fetchCount(FetchDescriptor<StoredHealthMetric>(predicate: #Predicate { $0.type == "HRV" }))
        let rhrCount = try context.fetchCount(FetchDescriptor<StoredHealthMetric>(predicate: #Predicate { $0.type == "RHR" }))
        
        return PredictionCache.DataFingerprint(
            workoutCount: workoutCount,
            sleepCount: sleepCount,
            hrvCount: hrvCount,
            rhrCount: rhrCount
        )
    }
    
    private func mapScoreToLevel(_ score: Int) -> ReadinessLevel {
        if score >= 80 { return .excellent }
        if score >= 70 { return .good }
        if score >= 60 { return .moderate }
        return .poor
    }
}
