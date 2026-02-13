//
//  EnhancedIntentReadinessCard.swift
//  HealthAnalytics
//
//  Enhanced with statistical confidence displays
//  Shows ACWR with CI, sample sizes, and data quality warnings
//

import SwiftUI

struct EnhancedIntentReadinessCard: View {
    let assessment: EnhancedIntentAwareReadinessService.EnhancedReadinessAssessment
    @State private var expandedIntents: Set<ActivityIntent> = []
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            
            // Data Quality Warning (if needed)
            if assessment.dataQuality.overallQuality == .poor || assessment.dataQuality.overallQuality == .fair {
                DataQualityBanner(dataQuality: assessment.dataQuality)
            }
            
            // Header with ACWR + Confidence
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Today's Readiness")
                        .font(.title3)
                        .fontWeight(.bold)
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // ACWR Badge with confidence interval
                VStack(spacing: 4) {
                    Text(String(format: "%.2f", assessment.acwr.value))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(acwrColor)
                    
                    // Show ±margin if we have CI
                    if let ci = assessment.acwr.confidenceInterval {
                        Text("±\(String(format: "%.2f", (ci.upper - ci.lower) / 2))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    
                    Text("Load Ratio")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    
                    HStack(spacing: 4) {
                        Text(acwrLabel)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(acwrColor)
                        
                        // Confidence emoji
                        Text(assessment.acwr.confidence.emoji)
                            .font(.caption2)
                    }
                }
                .padding(12)
                .background(acwrColor.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            
            Divider()
            
            // Green Light Section
            if !assessment.recommendedIntents.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Green Light", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(.green)
                    
                    Text("You're ready for these today")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    ForEach(assessment.recommendedIntents, id: \.self) { intent in
                        if let readinessData = assessment.performanceReadiness[intent] {
                            ExpandableIntentRow(
                                intent: intent,
                                readinessData: readinessData,
                                assessment: assessment,
                                isExpanded: expandedIntents.contains(intent),
                                color: .green,
                                onTap: {
                                    withAnimation(.spring(response: 0.3)) {
                                        if expandedIntents.contains(intent) {
                                            expandedIntents.remove(intent)
                                        } else {
                                            expandedIntents.insert(intent)
                                        }
                                    }
                                }
                            )
                        }
                    }
                }
            }
            
            // Yellow Light Section (Maybe)
            let maybeIntents = ActivityIntent.allCases.filter { intent in
                if assessment.performanceReadiness[intent] != nil {
                    return !assessment.recommendedIntents.contains(intent) &&
                           !assessment.shouldAvoidIntents.contains(intent)
                }
                return false
            }
            
            if !maybeIntents.isEmpty {
                Divider()
                
                VStack(alignment: .leading, spacing: 12) {
                    Label("Proceed with Caution", systemImage: "exclamationmark.triangle.fill")
                        .font(.headline)
                        .foregroundStyle(.orange)
                    
                    Text("Possible, but listen to your body")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    ForEach(maybeIntents, id: \.self) { intent in
                        if let readinessData = assessment.performanceReadiness[intent] {
                            ExpandableIntentRow(
                                intent: intent,
                                readinessData: readinessData,
                                assessment: assessment,
                                isExpanded: expandedIntents.contains(intent),
                                color: .orange,
                                onTap: {
                                    withAnimation(.spring(response: 0.3)) {
                                        if expandedIntents.contains(intent) {
                                            expandedIntents.remove(intent)
                                        } else {
                                            expandedIntents.insert(intent)
                                        }
                                    }
                                }
                            )
                        }
                    }
                }
            }
            
            // Red Light Section
            if !assessment.shouldAvoidIntents.isEmpty {
                Divider()
                
                VStack(alignment: .leading, spacing: 12) {
                    Label("Red Light", systemImage: "xmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(.red)
                    
                    Text("Skip these to avoid overtraining")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    ForEach(assessment.shouldAvoidIntents, id: \.self) { intent in
                        if let readinessData = assessment.performanceReadiness[intent] {
                            ExpandableIntentRow(
                                intent: intent,
                                readinessData: readinessData,
                                assessment: assessment,
                                isExpanded: expandedIntents.contains(intent),
                                color: .red,
                                onTap: {
                                    withAnimation(.spring(response: 0.3)) {
                                        if expandedIntents.contains(intent) {
                                            expandedIntents.remove(intent)
                                        } else {
                                            expandedIntents.insert(intent)
                                        }
                                    }
                                }
                            )
                        }
                    }
                }
            }
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
    
    private var acwrLabel: String {
        switch assessment.acwr.value {
        case 0..<0.8: return "Low Load"
        case 0.8...1.3: return "Optimal"
        case 1.3...1.5: return "Building"
        default: return "High Risk"
        }
    }
    
    private var statusMessage: String {
        switch assessment.trend {
        case .optimal:
            return "Training load is well balanced"
        case .building:
            return "Load is building - monitor fatigue"
        case .detraining:
            return "Load is low - consider ramping up"
        }
    }
}

// MARK: - Data Quality Banner

struct DataQualityBanner: View {
    let dataQuality: EnhancedIntentAwareReadinessService.EnhancedReadinessAssessment.DataQuality
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(bannerColor)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Limited Data")
                    .font(.caption)
                    .fontWeight(.semibold)
                
                Text(dataQuality.overallQuality.description)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding(12)
        .background(bannerColor.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    private var bannerColor: Color {
        switch dataQuality.overallQuality {
        case .excellent, .good: return .green
        case .fair: return .orange
        case .poor: return .red
        }
    }
}

// MARK: - Expandable Intent Row

struct ExpandableIntentRow: View {
    let intent: ActivityIntent
    let readinessData: EnhancedIntentAwareReadinessService.EnhancedReadinessAssessment.ReadinessWithConfidence
    let assessment: EnhancedIntentAwareReadinessService.EnhancedReadinessAssessment
    let isExpanded: Bool
    let color: Color
    let onTap: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Main row (always visible)
            Button(action: onTap) {
                HStack(spacing: 12) {
                    // Intent info
                    HStack(spacing: 8) {
                        Text(intent.emoji)
                            .font(.title3)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(intent.rawValue)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(.primary)
                            
                            Text(intent.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    
                    Spacer()
                    
                    // Confidence badge
                    HStack(spacing: 4) {
                        Text(readinessData.level.emoji)
                            .font(.title3)
                        
                        // Show confidence for non-excellent data
                        if readinessData.confidence != .high {
                            Text(readinessData.confidence.emoji)
                                .font(.caption)
                        }
                    }
                    
                    // Expand chevron
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(color.opacity(isExpanded ? 0.15 : 0.05))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            
            // Expanded details (conditional)
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    
                    Text("Why \(reasoningVerb)")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                    
                    // Reasoning bullets
                    ForEach(reasons, id: \.self) { reason in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: reason.isPositive ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(reason.isPositive ? .green : .red)
                            
                            Text(reason.text)
                                .font(.caption)
                                .foregroundStyle(.primary)
                        }
                    }
                    
                    // Statistical confidence footer
                    Divider()
                        .padding(.vertical, 4)
                    
                    HStack {
                        Image(systemName: "chart.bar.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        
                        Text("Based on \(readinessData.sampleSize) examples • \(readinessData.confidence.description)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
                .background(color.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.top, 4)
            }
        }
    }
    
    private var reasoningVerb: String {
        switch readinessData.level {
        case .excellent: return "you're ready"
        case .good: return "you can do this"
        case .fair: return "proceed with caution"
        case .poor: return "skip this today"
        }
    }
    
    private struct Reason: Hashable {
        let text: String
        let isPositive: Bool
    }
    
    private var reasons: [Reason] {
        var reasons: [Reason] = []
        
        // ACWR reasoning with confidence interval
        let acwrText: String
        if let ci = assessment.acwr.confidenceInterval {
            acwrText = String(format: "%.2f (%.2f-%.2f)",
                            assessment.acwr.value, ci.lower, ci.upper)
        } else {
            acwrText = String(format: "%.2f", assessment.acwr.value)
        }
        
        if assessment.acwr.value <= 1.2 {
            reasons.append(Reason(text: "Training load is optimal (\(acwrText))", isPositive: true))
        } else if assessment.acwr.value <= 1.4 {
            reasons.append(Reason(text: "Load is building (\(acwrText))", isPositive: intent == .easy || intent == .casualWalk))
        } else {
            reasons.append(Reason(text: "Load is high (\(acwrText)) - injury risk", isPositive: false))
        }
        
        // Intent-specific reasoning
        switch intent {
        case .race:
            if readinessData.level == .excellent {
                reasons.append(Reason(text: "Perfect recovery conditions for peak effort", isPositive: true))
            } else if readinessData.level == .poor {
                reasons.append(Reason(text: "Not enough recovery for race intensity", isPositive: false))
            }
            
        case .tempo:
            if readinessData.level == .excellent || readinessData.level == .good {
                reasons.append(Reason(text: "Good for sustained hard effort", isPositive: true))
            } else {
                reasons.append(Reason(text: "Too fatigued for threshold work", isPositive: false))
            }
            
        case .intervals:
            if readinessData.level == .excellent {
                reasons.append(Reason(text: "Fresh enough for high-intensity intervals", isPositive: true))
            } else {
                reasons.append(Reason(text: "Need more recovery for max efforts", isPositive: false))
            }
            
        case .easy:
            if assessment.acwr.value > 1.3 {
                reasons.append(Reason(text: "Easy pace aids recovery when fatigued", isPositive: true))
            } else {
                reasons.append(Reason(text: "Always safe for active recovery", isPositive: true))
            }
            
        case .long:
            if assessment.acwr.value <= 1.3 {
                reasons.append(Reason(text: "Good base fitness for volume work", isPositive: true))
            } else {
                reasons.append(Reason(text: "High load - adding volume increases injury risk", isPositive: false))
            }
            
        case .casualWalk:
            reasons.append(Reason(text: "Always safe for movement and recovery", isPositive: true))
            
        case .strength:
            if readinessData.level == .good || readinessData.level == .excellent {
                reasons.append(Reason(text: "Fresh enough for resistance training", isPositive: true))
            } else {
                reasons.append(Reason(text: "Consider lighter weights or mobility work", isPositive: false))
            }
            
        case .other:
            break
        }
        
        return reasons
    }
}

#Preview {
    ScrollView {
        EnhancedIntentReadinessCard(
            assessment: EnhancedIntentAwareReadinessService.EnhancedReadinessAssessment(
                acwr: StatisticalResult(
                    value: 1.15,
                    confidenceInterval: (lower: 1.05, upper: 1.25),
                    sampleSize: 25,
                    confidence: .medium
                ),
                chronicLoad: 250,
                acuteLoad: 290,
                trend: .optimal,
                performanceReadiness: [
                    .race: EnhancedIntentAwareReadinessService.EnhancedReadinessAssessment.ReadinessWithConfidence(level: .good, confidence: .medium, sampleSize: 8),
                    .tempo: EnhancedIntentAwareReadinessService.EnhancedReadinessAssessment.ReadinessWithConfidence(level: .excellent, confidence: .medium, sampleSize: 10),
                    .intervals: EnhancedIntentAwareReadinessService.EnhancedReadinessAssessment.ReadinessWithConfidence(level: .good, confidence: .medium, sampleSize: 7),
                    .easy: EnhancedIntentAwareReadinessService.EnhancedReadinessAssessment.ReadinessWithConfidence(level: .excellent, confidence: .high, sampleSize: 35),
                    .long: EnhancedIntentAwareReadinessService.EnhancedReadinessAssessment.ReadinessWithConfidence(level: .excellent, confidence: .medium, sampleSize: 12),
                    .casualWalk: EnhancedIntentAwareReadinessService.EnhancedReadinessAssessment.ReadinessWithConfidence(level: .excellent, confidence: .high, sampleSize: 40),
                    .strength: EnhancedIntentAwareReadinessService.EnhancedReadinessAssessment.ReadinessWithConfidence(level: .fair, confidence: .low, sampleSize: 6),
                    .other: EnhancedIntentAwareReadinessService.EnhancedReadinessAssessment.ReadinessWithConfidence(level: .good, confidence: .medium, sampleSize: 15)
                ],
                recommendedIntents: [.easy, .long, .tempo],
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
