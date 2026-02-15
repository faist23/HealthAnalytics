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
    @State private var showInjuryRiskInfo = false

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
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("DataSyncCompleted"))) { _ in
            // Refresh when new data is synced
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
                    
                    // Injury Risk Assessment
                    if let injuryRisk = viewModel.injuryRiskAssessment {
                        InjuryRiskCard(assessment: injuryRisk)
                            .cardStyle(for: .recovery)
                    }
                    
                    // Training Zone Analysis
                    if let zoneAnalysis = viewModel.zoneAnalysis {
                        TrainingZoneCard(analysis: zoneAnalysis)
                            .cardStyle(for: .recovery)
                    }
                    
                    // Fitness Trend Analysis
                    if let fitnessAnalysis = viewModel.fitnessAnalysis {
                        FitnessTrendCard(analysis: fitnessAnalysis)
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

// MARK: - Injury Risk Card

struct InjuryRiskCard: View {
    let assessment: InjuryRiskCalculator.InjuryRiskAssessment
    @State private var showDetails = false
    @State private var showInfo = false
    
    var riskColor: Color {
        switch assessment.riskLevel {
        case .low: return .green
        case .moderate: return .yellow
        case .high: return .orange
        case .veryHigh: return .red
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                HStack(spacing: 4) {
                    Text("INJURY RISK")
                        .font(.headline)
                    
                    Button {
                        showInfo = true
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
                
                Spacer()
                
                HStack(spacing: 6) {
                    Text(assessment.riskLevel.emoji)
                        .font(.title3)
                    
                    Text(assessment.riskLevel.label)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(riskColor)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(riskColor.opacity(0.15))
                .clipShape(Capsule())
            }
            
            // Risk Score Circle
            HStack(spacing: 20) {
                ZStack {
                    Circle()
                        .stroke(riskColor.opacity(0.2), lineWidth: 12)
                        .frame(width: 80, height: 80)
                    
                    Circle()
                        .trim(from: 0, to: CGFloat(assessment.score) / 100.0)
                        .stroke(
                            riskColor,
                            style: StrokeStyle(lineWidth: 12, lineCap: .round)
                        )
                        .frame(width: 80, height: 80)
                        .rotationEffect(.degrees(-90))
                        .animation(.spring(duration: 1.0), value: assessment.score)
                    
                    Text("\(assessment.score)")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(riskColor)
                }
                
                // Breakdown
                VStack(alignment: .leading, spacing: 8) {
                    RiskBreakdownRow(
                        label: "Load",
                        score: assessment.loadRisk,
                        maxScore: 40,
                        color: riskColor
                    )
                    RiskBreakdownRow(
                        label: "Recovery",
                        score: assessment.recoveryRisk,
                        maxScore: 30,
                        color: riskColor
                    )
                    RiskBreakdownRow(
                        label: "Trends",
                        score: assessment.trendRisk,
                        maxScore: 20,
                        color: riskColor
                    )
                    RiskBreakdownRow(
                        label: "Monotony",
                        score: assessment.monotonyRisk,
                        maxScore: 10,
                        color: riskColor
                    )
                }
            }
            
            Divider()
            
            // Recommendation
            VStack(alignment: .leading, spacing: 8) {
                Label("Recommendation", systemImage: "lightbulb.fill")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.orange)
                
                Text(assessment.recommendation)
                    .font(.body)
                    .foregroundStyle(.primary)
            }
            
            // Contributing Factors (collapsible)
            if !assessment.contributingFactors.isEmpty {
                Button {
                    withAnimation {
                        showDetails.toggle()
                    }
                } label: {
                    HStack {
                        Label(
                            "\(assessment.contributingFactors.count) Risk Factor\(assessment.contributingFactors.count == 1 ? "" : "s")",
                            systemImage: showDetails ? "chevron.up" : "chevron.down"
                        )
                        .font(.subheadline)
                        .fontWeight(.medium)
                        
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                
                if showDetails {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(assessment.contributingFactors) { factor in
                            HStack(alignment: .top, spacing: 8) {
                                // Severity indicator
                                Circle()
                                    .fill(severityColor(factor.severity))
                                    .frame(width: 8, height: 8)
                                    .padding(.top, 6)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(factor.description)
                                        .font(.caption)
                                        .foregroundStyle(.primary)
                                    
                                    Text(categoryLabel(factor.category))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                
                                Spacer()
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .padding(.top, 8)
                }
            }
        }
        .padding(20)
        .sheet(isPresented: $showInfo) {
            InjuryRiskInfoSheet()
        }
    }
    
    private func severityColor(_ severity: Int) -> Color {
        if severity >= 8 { return .red }
        if severity >= 6 { return .orange }
        if severity >= 4 { return .yellow }
        return .blue
    }
    
    private func categoryLabel(_ category: InjuryRiskCalculator.RiskFactor.Category) -> String {
        switch category {
        case .load: return "Training Load"
        case .recovery: return "Recovery Status"
        case .trend: return "Metric Trends"
        case .monotony: return "Training Variety"
        }
    }
}

struct RiskBreakdownRow: View {
    let label: String
    let score: Int
    let maxScore: Int
    let color: Color
    
    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 65, alignment: .leading)
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color.opacity(0.2))
                        .frame(height: 6)
                    
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color)
                        .frame(
                            width: geometry.size.width * CGFloat(score) / CGFloat(maxScore),
                            height: 6
                        )
                }
            }
            .frame(height: 6)
            
            Text("\(score)")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(color)
                .frame(width: 20, alignment: .trailing)
        }
    }
}

// MARK: - Injury Risk Info Sheet

struct InjuryRiskInfoSheet: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("What is Injury Risk?")) {
                    Text("This multi-factor model analyzes your training load patterns, recovery status, and biometric trends to predict injury risk. It's based on the latest sports science research for endurance athletes.")
                }
                
                Section(header: Text("Risk Score Components")) {
                    VStack(alignment: .leading, spacing: 12) {
                        ComponentRow(
                            label: "Training Load (40 pts)",
                            description: "EWMA ratio, monotony, strain, and weekly spikes",
                            icon: "figure.run",
                            color: .blue
                        )
                        
                        ComponentRow(
                            label: "Recovery Status (30 pts)",
                            description: "HRV, resting heart rate, and sleep quality",
                            icon: "heart.fill",
                            color: .red
                        )
                        
                        ComponentRow(
                            label: "Metric Trends (20 pts)",
                            description: "Multi-day trends in key biomarkers",
                            icon: "chart.line.uptrend.xyaxis",
                            color: .green
                        )
                        
                        ComponentRow(
                            label: "Training Monotony (10 pts)",
                            description: "Lack of variety increases injury risk",
                            icon: "repeat",
                            color: .orange
                        )
                    }
                    .font(.subheadline)
                }
                
                Section(header: Text("Understanding Risk Levels")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Low (0-24): Maintain current training balance", systemImage: "checkmark.shield.fill")
                            .foregroundColor(.green)
                        
                        Label("Moderate (25-44): Monitor recovery closely", systemImage: "exclamationmark.shield.fill")
                            .foregroundColor(.yellow)
                        
                        Label("High (45-64): Reduce volume/intensity 20-30%", systemImage: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        
                        Label("Very High (65+): Take 1-2 complete rest days", systemImage: "xmark.shield.fill")
                            .foregroundColor(.red)
                    }
                    .font(.subheadline)
                    .padding(.vertical, 8)
                }
                
                Section(header: Text("Key Metrics")) {
                    VStack(alignment: .leading, spacing: 12) {
                        MetricExplanation(
                            title: "EWMA Ratio",
                            description: "Exponentially weighted moving average of acute (7d) vs chronic (42d) load. More responsive than simple averages.",
                            optimal: "0.8 - 1.3"
                        )
                        
                        Divider()
                        
                        MetricExplanation(
                            title: "Monotony",
                            description: "Training variety score. High monotony (>2.0) means you're doing the same thing every day.",
                            optimal: "< 2.0"
                        )
                        
                        Divider()
                        
                        MetricExplanation(
                            title: "Strain",
                            description: "Load × Monotony. High strain (>1500) indicates cumulative fatigue.",
                            optimal: "< 1000"
                        )
                        
                        Divider()
                        
                        MetricExplanation(
                            title: "Weekly Load Change",
                            description: "Week-over-week load increase. Rapid spikes (>20%) raise injury risk.",
                            optimal: "< 10%"
                        )
                    }
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Research-Backed")
                            .font(.headline)
                        
                        Text("This model incorporates findings from over 20 peer-reviewed studies on endurance athlete injury prevention, including work from Australian Institute of Sport and British Journal of Sports Medicine.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Injury Risk Model")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("Done") { dismiss() }
            }
        }
        .presentationDetents([.large])
    }
}

struct ComponentRow: View {
    let label: String
    let description: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .fontWeight(.semibold)
                
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct MetricExplanation: View {
    let title: String
    let description: String
    let optimal: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Text("Optimal: \(optimal)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.green.opacity(0.15))
                    .clipShape(Capsule())
            }
            
            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}


#Preview {
    NavigationStack {
        ReadinessView()
            .modelContainer(for: [StoredWorkout.self, StoredHealthMetric.self, StoredNutrition.self, StoredIntentLabel.self])
    }
}
