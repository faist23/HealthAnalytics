//
//  IntentAwareReadinessTestView.swift
//  HealthAnalytics
//
//  Standalone view to test intent-aware readiness
//  Uses mock sleep/HRV data since HealthDataPoint is not a SwiftData model
//

import SwiftUI
import SwiftData

struct IntentAwareReadinessTestView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var workouts: [StoredWorkout]
    @Query private var intentLabels: [StoredIntentLabel]
    
    @State private var assessment: IntentAwareReadinessService.EnhancedReadinessAssessment?
    @State private var isLoading = false
    @State private var sleepData: [HealthDataPoint] = []
    @State private var hrvData: [HealthDataPoint] = []

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                
                // Status Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Intent-Aware Readiness")
                            .font(.title2)
                            .fontWeight(.bold)
                        Text("\(intentLabels.count) labeled workouts")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Button(action: calculate) {
                        Label("Calculate", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isLoading || intentLabels.isEmpty)
                }
                .padding()
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                
                // No Labels State
                if intentLabels.isEmpty {
                    ContentUnavailableView(
                        "No Labeled Workouts",
                        systemImage: "tag.slash",
                        description: Text("Use the Activity Intent Labeler to label some workouts first, then come back here.")
                    )
                }
                
                // Loading State
                if isLoading {
                    ProgressView("Calculating readiness...")
                        .padding()
                }
                
                // Assessment Display
                if let assessment = assessment {
                    EnhancedIntentReadinessCard(assessment: assessment)
                    
                    // Debug Info
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Debug Info")
                            .font(.headline)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            DebugRow(label: "ACWR", value: String(format: "%.2f", assessment.acwr))
                            DebugRow(label: "Chronic Load", value: String(format: "%.0f", assessment.chronicLoad))
                            DebugRow(label: "Acute Load", value: String(format: "%.0f", assessment.acuteLoad))
                            DebugRow(label: "Trend", value: String(describing: assessment.trend))
                            DebugRow(label: "Workouts", value: "\(workouts.count)")
                            DebugRow(label: "Labels", value: "\(intentLabels.count)")
                            DebugRow(label: "Sleep Points", value: "\(sleepData.count)")
                            DebugRow(label: "HRV Points", value: "\(hrvData.count)")
                        }
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    
                    // All Intent Readiness Levels
                    VStack(alignment: .leading, spacing: 12) {
                        Text("All Intent Levels")
                            .font(.headline)
                        
                        ForEach(ActivityIntent.allCases, id: \.self) { intent in
                            if let readiness = assessment.performanceReadiness[intent] {
                                HStack {
                                    Text(intent.emoji)
                                    Text(intent.rawValue)
                                        .font(.subheadline)
                                    Spacer()
                                    Text(readiness.emoji)
                                    Text(String(describing: readiness))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                
            }
            .padding()
        }
        .navigationTitle("Intent Readiness Test")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // Fetch HealthKit data on appear
            await fetchHealthKitData()
            
            if assessment == nil && !intentLabels.isEmpty {
                calculate()
            }
        }
    }
    
    private func fetchHealthKitData() async {
        // Fetch sleep and HRV from SwiftData using StoredHealthMetric
        let sleepDescriptor = FetchDescriptor<StoredHealthMetric>(
            predicate: #Predicate { $0.type == "Sleep" },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        
        let hrvDescriptor = FetchDescriptor<StoredHealthMetric>(
            predicate: #Predicate { $0.type == "HRV" },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        
        do {
            let sleepMetrics = try modelContext.fetch(sleepDescriptor)
            let hrvMetrics = try modelContext.fetch(hrvDescriptor)
            
            // Convert StoredHealthMetric to HealthDataPoint
            sleepData = sleepMetrics.prefix(30).map { metric in
                HealthDataPoint(date: metric.date, value: metric.value)
            }
            
            hrvData = hrvMetrics.prefix(30).map { metric in
                HealthDataPoint(date: metric.date, value: metric.value)
            }
            
            print("📊 Fetched health data: Sleep=\(sleepData.count), HRV=\(hrvData.count)")
            
        } catch {
            print("❌ Failed to fetch health data: \(error)")
        }
    }
    
    private func calculate() {
        isLoading = true
        
        Task {
            let service = IntentAwareReadinessService()
            let result = service.calculateEnhancedReadiness(
                workouts: Array(workouts),
                labels: Array(intentLabels),
                sleep: sleepData,
                hrv: hrvData
            )
            
            await MainActor.run {
                assessment = result
                isLoading = false
            }
        }
    }
}

struct DebugRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
        }
    }
}

#Preview {
    NavigationStack {
        IntentAwareReadinessTestView()
            .modelContainer(for: [StoredWorkout.self, StoredIntentLabel.self])
    }
}
