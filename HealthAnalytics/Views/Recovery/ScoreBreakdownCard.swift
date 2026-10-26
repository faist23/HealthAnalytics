//
//  ScoreBreakdownCard.swift
//  HealthAnalytics
//
//  Recovery / fitness / fatigue split of the recovery score.
//

import SwiftUI

struct ScoreBreakdownCard: View {
    let breakdown: ReadinessAnalyzer.ScoreBreakdown
    
    var body: some View {
        VStack(alignment: .leading, spacing: .spacingMd) {
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
        VStack(alignment: .leading, spacing: .spacingSm) {
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
