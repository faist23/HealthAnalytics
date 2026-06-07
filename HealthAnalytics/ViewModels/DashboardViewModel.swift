//
//  DashboardViewModel.swift
//  HealthAnalytics
//
//  Created by Craig Faist on 1/25/26.
//

import Foundation
import HealthKit
import SwiftData
import SwiftUI
import Combine

@MainActor
class DashboardViewModel: ObservableObject {
    @Published var hrvData: [HealthDataPoint] = []
    @Published var restingHeartRateData: [HealthDataPoint] = []
    @Published var sleepData: [HealthDataPoint] = []
    @Published var stepCountData: [HealthDataPoint] = []
    @Published var workouts: [WorkoutData] = []
    @Published var weightData: [HealthDataPoint] = []
    
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedPeriod: TimePeriod = .month
    @Published var startDate = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @Published var endDate = Date()
    
    // Readiness data
    @Published var readinessScore: Int = 0
    @Published var readinessLevel: ReadinessLevel = .moderate
    @Published var readinessRecommendation: String = ""
    @Published var intraDayReadiness: RecoveryDecayService.IntraDayReadiness?

    // Holistic metrics (Phase 1.2 — now sourced from ReadinessRepository)
    @Published var holisticMetrics: HealthMetrics?

    private var cancellables = Set<AnyCancellable>()

    init() {
        setupReadinessSubscription()
    }

    private func setupReadinessSubscription() {
        ReadinessRepository.shared.$currentReadiness
            .receive(on: DispatchQueue.main)
            .sink { [weak self] unified in
                guard let self = self, let unified = unified else { return }
                self.readinessScore = unified.score
                self.readinessLevel = unified.level
                self.readinessRecommendation = unified.coachAdvice
                self.intraDayReadiness = unified.intraDay
                self.holisticMetrics = unified.holisticMetrics

                // Raw chart arrays now sourced from the repo (Phase 1.2)
                self.hrvData = unified.hrvData
                self.restingHeartRateData = unified.rhrData
                self.sleepData = unified.sleepData
                self.stepCountData = unified.stepCountData
                self.workouts = unified.workouts
                self.weightData = unified.weightData
            }
            .store(in: &cancellables)

        // Phase 3 fix: forward repo's isAnalyzing so the Coach tab's LoadingOverlay
        // appears during analysis. Without this the screen looks frozen since
        // loadData() (which set isLoading) was deleted in Phase 1.4.
        ReadinessRepository.shared.$isAnalyzing
            .receive(on: DispatchQueue.main)
            .sink { [weak self] analyzing in
                self?.isLoading = analyzing
            }
            .store(in: &cancellables)
    }
    
    // loadData() removed in Phase 1.4 — DashboardViewModel is now a pure
    // adapter that subscribes to ReadinessRepository.shared.$currentReadiness.
    // All chart arrays and holisticMetrics are populated via the subscription
    // above. No SwiftData fetching, no analyze trigger.
}
