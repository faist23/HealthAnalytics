//
//  ReadinessView.swift
//  HealthAnalytics
//
//  Properly integrated with SwiftData and intent-aware readiness
//

import SwiftUI
import SwiftData
import Charts

struct ReadinessView: View {
    @StateObject private var viewModel = ReadinessViewModel()
    @State private var isFirstLoad = true
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.modelContext) private var modelContext
    @ObservedObject var syncManager = SyncManager.shared
    @Query private var intentLabels: [StoredIntentLabel]

    var body: some View {
        ZStack {
            TabBackgroundColor.recovery(for: colorScheme)
                .ignoresSafeArea()
            
            Group {
                if syncManager.isBackfillingHistory {
                    BackfillProgressView(
                        progress: syncManager.backfillProgress,
                        message: syncManager.syncProgress
                    )
                } else {
                    readinessContent
                }
            }
        }
        .navigationTitle("Readiness")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    StatisticalDashboardView()
                } label: {
                    Image(systemName: "chart.bar.doc.horizontal")
                }
            }
        }
        /*      .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                refreshButton
            }
        } */
        .task {
            // Configure on first appearance
            if viewModel.modelContainer == nil {
                viewModel.configure(container: modelContext.container)
            }
            // Always analyze when tab appears
            await viewModel.analyze(modelContext: modelContext)
            // Mark first load as complete
            isFirstLoad = false
        }
        .onChange(of: modelContext) { _, _ in
            if viewModel.modelContainer == nil {
                viewModel.configure(container: modelContext.container)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("DataWindowChanged"))) { _ in
            // Force recalculation when data window changes
            Task {
                await viewModel.analyze(modelContext: modelContext)
            }
        }
    }
    
    // MARK: - Subviews
    
    private var readinessContent: some View {
        ZStack {
            ScrollView {
                VStack(spacing: 24) {
                    
                    if let error = viewModel.errorMessage {
                        ErrorView(message: error)
                            .cardStyle(for: .error)
                    }
                
                // Don't show content if loading OR first load - loading overlay will appear
                if !viewModel.isLoading && !isFirstLoad {
                    // HRV-Guided Daily Recommendation (HERO)
                    if let recommendation = viewModel.dailyRecommendation {
                        DailyRecommendationCard(recommendation: recommendation)
                            .cardStyle(for: .info)
                    }
                    
                    // Legacy daily instruction (fallback)
                    if viewModel.dailyRecommendation == nil, let instruction = viewModel.dailyInstruction {
                        DailyInstructionCard(instruction: instruction)
                            .cardStyle(for: .info)
                    }
                    
                    // HERO: Readiness Score
                    if let readiness = viewModel.readinessScore {
                    ReadinessScoreHero(readiness: readiness)
                        .cardStyle(for: .recovery)
                    
                    // Form Indicator
                    if let form = viewModel.formIndicator {
                        FormIndicatorCard(form: form)
                            .cardStyle(for: .recovery)
                    }
                    
                    // Intent-Aware Readiness - Shows what you're ready for TODAY
                    if let assessment = viewModel.intentAwareAssessment {
                        EnhancedIntentReadinessCard(assessment: assessment)
                    }
                    
                    // Temporal Analysis - Multi-timescale insights
                    if let temporal = viewModel.temporalAnalysis {
                        TemporalInsightsCard(analysis: temporal)
                    }

                    // Training Load Visualization
                    if let loadViz = viewModel.loadVisualization {
                        NavigationLink {
                            TrainingLoadVisualizationView(data: loadViz)
                        } label: {
                            TrainingLoadPreviewCard(summary: loadViz.summary)
                        }
                        .buttonStyle(.plain)
                    }

                    // Score Breakdown
                    ScoreBreakdownCard(breakdown: readiness.breakdown)
                        .cardStyle(for: .recovery)
                    
                    // ML Prediction
                    if let prediction = viewModel.mlPrediction,
                       let weights = viewModel.mlFeatureWeights {
                        PredictionInsightCard(
                            prediction: prediction,
                            weights: weights
                        )
                        .cardStyle(for: .recovery)
                    } else if let mlError = viewModel.mlError {
                        PredictionUnavailableCard(reason: mlError)
                            .cardStyle(for: .error)
                    }
                    
                    // Performance Windows Section
                    if !viewModel.performanceWindows.isEmpty {
                        SectionHeader(
                            title: "Your Performance Windows",
                            subtitle: "Discovered from YOUR data"
                        )
                        
                        ForEach(Array(viewModel.performanceWindows.prefix(3).enumerated()), id: \.offset) { index, window in
                            PerformanceWindowCard(window: window)
                                .cardStyle(for: .recovery)
                        }
                    }
                    
                    // Optimal Timing Section
                    if !viewModel.optimalTimings.isEmpty {
                        SectionHeader(
                            title: "Optimal Timing",
                            subtitle: "When you perform best"
                        )
                        
                        ForEach(Array(viewModel.optimalTimings.prefix(2).enumerated()), id: \.offset) { index, timing in
                            OptimalTimingCard(timing: timing)
                                .cardStyle(for: .recovery)
                        }
                    }
                    
                    // Workout Sequences
                    if !viewModel.workoutSequences.isEmpty {
                        SectionHeader(
                            title: "Effective Sequences",
                            subtitle: "Workout combinations that work"
                        )
                        
                        ForEach(viewModel.workoutSequences.prefix(3)) { sequence in
                            WorkoutSequenceCard(sequence: sequence)
                                .cardStyle(for: .workouts)
                        }
                    }
                    
                    } else {
                        // Show empty state only when not loading and no data
                        ReadinessEmptyState()
                            .cardStyle(for: .info)
                    }
                } // End of !viewModel.isLoading check
                
                Spacer()
                }
                .padding()
            }
            .scrollContentBackground(.hidden)
            
            // Loading overlay - must be AFTER ScrollView to appear on top
            if viewModel.isLoading || isFirstLoad {
                LoadingOverlay(message: "Analyzing your readiness...")
            }
        }
    }
    
    private var refreshButton: some View {
        Button {
            Task {
                await viewModel.analyze(modelContext: modelContext)
            }
        } label: {
            Image(systemName: "arrow.clockwise")
        }
        .disabled(viewModel.isLoading)
    }
}

// MARK: - Backfill Progress View

struct BackfillProgressView: View {
    let progress: Double
    let message: String
    
    var body: some View {
        VStack(spacing: 20) {
            ProgressView(value: progress, total: 1.0)
                .progressViewStyle(.linear)
                .scaleEffect(x: 1, y: 2)
                .padding(.horizontal, 40)
            
            Text("Establishing 10-Year Baseline")
                .font(.headline)
            
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Text("\(Int(progress * 100))% complete")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding()
    }
}

// MARK: - Daily Instruction Card

struct DailyInstructionCard: View {
    let instruction: ReadinessViewModel.DailyInstruction
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(instruction.headline)
                    .font(.title2.bold())
                Spacer()
                Circle()
                    .fill(instruction.status.color)
                    .frame(width: 12, height: 12)
            }
            
            Text(instruction.subline)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            if let target = instruction.targetAction {
                HStack {
                    Image(systemName: "target")
                        .foregroundColor(instruction.status.color)
                    Text(target)
                        .font(.subheadline.weight(.semibold))
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(instruction.status.color.opacity(0.1))
                .cornerRadius(8)
            }
            
            if let insight = instruction.primaryInsight {
                Divider()
                Text(insight)
                    .font(.caption.bold())
                    .foregroundStyle(instruction.status.color)
            }
        }
        .padding()
    }
}

// MARK: - Hero Readiness Score

struct ReadinessScoreHero: View {
    let readiness: ReadinessAnalyzer.ReadinessScore
    
    var scoreColor: Color {
        if readiness.score >= 80 { return .green }
        if readiness.score >= 60 { return .blue }
        if readiness.score >= 40 { return .orange }
        return .red
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Main Score Circle
            ZStack {
                Circle()
                    .stroke(scoreColor.opacity(0.2), lineWidth: 20)
                    .frame(width: 200, height: 200)
                
                Circle()
                    .trim(from: 0, to: CGFloat(readiness.score) / 100.0)
                    .stroke(
                        scoreColor,
                        style: StrokeStyle(lineWidth: 20, lineCap: .round)
                    )
                    .frame(width: 200, height: 200)
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(duration: 1.0), value: readiness.score)
                
                VStack(spacing: 4) {
                    Text("\(readiness.score)")
                        .font(.system(size: 72, weight: .bold, design: .rounded))
                        .foregroundStyle(scoreColor)
                    
                    Text("/ 100")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top)
            
            // Trend Badge
            HStack(spacing: 8) {
                Text(readiness.trend.emoji)
                    .font(.title2)
                
                Text(trendLabel)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(trendColor)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(trendColor.opacity(0.15))
            .clipShape(Capsule())
            
            // Recommendation
            VStack(spacing: 8) {
                Text("Today's Guidance")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(1)
                
                Text(readiness.recommendation)
                    .font(.body)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
            }
            .padding()
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            
            // Confidence indicator
            HStack {
                Image(systemName: confidenceIcon)
                    .font(.caption)
                
                Text(readiness.confidence.description)
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
        }
        .padding(20)
    }
    
    private var trendLabel: String {
        switch readiness.trend {
        case .improving: return "Building Form"
        case .maintaining: return "Steady State"
        case .declining: return "Managing Fatigue"
        case .peaking: return "PEAK WINDOW"
        case .recovering: return "Recovering Well"
        }
    }
    
    private var trendColor: Color {
        switch readiness.trend {
        case .improving: return AppColors.hrv
        case .maintaining: return AppColors.sleep
        case .declining: return AppColors.steps
        case .peaking: return AppColors.workouts
        case .recovering: return AppColors.nutrition
        }
    }
    
    private var confidenceIcon: String {
        switch readiness.confidence {
        case .high: return "checkmark.circle.fill"
        case .medium: return "checkmark.circle"
        case .low: return "clock.circle"
        }
    }
}

// MARK: - Form Indicator Card

struct FormIndicatorCard: View {
    let form: ReadinessAnalyzer.FormIndicator
    
    var statusColor: Color {
        switch form.status {
        case .fresh, .primed: return AppColors.hrv
        case .functional: return AppColors.sleep
        case .fatigued: return AppColors.steps
        case .depleted: return AppColors.heartRate
        }
    }
    
    var riskColor: Color {
        switch form.riskLevel {
        case .low: return .green
        case .moderate: return .yellow
        case .high: return .orange
        case .veryHigh: return .red
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Current Form")
                    .font(.headline)
                
                Spacer()
                
                HStack(spacing: 4) {
                    Circle()
                        .fill(riskColor)
                        .frame(width: 8, height: 8)
                    
                    Text(riskLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            HStack(spacing: 12) {
                Text(form.status.emoji)
                    .font(.system(size: 48))
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(form.status.label)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(statusColor)
                    
                    Text("Day \(form.daysInStatus)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 8) {
                Label("Optimal Action Window", systemImage: "calendar.badge.clock")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Text(form.optimalActionWindow)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
    }
    
    private var riskLabel: String {
        switch form.riskLevel {
        case .low: return "Low risk"
        case .moderate: return "Moderate risk"
        case .high: return "High risk"
        case .veryHigh: return "Very high risk"
        }
    }
}

// MARK: - Score Breakdown Card

struct ScoreBreakdownCard: View {
    let breakdown: ReadinessAnalyzer.ScoreBreakdown
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Score Breakdown")
                .font(.headline)
            
            VStack(spacing: 12) {
                BreakdownRow(
                    label: "Recovery",
                    score: breakdown.recoveryScore,
                    maxScore: 40,
                    color: AppColors.hrv,
                    details: breakdown.recoveryDetails
                )
                
                BreakdownRow(
                    label: "Fitness",
                    score: breakdown.fitnessScore,
                    maxScore: 30,
                    color: AppColors.sleep,
                    details: breakdown.fitnessDetails
                )
                
                BreakdownRow(
                    label: "Fatigue Management",
                    score: breakdown.fatigueScore,
                    maxScore: 30,
                    color: AppColors.steps,
                    details: breakdown.fatigueDetails
                )
            }
        }
        .padding(20)
    }
}

struct BreakdownRow: View {
    let label: String
    let score: Int
    let maxScore: Int
    let color: Color
    let details: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
                
                Text("\(score)/\(maxScore)")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundStyle(color)
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color.opacity(0.2))
                        .frame(height: 8)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(
                            width: geometry.size.width * CGFloat(score) / CGFloat(maxScore),
                            height: 8
                        )
                }
            }
            .frame(height: 8)
            
            Text(details)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.ultraThinMaterial.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Performance Window Card

struct PerformanceWindowCard: View {
    let window: PerformancePatternAnalyzer.PerformanceWindow
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(window.activityType)
                        .font(.headline)
                    
                    Text(window.performanceMetric)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                VStack {
                    Text("\(String(format: "%+.0f", window.averageBoost))%")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(window.averageBoost > 0 ? .green : .red)
                    
                    Image(systemName: window.averageBoost > 0 ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                        .foregroundStyle(window.averageBoost > 0 ? .green : .red)
                }
            }
            
            Divider()
            
            Text(window.readableDescription)
                .font(.body)
                .foregroundStyle(.primary)
            
            HStack {
                Label("\(window.sampleSize) examples", systemImage: "chart.bar.fill")
                Spacer()
                Text(window.confidence.description)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(20)
    }
}

// MARK: - Optimal Timing Card

struct OptimalTimingCard: View {
    let timing: PerformancePatternAnalyzer.OptimalTiming
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "clock.fill")
                .font(.system(size: 32))
                .foregroundStyle(.blue)
                .frame(width: 50)
            
            VStack(alignment: .leading, spacing: 6) {
                Text(timing.activityType)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Text(timing.description)
                    .font(.body)
                    .foregroundStyle(.primary)
                
                Text("\(timing.sampleSize) workouts analyzed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding(12)
    }
}

// MARK: - Workout Sequence Card

struct WorkoutSequenceCard: View {
    let sequence: PerformancePatternAnalyzer.WorkoutSequence
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ForEach(sequence.sequence.indices, id: \.self) { index in
                    if index > 0 {
                        Image(systemName: "arrow.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Text(sequence.sequence[index])
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.blue.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
            
            HStack {
                Text(sequence.description)
                    .font(.body)
                
                Spacer()
            }
        }
        .padding(20)
    }
}

// MARK: - Section Header

struct SectionHeader: View {
    let title: String
    let subtitle: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title2)
                .fontWeight(.bold)
            
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }
}

// MARK: - Empty State

struct EmptyReadinessView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "figure.mixed.cardio")
                .font(.system(size: 64))
                .foregroundStyle(.blue)
            
            Text("Building Your Baseline")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Keep tracking your workouts, sleep, and recovery metrics. We'll analyze your patterns and provide personalized readiness insights.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Text("Minimum needed:\n• 7 days of sleep data\n• 7 days of HRV or Resting HR\n• 5+ workouts")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

// MARK: - Training Load Preview Card

struct TrainingLoadPreviewCard: View {
    let summary: TrainingLoadVisualizationService.LoadVisualizationData.LoadSummary
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Training Load")
                        .font(.title3)
                        .fontWeight(.bold)
                    
                    Text("Last 90 days")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }
            
            Divider()
            
            HStack(spacing: 20) {
                // Current ACWR
                VStack(alignment: .leading, spacing: 4) {
                    Text("ACWR")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    HStack(spacing: 4) {
                        Text(String(format: "%.2f", summary.currentACWR))
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(statusColor)
                        
                        Text(statusEmoji)
                            .font(.title3)
                    }
                }
                
                Spacer()
                
                // Current status
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Status")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Text(summary.currentStatus)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(statusColor)
                }
            }
            
            // Quick recommendation
            HStack(spacing: 8) {
                Image(systemName: "lightbulb.fill")
                    .font(.caption)
                    .foregroundStyle(.yellow)
                
                Text(summary.recommendation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(20)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    private var statusColor: Color {
        switch summary.currentStatus {
        case "Optimal": return .green
        case "Building": return .orange
        case "Overreaching": return .red
        case "Detraining": return .blue
        default: return .gray
        }
    }
    
    private var statusEmoji: String {
        switch summary.currentStatus {
        case "Optimal": return "✅"
        case "Building": return "⚠️"
        case "Overreaching": return "🚨"
        case "Detraining": return "📉"
        default: return "➖"
        }
    }
}


#Preview {
    NavigationStack {
        ReadinessView()
            .modelContainer(for: [StoredWorkout.self, StoredHealthMetric.self, StoredNutrition.self, StoredIntentLabel.self])
    }
}
