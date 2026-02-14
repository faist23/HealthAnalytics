//
//  DailyRecommendationCard.swift
//  HealthAnalytics
//
//  HRV-guided daily training recommendation card
//

import SwiftUI

struct DailyRecommendationCard: View {
    let recommendation: DailyRecommendationService.DailyRecommendation
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header with status
            HStack(spacing: 12) {
                Text(recommendation.status.emoji)
                    .font(.system(size: 40))
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("TODAY'S RECOMMENDATION")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                    
                    Text(recommendation.headline)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(colorForStatus(recommendation.status))
                }
                
                Spacer()
            }
            
            // Main guidance
            Text(recommendation.guidance)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            
            Divider()
            
            // Training zones
            if !recommendation.targetZones.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Recommended Today", systemImage: "checkmark.circle.fill")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.green)
                    
                    ForEach(recommendation.targetZones, id: \.self) { zone in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(.green.opacity(0.2))
                                .frame(width: 6, height: 6)
                            
                            Text(zone)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            
            if !recommendation.avoidZones.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Avoid Today", systemImage: "xmark.circle.fill")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.orange)
                    
                    ForEach(recommendation.avoidZones, id: \.self) { zone in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(.orange.opacity(0.2))
                                .frame(width: 6, height: 6)
                            
                            Text(zone)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            
            // Reasoning and confidence
            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Text(recommendation.reasoning)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Text(recommendation.confidence.description)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(.secondary.opacity(0.1))
                    )
            }
        }
        .padding(20)
    }
    
    private func colorForStatus(_ status: DailyRecommendationService.DailyRecommendation.RecommendationStatus) -> Color {
        switch status {
        case .goHard: return .purple
        case .quality: return .green
        case .moderate: return .blue
        case .easy: return .orange
        case .rest: return .red
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 16) {
        DailyRecommendationCard(
            recommendation: DailyRecommendationService.DailyRecommendation(
                status: .goHard,
                headline: "GO HARD - Prime Window",
                guidance: "Everything is aligned: elevated HRV, good recovery, and no recent hard sessions. This is your window for breakthrough efforts, PRs, or race-pace intervals.",
                targetZones: ["Zone 5 (VO2max)", "Zone 6 (Anaerobic)", "Race efforts", "PR attempts"],
                avoidZones: [],
                confidence: .high,
                reasoning: "HRV elevated +8.5% • Well-rested, no recent hard work • Good sleep (8.2h)"
            )
        )
        .cardStyle(for: .info)
        
        DailyRecommendationCard(
            recommendation: DailyRecommendationService.DailyRecommendation(
                status: .easy,
                headline: "EASY - Zone 1/2 Only",
                guidance: "Your HRV is suppressed, indicating accumulated fatigue. Stick to easy aerobic work (Zone 1-2) or consider rest. Hard training now will dig a deeper hole.",
                targetZones: ["Zone 1 (Recovery)", "Zone 2 (Easy base)"],
                avoidZones: ["Zone 3+", "Any intervals", "Long duration"],
                confidence: .high,
                reasoning: "HRV suppressed -8.2% • Body needs recovery stress only"
            )
        )
        .cardStyle(for: .info)
        
        DailyRecommendationCard(
            recommendation: DailyRecommendationService.DailyRecommendation(
                status: .rest,
                headline: "REST - Recovery Needed",
                guidance: "Your HRV is significantly suppressed. Take a complete rest day or very light active recovery only. Your body is telling you it needs time to adapt.",
                targetZones: ["Complete rest", "Very light recovery walk/spin (<30min Zone 1)"],
                avoidZones: ["Any structured training", "All zones above Z1"],
                confidence: .high,
                reasoning: "HRV very low -16.3% • Recovery urgently needed"
            )
        )
        .cardStyle(for: .info)
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
