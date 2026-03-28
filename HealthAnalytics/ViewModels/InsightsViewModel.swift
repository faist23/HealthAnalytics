//
//  InsightsViewModel.swift
//  HealthAnalytics
//
//  Thin coordinator. All analysis runs in ReadinessRepository per GEMINI.md mandate.
//  @Published properties are assigned from ReadinessRepository.currentReadiness after
//  refreshIfNecessary() completes — InsightsView does not need to change.
//

import Foundation
import SwiftUI
import SwiftData
import Combine

@MainActor
class InsightsViewModel: ObservableObject {

    // MARK: - Published Properties (assigned from ReadinessRepository.currentReadiness)

    @Published var sleepPerformanceInsight: CorrelationEngine.SleepPerformanceInsight?
    @Published var activityTypeInsights: [CorrelationEngine.ActivityTypeInsight] = []
    @Published var dataSummary: [(activityType: String, goodSleep: Int, poorSleep: Int)] = []
    @Published var simpleInsights: [CorrelationEngine.SimpleInsight] = []
    @Published var recoveryInsights: [CorrelationEngine.RecoveryInsight] = []
    @Published var hrvPerformanceInsights: [CorrelationEngine.HRVPerformanceInsight] = []
    @Published var trainingLoadSummary: TrainingLoadCalculator.TrainingLoadSummary?
    @Published var metricTrends: [MetricTrend] = []
    @Published var recommendations: [ActionableRecommendations.Recommendation] = []
    @Published var readinessAssessment: PredictiveReadinessService.ReadinessAssessment?
    @Published var acwrTrend: [ACWRDataPoint] = []
    @Published var proteinRecoveryInsight: NutritionCorrelationEngine.ProteinRecoveryInsight?
    @Published var proteinPerformanceInsights: [NutritionCorrelationEngine.ProteinPerformanceInsight] = []
    @Published var agingAssessment: BiologicalAgingService.AgingAssessment?
    @Published var carbPerformanceInsights: [NutritionCorrelationEngine.CarbPerformanceInsight] = []
    @Published var loadVisualization: TrainingLoadVisualizationService.LoadVisualizationData?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var primaryActivity: String = "Ride"

    // MARK: - SwiftData handle

    var modelContainer: ModelContainer?

    func configure(container: ModelContainer) {
        self.modelContainer = container
    }

    // MARK: - Main Analysis (delegates to ReadinessRepository)

    func analyzeData() async {
        guard let container = modelContainer else {
            errorMessage = "Database not configured"
            return
        }

        isLoading = true
        errorMessage = nil

        await ReadinessRepository.shared.refreshIfNecessary(modelContext: container.mainContext)

        if let r = ReadinessRepository.shared.currentReadiness {
            sleepPerformanceInsight     = r.sleepPerformanceInsight
            activityTypeInsights        = r.activityTypeInsights
            dataSummary                 = r.dataSummary
            simpleInsights              = r.simpleInsights
            hrvPerformanceInsights      = r.hrvPerformanceInsights
            trainingLoadSummary         = r.trainingLoadSummary
            metricTrends                = r.metricTrends
            recommendations             = r.recommendations
            readinessAssessment         = r.readinessAssessment
            acwrTrend                   = r.acwrTrend
            proteinRecoveryInsight      = r.proteinRecoveryInsight
            proteinPerformanceInsights  = r.proteinPerformanceInsights
            carbPerformanceInsights     = r.carbPerformanceInsights
            agingAssessment             = r.agingAssessment
            loadVisualization           = r.loadVisualization
            primaryActivity             = r.primaryActivity
        } else {
            errorMessage = ReadinessRepository.shared.analysisError ?? "Analysis failed"
        }

        isLoading = false
    }
}
