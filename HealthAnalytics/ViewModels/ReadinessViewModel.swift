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
    @Published var isLoading = false
    @Published var errorMessage: String?
    
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
                self?.isLoading = ReadinessRepository.blocksContent(
                    isAnalyzing: analyzing,
                    snapshotDate: ReadinessRepository.shared.currentReadiness?.date
                )
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

        // ML outputs — now owned by ReadinessRepository

        // Training load & zone outputs — now owned by ReadinessRepository (GEMINI.md mandate)
        self.trainingLoadSummary = unified.trainingLoadSummary
        self.readinessAssessment = unified.readinessAssessment
        self.acwrTrend = unified.acwrTrend
        self.loadVisualization = unified.loadVisualization
        self.primaryActivity = unified.primaryActivity

        // Energy-bank curve inputs — owned by ReadinessRepository (GEMINI.md mandate)
        self.overnightRecoveryMultiplier = unified.overnightRecoveryMultiplier
        self.todayStepExcessTSS = unified.todayStepExcessTSS

        // Per-tab outputs (Phase 1.2 — now owned by ReadinessRepository)
        self.todayWorkouts = unified.todayWorkouts
        self.todaySteps = unified.todaySteps
        self.cardiovascularStrain = unified.cardiovascularStrain
        self.dailyTSSData = Self.dailyTSSData(from: unified.dailyTraining)
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
    
    
    // calculateTrainingZones / calculateFitnessTrends / calculateTrainingLoad / calculateImprovedACWRTrend
    // removed — logic moved to ReadinessRepository per GEMINI.md mandate

    /// The repository's per-day TSS and hours (one load engine), with fitness/fatigue EWMAs.
    static func dailyTSSData(from days: [ReadinessRepository.DailyTraining]) -> [DailyTSSData] {
        let ctlAlpha = 2.0 / 43.0  // 42-day time constant
        let atlAlpha = 2.0 / 8.0   // 7-day time constant
        var ctl = 0.0, atl = 0.0
        return days.map { day in
            ctl = day.tss * ctlAlpha + ctl * (1 - ctlAlpha)
            atl = day.tss * atlAlpha + atl * (1 - atlAlpha)
            return DailyTSSData(date: day.date, tss: day.tss, hours: day.hours, ctl: ctl, atl: atl)
        }
    }
    
}
