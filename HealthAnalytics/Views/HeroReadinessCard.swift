//
//  HeroReadinessCard.swift
//  HealthAnalytics
//
//  Single source of truth for readiness score - shown on Today tab
//

import SwiftUI

struct HeroReadinessCard: View {
    let score: Int
    let level: ReadinessLevel
    let recommendation: String
    
    var body: some View {
        VStack(spacing: 16) {
            // Hero Score Circle
            ZStack {
                // Background circle
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 16)
                    .frame(width: 140, height: 140)
                
                // Progress circle
                Circle()
                    .trim(from: 0, to: Double(score) / 100.0)
                    .stroke(
                        gradientForScore,
                        style: StrokeStyle(lineWidth: 16, lineCap: .round)
                    )
                    .frame(width: 140, height: 140)
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 1.0, dampingFraction: 0.8), value: score)
                
                // Score text
                VStack(spacing: 2) {
                    Text("\(score)")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundStyle(gradientForScore)
                    
                    Text("Readiness")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 8)
            
            // Status Badge
            HStack(spacing: 8) {
                Text(level.emoji)
                    .font(.title3)
                
                Text(level.rawValue)
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(colorForLevel.opacity(0.15))
            )
            .foregroundStyle(colorForLevel)
            
            // Daily Recommendation
            Text(recommendation)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding(.vertical, 20)
    }
    
    private var gradientForScore: LinearGradient {
        let colors: [Color]
        if score >= 80 {
            colors = [.green, .green.opacity(0.8)]
        } else if score >= 60 {
            colors = [.yellow, .orange]
        } else {
            colors = [.orange, .red]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    
    private var colorForLevel: Color {
        switch level {
        case .excellent, .good: return .green
        case .moderate: return .yellow
        case .poor: return .red
        }
    }
}

#Preview {
    HeroReadinessCard(
        score: 72,
        level: .moderate,
        recommendation: "Managing fatigue. Focus on easy training and prioritize recovery."
    )
    .cardStyle(for: .recovery)
    .padding()
}
