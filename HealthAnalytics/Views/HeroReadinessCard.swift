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
    var intraDay: RecoveryDecayService.IntraDayReadiness? = nil
    
    var body: some View {
        VStack(spacing: .spacingMd) {
            // Hero Score Circle
            ZStack {
                // Background circle
                Circle()
                    .stroke(Color.textTertiary.opacity(0.15), lineWidth: 16)
                    .frame(width: 140, height: 140)
                
                // Baseline indicator (dashed line)
                if let intraDay = intraDay, !intraDay.isFullyRecovered {
                    Circle()
                        .trim(from: 0, to: Double(intraDay.baselineScore) / 100.0)
                        .stroke(Color.statusRest.opacity(0.3), style: StrokeStyle(lineWidth: 16, lineCap: .round, dash: [2, 4]))
                        .frame(width: 140, height: 140)
                        .rotationEffect(.degrees(-90))
                }
                
                // Progress circle (Current dynamic score)
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
                    
                    Text("Recovery")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, .spacingSm)
            
            // Dynamic Recovery Banner
            if let intraDay = intraDay, !intraDay.isFullyRecovered {
                HStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.title3)
                        .foregroundStyle(Color.statusRest)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Recovery in progress")
                            .font(.subheadline)
                            .fontWeight(.bold)
                        
                        Text("Est. full recovery: \(formatRecoveryTime(intraDay.timeToFullRecovery))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Text("-\(intraDay.fatigueImpact)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.statusWarning.opacity(0.2))
                        .foregroundStyle(Color.statusWarning)
                        .clipShape(Capsule())
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.statusRest.opacity(0.05)))
                .padding(.horizontal)
            }
            
            // Status Badge
            HStack(spacing: .spacingSm) {
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
                .font(.coachGuidance)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 24)
            
            // Score calculation explanation
            Text("Based on Recovery (0-40) + Fitness (0-30) + Fatigue (0-30)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
                .padding(.top, 4)
        }
        .padding(.vertical, 20)
    }
    
    private func formatRecoveryTime(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
    
    private var gradientForScore: LinearGradient {
        let colors: [Color]
        if score >= 80 {
            colors = [.statusOptimal, .statusOptimal.opacity(0.8)]
        } else if score >= 60 {
            colors = [.statusMonitoring, .statusWarning]
        } else {
            colors = [.statusWarning, .statusWarning]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var colorForLevel: Color {
        switch level {
        case .excellent, .good: return .statusOptimal
        case .moderate: return .statusMonitoring
        case .poor: return .statusWarning
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
