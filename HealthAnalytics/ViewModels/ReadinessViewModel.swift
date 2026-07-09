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
    private var repositoryLoadingCancellable: AnyCancellable?

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
                    ? "Add some workouts and sleep data to see your recovery score."
                    : "Something went wrong. Pull to refresh or try again later."
            }

        // Phase 3 fix: forward repo's isAnalyzing → isLoading so the LoadingOverlay
        // appears during repo re-analysis (after sync, after pull-to-refresh).
        // Without this the screen looks frozen because nothing sets isLoading
        // since analyze() was deleted in Phase 1.4.
        repositoryLoadingCancellable = ReadinessRepository.shared.$isAnalyzing
            .receive(on: DispatchQueue.main)
            .sink { [weak self] analyzing in
                self?.isLoading = analyzing
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
