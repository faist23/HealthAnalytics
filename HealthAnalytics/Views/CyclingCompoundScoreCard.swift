//
//  CyclingCompoundScoreCard.swift
//  HealthAnalytics
//

import SwiftUI

struct CyclingCompoundScoreCard: View {
    let analysis: CyclingPowerAnalyzer.CompoundScoreAnalysis
    @State private var showDetailedExplanation = false
    
    var body: some View {
        Button(action: { showDetailedExplanation.toggle() }) {
            VStack(alignment: .leading, spacing: .spacingMd) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: .spacingXs) {
                        Text("COMPOUND SCORE")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.secondary)
                            .tracking(1)
                        Text(analysis.phenotype)
                            .font(.subheadline)
                            .foregroundStyle(Color.statusRest) // Blue-ish
                    }
                    Spacer()
                    
                    VStack(spacing: .spacingXs) {
                        Text(String(format: "%.0f", analysis.compoundScore))
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.statusRest)
                        Text(analysis.level)
                            .font(.caption)
                            .foregroundStyle(Color.textTertiary)
                    }
                }
                
                // Details
                HStack(spacing: .spacingMd) {
                    VStack(alignment: .leading) {
                        Text("Absolute Power (5-Min Max)")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                        Text(String(format: "%.0f W", analysis.absoluteFTP))
                            .font(.system(size: 15, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.textPrimary)
                    }
                    
                    Divider()
                        .background(Color.white.opacity(0.1))
                    
                    VStack(alignment: .leading) {
                        Text("Relative Power")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                        Text(String(format: "%.2f W/kg", analysis.relativeFTP))
                            .font(.system(size: 15, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.textPrimary)
                    }
                }
                
                // Data Source Note
                HStack {
                    Image(systemName: "info.circle")
                        .font(.caption2)
                    Text("Derived from 5-min peak power on \(analysis.dataDate.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption2)
                }
                .foregroundStyle(Color.textTertiary)
                
                // Actionable Insight
                Text(analysis.insight)
                    .font(.system(size: 15, weight: .regular, design: .default))
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding()
            .solidCard()
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showDetailedExplanation) {
            MetricConditionDetailView(
                config: MetricDisplayConfig(
                    id: "compound_score",
                    title: "Cycling Compound Score",
                    icon: "bicycle",
                    currentValueFormatted: String(format: "%.0f", analysis.compoundScore),
                    status: .good, // Using .good (blue) for optimal representation
                    citation: CitationDatabase.citation(for: .compoundScore),
                    thresholdBarValue: nil,
                    conditionReasoning: analysis.insight,
                    guidanceText: "Target workouts that balance raw sprint/TT power with lean weight management based on your phenotype (\(analysis.phenotype)).\n\n*Note: This app calculates your Absolute Power by extracting the highest 5-minute rolling average power directly from your recent cycling workouts.\n\nGrading Scale (approximate):\n• Beginner: < 450\n• Recreational: 450 - 749\n• Intermediate: 750 - 1099\n• Advanced: 1100 - 1599\n• Elite/Pro: 1600+",
                    detailedInsight: nil,
                    badgeType: .science,
                    isBlendedHRVSource: false
                )
            )
        }
    }
}
