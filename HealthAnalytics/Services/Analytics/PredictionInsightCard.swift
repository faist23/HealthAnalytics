//
//  PredictionInsightCard.swift
//  HealthAnalytics
//
//  Created by Craig Faist on 2/1/26.
//
//  SwiftUI card that surfaces the ML prediction result inside ReadinessView.
//  Displays predicted performance, a feature-importance breakdown, and the
//  live conditions that fed the model.
//

import SwiftUI

// MARK: - Main Card

struct PredictionInsightCard: View {
    let prediction: PerformancePredictor.Prediction
    let weights:    PerformancePredictor.FeatureWeights

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {

            // ── Header ──
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ML Performance Prediction")
                        .font(.headline)
                    Text("Trained on your workout history")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                ConfidenceBadge(confidence: prediction.confidence)
            }

            Divider()

            // ── Hero number ──
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(formattedPerformance)
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundStyle(predictionColor)

                VStack(alignment: .leading, spacing: 0) {
                    Text(prediction.unit)
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("predicted \(prediction.activityType.lowercased())")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // ── Feature importance ──
            Divider()

            Text("What matters most today")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)

            VStack(spacing: 10) {
                FeatureBar(label: "Sleep",      value: weights.sleep,     color: .blue,   detail: formatSleep(prediction.inputs.sleepHours))
                FeatureBar(label: "HRV",        value: weights.hrv,       color: .green,  detail: "\(Int(prediction.inputs.hrvMs)) ms")
                FeatureBar(label: "Resting HR", value: weights.restingHR, color: .red,    detail: "\(Int(prediction.inputs.restingHR)) bpm")
            }

            // ── Dominant-factor callout ──
            DominantFactorBanner(dominant: weights.dominantFeature)
        }
        .padding(20)
    }

    // MARK: - Helpers

    private var formattedPerformance: String {
        if prediction.unit == "W" {
            return "\(Int(prediction.predictedPerformance))"
        } else {
            // mph → show one decimal
            return String(format: "%.1f", prediction.predictedPerformance)
        }
    }

    /// Color shifts with predicted performance relative to a rough baseline
    private var predictionColor: Color {
        // For runs: anything above 5 mph is decent; for rides: above 150 W
        let isGood = prediction.unit == "W"
            ? prediction.predictedPerformance > 150
            : prediction.predictedPerformance > 5.0
        return isGood ? .green : .orange
    }

    private func formatSleep(_ hours: Double) -> String {
        let h = Int(hours)
        let m = Int((hours - Double(h)) * 60)
        return "\(h)h \(m)m"
    }
}

// MARK: - Confidence Badge

private struct ConfidenceBadge: View {
    let confidence: PerformancePredictor.Confidence

    var body: some View {
        Text(confidence.rawValue)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(badgeColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(badgeColor.opacity(0.15))
            .clipShape(Capsule())
    }

    private var badgeColor: Color {
        switch confidence {
        case .high:   return .green
        case .medium: return .blue
        case .low:    return .orange
        }
    }
}

// MARK: - Feature Importance Bar

private struct FeatureBar: View {
    let label:  String
    let value:  Double   // 0…1 normalised weight
    let color:  Color
    let detail: String

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(label)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(Int(value * 100))%")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(color)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color.opacity(0.12))
                        .frame(height: 6)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: geo.size.width * value, height: 6)
                        .animation(.easeOut(duration: 0.4), value: value)
                }
            }
            .frame(height: 6)
        }
    }
}

// MARK: - Dominant Factor Banner

private struct DominantFactorBanner: View {
    let dominant: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "lightbulb.fill")
                .foregroundStyle(.yellow)

            Text("\(dominant) is your biggest lever today")
                .font(.subheadline)
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Error / Insufficient-Data States

/// Shown when training hasn't run yet or there's not enough data.
struct PredictionUnavailableCard: View {
    let reason: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "brain.fill")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)

            Text("Prediction Unavailable")
                .font(.headline)

            Text(reason)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
    }
}
