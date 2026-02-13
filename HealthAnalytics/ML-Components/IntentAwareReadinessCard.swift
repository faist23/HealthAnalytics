//
//  IntentAwareReadinessCard.swift
//  HealthAnalytics
//
//  Displays intent-specific readiness recommendations
//  Shows what types of workouts you're ready for TODAY
//

import SwiftUI

struct IntentAwareReadinessCard: View {
    let assessment: EnhancedIntentAwareReadinessService.EnhancedReadinessAssessment
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Today's Readiness")
                        .font(.headline)
                    Text("What you're ready for right now")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                
                // ACWR Badge
                VStack(spacing: 2) {
                    Text(String(format: "%.2f", assessment.acwr.value))
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundStyle(acwrColor)
                    Text("Load Ratio")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(acwrColor.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            
            Divider()
            
            // Recommended Activities
            if !assessment.recommendedIntents.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Label("You're Ready For", systemImage: "checkmark.circle.fill")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.green)
                    
                    ForEach(assessment.recommendedIntents, id: \.self) { intent in
                        if let readiness = assessment.performanceReadiness[intent] {
                            IntentReadinessRow(
                                intent: intent,
                                readiness: readiness.level,
                                isRecommended: true
                            )
                        }
                    }
                }
            }
            
            // Activities to Avoid
            if !assessment.shouldAvoidIntents.isEmpty {
                Divider()
                
                VStack(alignment: .leading, spacing: 12) {
                    Label("Not Today", systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.orange)
                    
                    ForEach(assessment.shouldAvoidIntents, id: \.self) { intent in
                        if let readiness = assessment.performanceReadiness[intent] {
                            IntentReadinessRow(
                                intent: intent,
                                readiness: readiness.level,
                                isRecommended: false
                            )
                        }
                    }
                }
            }
            
            // Overall Status Message
            Divider()
            
            HStack(spacing: 10) {
                Image(systemName: statusIcon)
                    .foregroundStyle(statusColor)
                
                Text(statusMessage)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(statusColor.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(20)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    // MARK: - Computed Properties
    
    private var acwrColor: Color {
        switch assessment.acwr.value {
        case 0..<0.8: return .blue
        case 0.8...1.3: return .green
        case 1.3...1.5: return .orange
        default: return .red
        }
    }
    
    private var statusIcon: String {
        switch assessment.trend {
        case .optimal: return "checkmark.circle.fill"
        case .building: return "arrow.up.circle.fill"
        case .detraining: return "arrow.down.circle.fill"
        }
    }
    
    private var statusColor: Color {
        switch assessment.trend {
        case .optimal: return .green
        case .building: return .orange
        case .detraining: return .blue
        }
    }
    
    private var statusMessage: String {
        switch assessment.trend {
        case .optimal:
            return "You're in the sweet spot. Training load is well balanced."
        case .building:
            return "Load is building. Monitor fatigue and prioritize recovery."
        case .detraining:
            return "Load is low. Consider ramping up training volume."
        }
    }
}

// MARK: - Intent Readiness Row

struct IntentReadinessRow: View {
    let intent: ActivityIntent
    let readiness: EnhancedIntentAwareReadinessService.EnhancedReadinessAssessment.ReadinessWithConfidence.ReadinessLevel
    let isRecommended: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            // Intent emoji and name
            HStack(spacing: 8) {
                Text(intent.emoji)
                    .font(.title3)
                
                Text(intent.rawValue)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            
            Spacer()
            
            // Readiness indicator
            HStack(spacing: 4) {
                Text(readiness.emoji)
                Text(readinessText)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(readinessColor)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(readinessColor.opacity(0.15))
            .clipShape(Capsule())
        }
        .padding(.vertical, 4)
    }
    
    private var readinessText: String {
        switch readiness {
        case .excellent: return "Ready"
        case .good: return "Good"
        case .fair: return "Caution"
        case .poor: return "Skip"
        }
    }
    
    private var readinessColor: Color {
        switch readiness {
        case .excellent: return .green
        case .good: return .blue
        case .fair: return .orange
        case .poor: return .red
        }
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        IntentAwareReadinessCard(
            assessment: EnhancedIntentAwareReadinessService.EnhancedReadinessAssessment(
                acwr: StatisticalResult(
                    value: 1.15,
                    confidenceInterval: (lower: 1.05, upper: 1.25),
                    sampleSize: 25,
                    confidence: .medium
                ),
                chronicLoad: 45.0,
                acuteLoad: 52.0,
                trend: .optimal,
                performanceReadiness: [
                    .easy: EnhancedIntentAwareReadinessService.EnhancedReadinessAssessment.ReadinessWithConfidence(level: .excellent, confidence: .high, sampleSize: 35),
                    .tempo: EnhancedIntentAwareReadinessService.EnhancedReadinessAssessment.ReadinessWithConfidence(level: .good, confidence: .medium, sampleSize: 10),
                    .long: EnhancedIntentAwareReadinessService.EnhancedReadinessAssessment.ReadinessWithConfidence(level: .good, confidence: .medium, sampleSize: 12),
                    .intervals: EnhancedIntentAwareReadinessService.EnhancedReadinessAssessment.ReadinessWithConfidence(level: .fair, confidence: .low, sampleSize: 6),
                    .race: EnhancedIntentAwareReadinessService.EnhancedReadinessAssessment.ReadinessWithConfidence(level: .poor, confidence: .medium, sampleSize: 8)
                ],
                recommendedIntents: [.easy, .tempo, .long],
                shouldAvoidIntents: [.race, .intervals],
                sampleValidation: SampleSizeValidator.ValidationResult(
                    isValid: true,
                    sampleSize: 25,
                    required: 10,
                    confidence: .medium,
                    message: "Good sample size for analysis"
                ),
                dataQuality: EnhancedIntentAwareReadinessService.EnhancedReadinessAssessment.DataQuality(
                    hasAdequateSleep: true,
                    hasAdequateHRV: true,
                    hasAdequateWorkouts: true,
                    overallQuality: .good
                )
            )
        )
        .padding()
    }
}
