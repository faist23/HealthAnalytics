//
//  SupportingMetricsCard.swift
//  HealthAnalytics
//
//  Created by Claude on 2/23/26.
//

import SwiftUI

/// Supporting metrics grid that shows the key health signals influencing readiness
struct SupportingMetricsCard: View {
    let metrics: HealthMetrics
    @State private var showDetailedExplanation = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with info button
            HStack {
                Text("Health Signals")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                // Info button
                Button {
                    showDetailedExplanation = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.title3)
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
            }
            
            // Grid of metrics (2 columns, 3 rows for 6 metrics)
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                // MET Activity
                MetricTileView(
                    title: "Activity",
                    value: "\(Int(metrics.weeklyMETMinutes)) MET-min",
                    status: metrics.metStatus,
                    icon: "figure.run"
                )
                
                // Training Balance
                MetricTileView(
                    title: "Balance",
                    value: "\(Int(metrics.strengthPercentage))% strength",
                    status: metrics.trainingBalance,
                    icon: "chart.pie"
                )
                
                // HRV
                MetricTileView(
                    title: "HRV",
                    value: "\(Int(metrics.currentHRV)) ms",
                    status: metrics.hrvStatus,
                    icon: "waveform.path.ecg"
                )
                
                // Load (ACWR)
                MetricTileView(
                    title: "Load",
                    value: String(format: "%.2f", metrics.acwr),
                    status: metrics.loadStatus,
                    icon: "chart.line.uptrend.xyaxis"
                )
                
                // Sleep
                MetricTileView(
                    title: "Sleep",
                    value: String(format: "%.1fh", metrics.averageSleep),
                    status: metrics.sleepStatus,
                    icon: "moon.zzz"
                )
                
                // Readiness
                MetricTileView(
                    title: "Readiness",
                    value: "\(metrics.readinessScore)",
                    status: metrics.readinessStatus,
                    icon: "heart.fill"
                )
            }
            
            Divider()
                .padding(.vertical, 8)
            
            // Overall Score Section
            HStack(alignment: .top, spacing: 16) {
                // Score circle
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.2), lineWidth: 10)
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
                        .foregroundStyle(.secondary)
                    
                    Text("A weighted average across all 6 metrics")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 2)
                }
                
                Spacer()
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.05), radius: 10, y: 5)
        )
        .sheet(isPresented: $showDetailedExplanation) {
            DetailedReadinessExplanationView()
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
        case 80...: return .green
        case 65..<80: return .blue
        case 50..<65: return .orange
        default: return .red
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
}

// MARK: - Metric Tile View

private struct MetricTileView: View {
    let title: String
    let value: String
    let status: MetricStatus
    let icon: String
    
    var body: some View {
        VStack(spacing: 8) {
            // Icon with status color
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(status.color)
                .frame(height: 28)
            
            // Title
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
            
            // Value
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(status.color.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(status.color.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Detailed Explanation View

private struct DetailedReadinessExplanationView: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Introduction
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Understanding Your Readiness Score")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("Your readiness score is calculated from multiple validated health metrics, providing a comprehensive view of your recovery status and training capacity.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    
                    Divider()
                    
                    // MET Activity
                    ReadinessMetricExplanation(
                        icon: "figure.run",
                        title: "MET Activity",
                        color: .blue,
                        explanation: "Metabolic Equivalent of Task (MET) minutes measure your weekly activity volume. WHO guidelines recommend 600-1500 MET-min/week for longevity. Unlike VO2 max, METs are used in 99% of longevity research and don't rely on wrist-based estimates."
                    )
                    
                    // Training Balance
                    ReadinessMetricExplanation(
                        icon: "chart.pie",
                        title: "Training Balance",
                        color: .purple,
                        explanation: "Tracks the ratio of endurance to strength training over 14 days. Research shows combining both types provides superior health outcomes compared to either alone. Optimal balance prevents overemphasis on one training modality."
                    )
                    
                    // HRV
                    ReadinessMetricExplanation(
                        icon: "waveform.path.ecg",
                        title: "Heart Rate Variability",
                        color: .red,
                        explanation: "HRV measures the variation in time between heartbeats, reflecting your autonomic nervous system balance. Higher HRV typically indicates better recovery and readiness for training. Recent 7-day average is used to smooth daily fluctuations."
                    )
                    
                    // Load (ACWR)
                    ReadinessMetricExplanation(
                        icon: "chart.line.uptrend.xyaxis",
                        title: "Training Load",
                        color: .orange,
                        explanation: "Acute-to-Chronic Workload Ratio (ACWR) compares recent training (7 days) to longer-term average (28 days). Optimal range is 0.8-1.3. Too low suggests detraining, too high increases injury risk."
                    )
                    
                    // Sleep
                    ReadinessMetricExplanation(
                        icon: "moon.zzz",
                        title: "Sleep Quality",
                        color: .indigo,
                        explanation: "Recent sleep duration (7-day average) is a critical recovery marker. Consistent sleep of 7-9 hours supports recovery, immune function, and training adaptations. Sleep deprivation impairs both performance and decision-making."
                    )
                    
                    Divider()
                    
                    // Score Calculation
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Score Calculation")
                            .font(.headline)
                        
                        Text("Your readiness score (0-100) combines three weighted components:")
                            .font(.body)
                            .foregroundStyle(.secondary)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            ScoreComponentRow(label: "Recovery", points: "40 points", description: "HRV, sleep, resting heart rate")
                            ScoreComponentRow(label: "Fitness", points: "30 points", description: "Training consistency, VO2 max trends")
                            ScoreComponentRow(label: "Fatigue", points: "30 points", description: "Training load, muscle soreness")
                        }
                        .padding(.vertical, 8)
                    }
                    
                    Divider()
                    
                    // Data Timeframes
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Data Timeframes")
                            .font(.headline)
                        
                        Text("Each metric uses different time windows optimized for that specific measurement:")
                            .font(.body)
                            .foregroundStyle(.secondary)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            TimeframeRow(label: "Activity, HRV, Sleep", timeframe: "7 days", description: "Short-term daily patterns")
                            TimeframeRow(label: "Training Balance", timeframe: "14 days", description: "Medium-term workout mix")
                            TimeframeRow(label: "Load (Chronic)", timeframe: "28 days", description: "Long-term training volume")
                            TimeframeRow(label: "Readiness Score", timeframe: "30 days", description: "Comprehensive assessment")
                        }
                        .padding(.vertical, 8)
                        
                        Text("The readiness score always uses the last 30 days, regardless of the date range selector, ensuring it's current and actionable for today's training decisions.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }
                    
                    Divider()
                    
                    // Research Context
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Evidence-Based Approach")
                            .font(.headline)
                        
                        Text("This multi-factorial approach avoids over-reliance on any single metric. Smartwatch VO2 max estimates have 7-16% error rates and often underestimate fitness in trained individuals. By combining multiple validated metrics, we provide a more reliable assessment of your readiness to train.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(20)
            }
            .navigationTitle("Readiness Explained")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Helper Views

private struct ReadinessMetricExplanation: View {
    let icon: String
    let title: String
    let color: Color
    let explanation: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                
                Text(explanation)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

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
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Text(points)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.blue)
        }
        .padding(.vertical, 4)
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
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Text(timeframe)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.orange)
        }
        .padding(.vertical, 4)
    }
}


