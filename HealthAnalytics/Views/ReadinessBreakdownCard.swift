//
//  ReadinessBreakdownCard.swift
//  HealthAnalytics
//
//  Transparent readiness score breakdown showing component contributions
//  Builds trust by showing WHY you got this score
//

import SwiftUI

struct ReadinessBreakdownCard: View {
    let breakdown: ScoreBreakdown
    @State private var showDetails = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: "chart.bar.fill")
                    .foregroundStyle(Color.accent)
                Text("Score Breakdown")
                    .font(.headline)
                
                Spacer()
                
                Button(action: { showDetails.toggle() }) {
                    HStack(spacing: 4) {
                        Text(showDetails ? "Hide" : "Details")
                            .font(.caption)
                        Image(systemName: showDetails ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                    }
                    .foregroundStyle(Color.accent)
                }
            }
            
            // Component Bars
            VStack(spacing: 12) {
                ComponentBar(
                    label: "Recovery",
                    score: breakdown.recoveryScore,
                    maxScore: 40,
                    color: .statusOptimal,
                    icon: "heart.fill"
                )

                ComponentBar(
                    label: "Fitness",
                    score: breakdown.fitnessScore,
                    maxScore: 30,
                    color: .statusRest,
                    icon: "figure.run"
                )

                ComponentBar(
                    label: "Fatigue",
                    score: breakdown.fatigueScore,
                    maxScore: 30,
                    color: .statusMonitoring,
                    icon: "gauge.with.dots.needle.bottom.50percent"
                )
            }
            
            // Total
            HStack {
                Text("Total Score")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Text("\(breakdown.recoveryScore + breakdown.fitnessScore + breakdown.fatigueScore) / 100")
                    .font(.headline)
                    .fontWeight(.bold)
            }
            .padding(.top, 8)
            
            // Detailed explanations
            if showDetails {
                VStack(alignment: .leading, spacing: 12) {
                    Divider()
                    
                    DetailSection(
                        title: "Recovery (\(breakdown.recoveryScore)/40)",
                        description: breakdown.recoveryDetails,
                        color: .statusOptimal
                    )

                    DetailSection(
                        title: "Fitness (\(breakdown.fitnessScore)/30)",
                        description: breakdown.fitnessDetails,
                        color: .statusRest
                    )

                    DetailSection(
                        title: "Fatigue (\(breakdown.fatigueScore)/30)",
                        description: breakdown.fatigueDetails,
                        color: .statusMonitoring
                    )
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: .radiusMd)
                .fill(Color(uiColor: .systemBackground))
                .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
        )
        .animation(.easeInOut(duration: 0.3), value: showDetails)
    }
}

// MARK: - Component Bar View

struct ComponentBar: View {
    let label: String
    let score: Int
    let maxScore: Int
    let color: Color
    let icon: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(color)
                
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Text("\(score) / \(maxScore)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(color)
            }
            
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.textTertiary.opacity(0.15))
                    
                    // Fill
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: geometry.size.width * (Double(score) / Double(maxScore)))
                }
            }
            .frame(height: 8)
        }
    }
}

// MARK: - Detail Section View

struct DetailSection: View {
    let title: String
    let description: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(color)
            
            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Supporting Model

/// Transparent score breakdown - shows what contributes to readiness
struct ScoreBreakdown {
    let recoveryScore: Int        // 0-40 points (HRV, RHR, sleep)
    let fitnessScore: Int         // 0-30 points (recent training quality)
    let fatigueScore: Int         // 0-30 points (training load vs capacity)
    
    let recoveryDetails: String
    let fitnessDetails: String
    let fatigueDetails: String
}

// MARK: - Previews

#Preview("High Score") {
    ReadinessBreakdownCard(
        breakdown: ScoreBreakdown(
            recoveryScore: 38,
            fitnessScore: 27,
            fatigueScore: 28,
            recoveryDetails: "HRV elevated 8% above baseline. RHR down 2 bpm. Sleep: 8.2 hours.",
            fitnessDetails: "Training consistency: 12/14 days. Good volume and intensity mix.",
            fatigueDetails: "ACWR: 1.1 (optimal range). Well-recovered from recent training."
        )
    )
    .padding()
}

#Preview("Moderate Score") {
    ReadinessBreakdownCard(
        breakdown: ScoreBreakdown(
            recoveryScore: 28,
            fitnessScore: 22,
            fatigueScore: 18,
            recoveryDetails: "HRV slightly down. RHR elevated 3 bpm. Sleep: 6.8 hours.",
            fitnessDetails: "Training consistency: 8/14 days. Moderate volume.",
            fatigueDetails: "ACWR: 1.4 (elevated). Recent training load is high relative to fitness."
        )
    )
    .padding()
}
