//
//  SupportingMetricsCard.swift
//  HealthAnalytics
//
//  Created by Claude on 2/23/26.
//

import SwiftUI

/// Supporting metrics grid that shows the key health signals influencing readiness
// MARK: - Science Badge Type

enum ScienceBadgeType {
    case science    // Mechanistic, citable formula → statusRest (#5BA8FF)
    case estimate   // ML / IntentAwareReadiness output → statusMonitoring (#F5C842)
    case none
}

// MARK: - SupportingMetricsCard

struct SupportingMetricsCard: View {
    let metrics: HealthMetrics
    @State private var showDetailedExplanation = false
    @State private var selectedConfig: MetricDisplayConfig?
    
    var body: some View {
        VStack(alignment: .leading, spacing: .spacingMd) {
            // Header with info button
            HStack {
                Text("Health Signals")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                // Info button (Readiness Explained)
                Button {
                    showDetailedExplanation = true
                } label: {
                    Image(systemName: "questionmark.circle")
                        .font(.title3)
                        .foregroundStyle(Color.accent)
                }
                .buttonStyle(.plain)
            }
            
            // Grid of metrics (2 columns, 3 rows for 6 metrics)
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                // MET Activity — science-backed (WHO 2020)
                MetricTileView(
                    title: "Activity",
                    value: "\(Int(metrics.weeklyMETMinutes)) MET-min",
                    status: metrics.metStatus,
                    icon: "figure.run",
                    badgeType: .science,
                    authorYear: CitationDatabase.citation(for: .metMinutes)?.shortCitation
                ) {
                    selectedConfig = makeConfig(signal: .metMinutes)
                }

                // Training Balance — no clean single citation (neither badge)
                MetricTileView(
                    title: "Balance",
                    value: "\(Int(metrics.strengthPercentage))% strength",
                    status: metrics.trainingBalance,
                    icon: "chart.pie",
                    badgeType: .none
                ) {
                    selectedConfig = makeConfig(signal: .trainingBalance)
                }

                // HRV — science-backed (Kiviniemi 2007)
                MetricTileView(
                    title: "HRV",
                    value: "\(Int(metrics.currentHRV)) ms",
                    status: metrics.hrvStatus,
                    icon: "waveform.path.ecg",
                    badgeType: .science,
                    authorYear: CitationDatabase.citation(for: .hrv)?.shortCitation
                ) {
                    selectedConfig = makeConfig(signal: .hrv)
                }

                // Load (ACWR) — science-backed (Gabbett 2016)
                MetricTileView(
                    title: "Load",
                    value: String(format: "%.2f", metrics.acwr),
                    status: metrics.loadStatus,
                    icon: "chart.line.uptrend.xyaxis",
                    badgeType: .science,
                    authorYear: CitationDatabase.citation(for: .acwr)?.shortCitation
                ) {
                    selectedConfig = makeConfig(signal: .acwr)
                }

                // Sleep — science-backed (Simpson 2017)
                MetricTileView(
                    title: "Sleep",
                    value: String(format: "%.1fh", metrics.averageSleep),
                    status: metrics.sleepStatus,
                    icon: "moon.zzz",
                    badgeType: .science,
                    authorYear: CitationDatabase.citation(for: .sleep)?.shortCitation
                ) {
                    selectedConfig = makeConfig(signal: .sleep)
                }

                // Readiness — composite ML estimate
                MetricTileView(
                    title: "Readiness",
                    value: "\(metrics.readinessScore)",
                    status: metrics.readinessStatus,
                    icon: "heart.fill",
                    badgeType: .estimate
                ) {
                    selectedConfig = makeConfig(signal: .biologicalAge)
                }
            }
            
            Divider()
                .padding(.vertical, .spacingSm)
            
            // Overall Score Section
            HStack(alignment: .top, spacing: .spacingMd) {
                // Score circle
                ZStack {
                    Circle()
                        .stroke(Color.textTertiary.opacity(0.2), lineWidth: 10)
                        .frame(width: 70, height: 70)
                    
                    Circle()
                        .trim(from: 0, to: Double(overallScore) / 100)
                        .stroke(overallColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .frame(width: 70, height: 70)
                        .rotationEffect(.degrees(-90))
                    
                    Text("\(overallScore)")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(overallColor)
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("Overall Health Score")
                        .font(.headline)
                    
                    Text(overallStatus)
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)

                    Text("A weighted average across all 6 metrics")
                        .font(.caption2)
                        .foregroundStyle(Color.textTertiary)
                        .padding(.top, 2)
                }
                
                Spacer()
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: .radiusMd, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.05), radius: 10, y: 5)
        )
        .sheet(isPresented: $showDetailedExplanation) {
            DetailedReadinessExplanationView()
        }
        .sheet(item: $selectedConfig) { config in
            MetricConditionDetailView(config: config)
        }
    }
    
    // MARK: - Overall Score Calculation
    
    private var overallScore: Int {
        let statuses = [
            metrics.metStatus,
            metrics.trainingBalance,
            metrics.hrvStatus,
            metrics.loadStatus,
            metrics.sleepStatus,
            metrics.readinessStatus
        ]
        
        let sum = statuses.reduce(0) { $0 + statusValue($1) }
        return sum / statuses.count
    }
    
    private func statusValue(_ status: MetricStatus) -> Int {
        switch status {
        case .excellent: return 90
        case .good: return 75
        case .moderate: return 60
        case .needsAttention: return 40
        }
    }
    
    private var overallColor: Color {
        switch overallScore {
        case 80...:    return .statusOptimal
        case 65..<80:  return .statusRest
        case 50..<65:  return .statusWarning
        default:       return .statusWarning
        }
    }
    
    private var overallStatus: String {
        switch overallScore {
        case 80...: return "Excellent - All systems ready"
        case 65..<80: return "Good - Most metrics on track"
        case 50..<65: return "Moderate - Some areas need attention"
        default: return "Needs Attention - Multiple areas to address"
        }
    }

    // MARK: - MetricDisplayConfig factory

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private func makeConfig(signal: SignalType) -> MetricDisplayConfig {
        let citation = CitationDatabase.citation(for: signal)

        switch signal {
        case .metMinutes:
            return MetricDisplayConfig(
                id: "metMinutes",
                title: "MET Activity",
                icon: "figure.run",
                currentValueFormatted: "\(Int(metrics.weeklyMETMinutes))",
                status: metrics.metStatus,
                citation: citation,
                thresholdBarValue: metrics.weeklyMETMinutes,
                conditionReasoning: metConditionReasoning,
                guidanceText: statusGuidance(metrics.metStatus),
                detailedInsight: "WHO guidelines recommend 600–1500 MET-min/week."
            )
        case .trainingBalance:
            return MetricDisplayConfig(
                id: "balance",
                title: "Training Balance",
                icon: "chart.pie.fill",
                currentValueFormatted: "\(Int(metrics.strengthPercentage))%",
                status: metrics.trainingBalance,
                citation: citation,
                thresholdBarValue: nil,
                conditionReasoning: balanceConditionReasoning,
                guidanceText: statusGuidance(metrics.trainingBalance),
                detailedInsight: nil
            )
        case .hrv:
            // Convert absolute HRV to % deviation from 30-day baseline for the bar
            let pctDeviation: Double? = {
                guard let baseline = metrics.hrvBaselineMs, baseline > 0 else { return nil }
                return (metrics.currentHRV - baseline) / baseline * 100.0
            }()
            return MetricDisplayConfig(
                id: "hrv",
                title: "Heart Rate Variability",
                icon: "waveform.path.ecg",
                currentValueFormatted: "\(Int(metrics.currentHRV))ms",
                status: metrics.hrvStatus,
                citation: citation,
                thresholdBarValue: pctDeviation,
                conditionReasoning: hrvConditionReasoning,
                guidanceText: statusGuidance(metrics.hrvStatus),
                detailedInsight: "HRV is highly sensitive to alcohol, stress, and late meals.",
                isBlendedHRVSource: UserDefaults.standard.bool(forKey: "hrvMultipleSourcesDetected")
            )
        case .acwr:
            return MetricDisplayConfig(
                id: "acwr",
                title: "Training Load (ACWR)",
                icon: "chart.line.uptrend.xyaxis",
                currentValueFormatted: String(format: "%.2f", metrics.acwr),
                status: metrics.loadStatus,
                citation: citation,
                thresholdBarValue: metrics.acwr,
                conditionReasoning: loadConditionReasoning,
                guidanceText: statusGuidance(metrics.loadStatus),
                detailedInsight: "The 'Sweet Spot' for building fitness is 0.8 – 1.3."
            )
        case .sleep:
            return MetricDisplayConfig(
                id: "sleep",
                title: "Sleep Quality",
                icon: "moon.zzz.fill",
                currentValueFormatted: String(format: "%.1fh", metrics.averageSleep),
                status: metrics.sleepStatus,
                citation: citation,
                thresholdBarValue: metrics.averageSleep,
                conditionReasoning: sleepConditionReasoning,
                guidanceText: statusGuidance(metrics.sleepStatus),
                detailedInsight: "Consistency (±30m wake time) is as important as duration."
            )
        case .biologicalAge:
            return MetricDisplayConfig(
                id: "readiness",
                title: "Readiness Score",
                icon: "heart.fill",
                currentValueFormatted: "\(metrics.readinessScore)",
                status: metrics.readinessStatus,
                citation: nil,
                thresholdBarValue: nil,
                conditionReasoning: readinessConditionReasoning,
                guidanceText: statusGuidance(metrics.readinessStatus),
                detailedInsight: nil,
                badgeType: .estimate
            )
        }
    }

    // MARK: Condition reasoning strings (kept co-located for readability)

    private var metConditionReasoning: String {
        switch metrics.metStatus {
        case .excellent, .good: return "Your weekly movement volume is within the optimal range (600–1500 MET-min), which is strongly associated with cardiovascular health and longevity."
        case .moderate: return "Your activity levels are slightly below target. Maintaining baseline movement is essential for metabolic health."
        case .needsAttention: return "Weekly MET-minutes are significantly below the WHO minimum of 600. Increasing daily walking or light activity is recommended."
        }
    }

    private var balanceConditionReasoning: String {
        switch metrics.trainingBalance {
        case .excellent, .good: return "Your training mix shows a healthy integration of both strength and endurance work. This dual-stimulus approach is ideal for longevity."
        case .moderate: return "Your training is currently leaning heavily toward one modality. Adding variety will help prevent imbalances."
        case .needsAttention: return "Missing one pillar of training (Strength or Endurance). Research shows that combining both types provides superior health outcomes."
        }
    }

    private var hrvConditionReasoning: String {
        switch metrics.hrvStatus {
        case .excellent: return "Your HRV is currently in its optimal range (within ±5% of your baseline), indicating your autonomic nervous system is well-recovered."
        case .good: return "Your HRV is stable, showing a healthy balance between training stress and recovery."
        case .moderate: return "Your HRV is slightly suppressed (5–10% below baseline). Your body is managing stress, but recovery is slightly lagging."
        case .needsAttention: return "Your HRV is significantly suppressed (>10% below baseline). This is a strong signal of systemic fatigue or impending overreaching."
        }
    }

    private var loadConditionReasoning: String {
        switch metrics.loadStatus {
        case .excellent, .good: return "Your Acute-to-Chronic Workload Ratio is in the 'Sweet Spot' (0.8–1.3). You are building fitness at a safe and sustainable rate."
        case .moderate: return "Your training load is currently low (ACWR < 0.8), suggesting you are in a recovery phase or detraining."
        case .needsAttention: return "Warning: Your training load has spiked (ACWR > 1.3). This rapid increase in volume or intensity significantly raises your risk of injury."
        }
    }

    private var sleepConditionReasoning: String {
        switch metrics.sleepStatus {
        case .excellent: return "Your sleep duration is exceptional (8h+). This provides the maximum possible window for hormonal recovery and tissue repair."
        case .good: return "You are averaging over 7 hours of sleep, which meets the baseline requirement for athletic recovery and cognitive function."
        case .moderate: return "Sleep is slightly below optimal (6.5–7h). You may notice slight decreases in cognitive focus and physical recovery speed."
        case .needsAttention: return "Critically low sleep (under 6h). Sleep deprivation impairs your immune system, raises cortisol, and severely hinders recovery from training."
        }
    }

    private var readinessConditionReasoning: String {
        switch metrics.readinessStatus {
        case .excellent: return "All systems are green. Your biometrics and training load are perfectly aligned for peak performance."
        case .good: return "Your overall readiness is strong. You have the capacity for quality training efforts today."
        case .moderate: return "Readiness is tempered. Some metrics suggest you are still adapting to recent stress or training load."
        case .needsAttention: return "Your body is signaling a need for rest. Multiple recovery markers are suppressed, and the risk of injury or illness is elevated."
        }
    }

    private func statusGuidance(_ status: MetricStatus) -> String {
        switch status {
        case .excellent: return "You are in an ideal state. Capitalize on this window for your most challenging training sessions or competitive efforts."
        case .good: return "Proceed with your planned training. You are well-positioned to handle moderate to high-intensity work."
        case .moderate: return "Listen closely to your body. Consider sticking to Zone 2 endurance work and prioritizing an extra hour of sleep tonight."
        case .needsAttention: return "Caution advised. We recommend a complete rest day or active recovery (Zone 1) only. Focus on nutrition and stress management."
        }
    }
}

// MARK: - Metric Tile View

private struct MetricTileView: View {
    let title: String
    let value: String
    let status: MetricStatus
    let icon: String
    var badgeType: ScienceBadgeType = .none
    /// Inline author attribution for science-badged tiles. E.g. "Gabbett '16".
    var authorYear: String? = nil
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: .spacingSm) {
                // Icon with status color
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(status.color)
                    .frame(height: 28)

                // Science / Estimate badge (Phase 1)
                if badgeType != .none {
                    let badgeColor: Color = badgeType == .science ? .statusRest : .statusMonitoring
                    VStack(spacing: 2) {
                        Text(badgeType == .science ? "SCIENCE" : "ESTIMATE")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(badgeColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(badgeColor.opacity(0.15))
                            .clipShape(Capsule())
                        if let authorYear {
                            Text(authorYear)
                                .font(.system(size: 8))
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                        .accessibilityLabel(badgeType == .science ? "Science-backed metric" : "ML predictive estimate")
                }

                // Title
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.textSecondary)

                // Value
                Text(value)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(Color.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, .spacingMd)
            .padding(.horizontal, .spacingSm)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(status.color.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(status.color.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MetricConditionDetailView was extracted to Views/MetricConditionDetailView.swift (Phase 1)
// MARK: - Detailed Explanation View

private struct DetailedReadinessExplanationView: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // Introduction
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Your readiness score combines five validated health signals — each grounded in peer-reviewed sport science.")
                            .font(.body)
                            .foregroundStyle(Color.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("Tap any signal tile on the dashboard for its full research basis, thresholds, and coaching guidance.")
                            .font(.subheadline)
                            .foregroundStyle(Color.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.surface))
                    .padding(.horizontal)

                    // Score breakdown
                    VStack(alignment: .leading, spacing: .spacingSm) {
                        HStack {
                            Image(systemName: "chart.bar.fill").font(.caption)
                            Text("SCORE CALCULATION")
                                .font(.caption).fontWeight(.bold)
                        }
                        .foregroundStyle(Color.accent)

                        VStack(alignment: .leading, spacing: 6) {
                            ScoreComponentRow(label: "Recovery", points: "40 pts", description: "HRV + sleep")
                            ScoreComponentRow(label: "Fitness", points: "30 pts", description: "Training consistency")
                            ScoreComponentRow(label: "Fatigue", points: "30 pts", description: "Load (ACWR) + balance")
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.surface))
                    .padding(.horizontal)

                    // Data timeframes
                    VStack(alignment: .leading, spacing: .spacingSm) {
                        HStack {
                            Image(systemName: "calendar").font(.caption)
                            Text("DATA WINDOWS")
                                .font(.caption).fontWeight(.bold)
                        }
                        .foregroundStyle(Color.accent)

                        VStack(alignment: .leading, spacing: 6) {
                            TimeframeRow(label: "Activity, HRV, Sleep", timeframe: "7 days", description: "Short-term patterns")
                            TimeframeRow(label: "Training Balance", timeframe: "14 days", description: "Workout mix")
                            TimeframeRow(label: "Chronic Load", timeframe: "28 days", description: "Long-term volume")
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.surface))
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .navigationTitle("Readiness Explained")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Helper Views

private struct ScoreComponentRow: View {
    let label: String
    let points: String
    let description: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.textPrimary)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer()
            Text(points)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(Color.accent)
        }
        .padding(.vertical, 2)
    }
}

private struct TimeframeRow: View {
    let label: String
    let timeframe: String
    let description: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.textPrimary)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer()
            Text(timeframe)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(Color.statusMonitoring)
        }
        .padding(.vertical, 2)
    }
}


