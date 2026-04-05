//
//  HolisticHealthDashboard.swift
//  HealthAnalytics
//
//  Multi-metric health view - no single "hero" metric
//  Research-based approach: Multiple factors together tell the complete story
//

import SwiftUI

struct HolisticHealthDashboard: View {
    let metrics: HealthMetrics
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("Holistic Health Overview")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text("Multiple factors combined provide a complete picture of your health and fitness")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                
                // Grid of metrics - equal visual weight
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 16),
                    GridItem(.flexible(), spacing: 16)
                ], spacing: 16) {
                    // MET Activity
                    HealthMetricTile(
                        icon: "flame.fill",
                        iconColor: metrics.metStatus.color,
                        title: "MET Activity",
                        value: String(format: "%.0f", metrics.weeklyMETMinutes),
                        unit: "min/week",
                        status: metrics.metStatus.label,
                        statusColor: metrics.metStatus.color
                    )
                    
                    // Training Balance
                    HealthMetricTile(
                        icon: "figure.mixed.cardio",
                        iconColor: metrics.trainingBalance.color,
                        title: "Training Balance",
                        value: String(format: "%.0f%%", metrics.strengthPercentage),
                        unit: "strength",
                        status: metrics.trainingBalance.label,
                        statusColor: metrics.trainingBalance.color
                    )
                    
                    // HRV Trend
                    HealthMetricTile(
                        icon: "waveform.path.ecg",
                        iconColor: metrics.hrvStatus.color,
                        title: "HRV Status",
                        value: String(format: "%.0f", metrics.currentHRV),
                        unit: "ms",
                        status: metrics.hrvStatus.label,
                        statusColor: metrics.hrvStatus.color
                    )
                    
                    // Training Load
                    HealthMetricTile(
                        icon: "gauge.with.dots.needle.bottom.50percent",
                        iconColor: metrics.loadStatus.color,
                        title: "Training Load",
                        value: String(format: "%.2f", metrics.acwr),
                        unit: "ACWR",
                        status: metrics.loadStatus.label,
                        statusColor: metrics.loadStatus.color
                    )
                    
                    // Sleep Quality
                    HealthMetricTile(
                        icon: "bed.double.fill",
                        iconColor: metrics.sleepStatus.color,
                        title: "Sleep",
                        value: String(format: "%.1f", metrics.averageSleep),
                        unit: "hours",
                        status: metrics.sleepStatus.label,
                        statusColor: metrics.sleepStatus.color
                    )
                    
                    // Readiness
                    HealthMetricTile(
                        icon: "heart.fill",
                        iconColor: metrics.readinessStatus.color,
                        title: "Readiness",
                        value: "\(metrics.readinessScore)",
                        unit: "/100",
                        status: metrics.readinessStatus.label,
                        statusColor: metrics.readinessStatus.color
                    )
                }
                .padding(.horizontal)
                
                // Research context
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "book.fill")
                            .foregroundStyle(Color.accent)
                        Text("Evidence-Based Approach")
                            .font(.headline)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        ResearchBullet(
                            text: "MET-based activity shows 14-15% mortality reduction per MET increase (750,000+ participants)"
                        )
                        
                        ResearchBullet(
                            text: "Combining cardiorespiratory fitness AND strength reduces mortality more than either alone"
                        )
                        
                        ResearchBullet(
                            text: "HRV is a validated real-time marker of recovery and adaptation"
                        )
                        
                        ResearchBullet(
                            text: "ACWR (Acute:Chronic Workload Ratio) is a proven injury risk predictor"
                        )
                        
                        ResearchBullet(
                            text: "Sleep quality directly impacts performance, recovery, and health outcomes"
                        )
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: .radiusMd)
                        .fill(Color.accent.opacity(0.1))
                )
                .padding(.horizontal)

                // Key insight
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "lightbulb.fill")
                            .foregroundStyle(Color.statusMonitoring)
                        Text("No Single Metric Tells the Whole Story")
                            .font(.headline)
                    }
                    
                    Text("This dashboard shows multiple validated health markers with equal emphasis. Unlike apps that fixate on a single metric (like VO2 max), this approach provides a more complete and accurate picture of your fitness, recovery, and health status.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: .radiusMd)
                        .fill(Color.statusMonitoring.opacity(0.1))
                )
                .padding(.horizontal)

                // Overall status summary
                OverallStatusView(metrics: metrics)
                    .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .navigationTitle("Holistic Health")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Health Metric Tile

struct HealthMetricTile: View {
    let icon: String
    let iconColor: Color
    let title: String
    let value: String
    let unit: String
    let status: String
    let statusColor: Color
    
    var body: some View {
        VStack(spacing: 12) {
            // Icon
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(iconColor)
                .frame(height: 30)
            
            // Title
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            // Value
            VStack(spacing: 2) {
                Text(value)
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundStyle(iconColor)
                
                Text(unit)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            // Status badge
            Text(status)
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(statusColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(statusColor.opacity(0.15))
                )
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(uiColor: .systemBackground))
                .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 3)
        )
    }
}

// MARK: - Research Bullet

struct ResearchBullet: View {
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(Color.statusOptimal)
                .font(.caption)
            
            Text(text)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Overall Status View

struct OverallStatusView: View {
    let metrics: HealthMetrics
    
    private var overallScore: Int {
        // Calculate weighted overall score
        let metScore = metricsScore(for: metrics.metStatus)
        let balanceScore = metricsScore(for: metrics.trainingBalance)
        let hrvScore = metricsScore(for: metrics.hrvStatus)
        let loadScore = metricsScore(for: metrics.loadStatus)
        let sleepScore = metricsScore(for: metrics.sleepStatus)
        
        return (metScore + balanceScore + hrvScore + loadScore + sleepScore) / 5
    }
    
    private func metricsScore(for status: MetricStatus) -> Int {
        switch status {
        case .excellent: return 90
        case .good: return 75
        case .moderate: return 60
        case .needsAttention: return 40
        }
    }
    
    private var overallStatus: String {
        if overallScore >= 80 {
            return "Excellent overall health across multiple factors"
        } else if overallScore >= 65 {
            return "Good overall health with room for optimization"
        } else if overallScore >= 50 {
            return "Moderate health status - focus on weak points"
        } else {
            return "Several metrics need attention - prioritize recovery"
        }
    }
    
    private var overallColor: Color {
        if overallScore >= 80 {
            return .green
        } else if overallScore >= 65 {
            return .blue
        } else if overallScore >= 50 {
            return .yellow
        } else {
            return .orange
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "chart.bar.doc.horizontal.fill")
                    .foregroundStyle(overallColor)
                Text("Overall Assessment")
                    .font(.headline)
            }
            
            // Score ring
            HStack(spacing: 20) {
                ZStack {
                    Circle()
                        .stroke(Color.textTertiary.opacity(0.2), lineWidth: 12)
                        .frame(width: 80, height: 80)
                    
                    Circle()
                        .trim(from: 0, to: Double(overallScore) / 100)
                        .stroke(overallColor, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .frame(width: 80, height: 80)
                        .rotationEffect(.degrees(-90))
                    
                    Text("\(overallScore)")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundStyle(overallColor)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text(overallStatus)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    Text("Based on \(metrics.metricsCount) validated health markers")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: .radiusMd)
                .fill(overallColor.opacity(0.1))
        )
    }
}

// MARK: - Supporting Models

struct HealthMetrics {
    // MET Activity
    let weeklyMETMinutes: Double
    let metStatus: MetricStatus

    // Training Balance
    let strengthPercentage: Double
    let trainingBalance: MetricStatus

    // HRV
    let currentHRV: Double
    let hrvStatus: MetricStatus
    /// Personal 30-day HRV baseline (ms). Used by ResearchThresholdBar to show % deviation.
    let hrvBaselineMs: Double?

    // Training Load
    let acwr: Double
    let loadStatus: MetricStatus

    // Sleep
    let averageSleep: Double
    let sleepStatus: MetricStatus

    // Readiness
    let readinessScore: Int
    let readinessStatus: MetricStatus

    var metricsCount: Int {
        return 6  // Total number of metrics tracked
    }
}

enum MetricStatus {
    case excellent
    case good
    case moderate
    case needsAttention
    
    var label: String {
        switch self {
        case .excellent: return "Excellent"
        case .good: return "Good"
        case .moderate: return "Moderate"
        case .needsAttention: return "Needs Attention"
        }
    }
    
    var color: Color {
        switch self {
        case .excellent:      return .statusOptimal
        case .good:           return .statusRest
        case .moderate:       return .statusMonitoring
        case .needsAttention: return .statusWarning
        }
    }
}

// MARK: - Previews

#Preview("Balanced Health") {
    NavigationView {
        HolisticHealthDashboard(
            metrics: HealthMetrics(
                weeklyMETMinutes: 2800,
                metStatus: .excellent,
                strengthPercentage: 22,
                trainingBalance: .good,
                currentHRV: 68,
                hrvStatus: .excellent,
                hrvBaselineMs: 65,
                acwr: 1.1,
                loadStatus: .good,
                averageSleep: 7.8,
                sleepStatus: .good,
                readinessScore: 82,
                readinessStatus: .excellent
            )
        )
    }
}

#Preview("Mixed Status") {
    NavigationView {
        HolisticHealthDashboard(
            metrics: HealthMetrics(
                weeklyMETMinutes: 950,
                metStatus: .moderate,
                strengthPercentage: 5,
                trainingBalance: .needsAttention,
                currentHRV: 52,
                hrvStatus: .moderate,
                hrvBaselineMs: 65,
                acwr: 1.4,
                loadStatus: .moderate,
                averageSleep: 6.5,
                sleepStatus: .moderate,
                readinessScore: 64,
                readinessStatus: .moderate
            )
        )
    }
}
