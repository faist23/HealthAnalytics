//
//  TrainingDNACard.swift
//  HealthAnalytics
//
//  Phase 2 — Pattern Engine
//  One card per detected TrainingPattern. Follows Warm Signal design system.
//

import SwiftUI

struct TrainingDNACard: View {
    let pattern: TrainingPattern

    // "New" badge: dismissed on first tap, persisted via UserDefaults
    @State private var isSeen: Bool = false

    private var seenKey: String { "trainingDNA_\(pattern.patternType.rawValue)_seen" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
                .padding(.bottom, 12)

            Divider()
                .background(Color.surfaceRaised)
                .padding(.bottom, 10)

            confidenceBadgeRow
                .padding(.bottom, .spacingSm)

            TrainingPatternTimelineView(pattern: pattern)
                .padding(.bottom, 12)

            Divider()
                .background(Color.surfaceRaised)
                .padding(.bottom, 10)

            Text(pattern.evidenceSummary)
                .font(.coachGuidance)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 10)

            coachingRow
        }
        .padding(.spacingMd)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: .radiusMd))
        .overlay(
            RoundedRectangle(cornerRadius: .radiusMd)
                .stroke(Color.accentBorder, lineWidth: 1)
        )
        .onTapGesture {
            if pattern.isNewlyDetected && !isSeen {
                isSeen = true
                UserDefaults.standard.set(true, forKey: seenKey)
            }
        }
        .onAppear {
            isSeen = UserDefaults.standard.bool(forKey: seenKey)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Header Row

    @ViewBuilder
    private var headerRow: some View {
        HStack(alignment: .top, spacing: .spacingSm) {
            Image(systemName: pattern.patternType.icon)
                .font(.system(size: 20))
                .foregroundStyle(patternColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(pattern.patternType.displayName)
                    .font(.cardTitle)
                    .foregroundStyle(Color.textPrimary)

                Text(pattern.patternType.definition)
                    .font(.system(size: 13, weight: .regular, design: .default))
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            HStack(spacing: .spacingSm) {
                if pattern.isNewlyDetected && !isSeen {
                    newBadge
                }

                ShareLink(item: pattern.shareText) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.textSecondary)
                        .frame(width: 24, height: 24)
                }
                .accessibilityLabel("Share \(pattern.patternType.displayName) insight")
            }
        }
    }

    // MARK: - "New" Badge

    private var newBadge: some View {
        Text("New")
            .font(.system(size: 11, weight: .semibold, design: .default))
            .foregroundStyle(Color.accent)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.accentDim, in: RoundedRectangle(cornerRadius: .radiusSm))
            .overlay(
                RoundedRectangle(cornerRadius: .radiusSm)
                    .stroke(Color.accentBorder, lineWidth: 1)
            )
    }

    // MARK: - Confidence Badge Row

    private var confidenceBadgeRow: some View {
        HStack(spacing: 8) {
            confidencePill
                .accessibilityHidden(true)

            Text(confidenceCountAndDuration)
                .font(.system(size: 13, weight: .medium, design: .default))
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer()
        }
        .accessibilityLabel(confidenceAccessibilityLabel)
    }

    private var confidencePill: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(confidenceSignalColor)
                .frame(width: 6, height: 6)
            Text(pattern.confidenceQualifier)
                .font(.system(size: 11, weight: .semibold, design: .default))
                .foregroundStyle(confidenceSignalColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(confidenceFillColor, in: RoundedRectangle(cornerRadius: .radiusSm))
        .overlay(
            RoundedRectangle(cornerRadius: .radiusSm)
                .stroke(confidenceBorderColor, lineWidth: 1)
        )
    }

    private enum ConfidenceTier { case consistent, mixed, tentative }

    private var confidenceTier: ConfidenceTier {
        let ratio = pattern.confidenceDenominator > 0
            ? Double(pattern.confidenceNumerator) / Double(pattern.confidenceDenominator)
            : 0
        if pattern.confidenceNumerator > 3 && ratio >= 0.75 { return .consistent }
        if pattern.confidenceNumerator > 3 { return .mixed }
        return .tentative
    }

    private var confidenceSignalColor: Color {
        switch confidenceTier {
        case .consistent: return Color.statusOptimal
        case .mixed:      return Color.statusMonitoring
        case .tentative:  return Color.textSecondary
        }
    }

    private var confidenceFillColor: Color {
        switch confidenceTier {
        case .consistent: return Color.statusOptimal.opacity(0.12)
        case .mixed:      return Color.statusMonitoring.opacity(0.12)
        case .tentative:  return Color.surfaceRaised
        }
    }

    private var confidenceBorderColor: Color {
        switch confidenceTier {
        case .consistent: return Color.statusOptimal.opacity(0.22)
        case .mixed:      return Color.statusMonitoring.opacity(0.22)
        case .tentative:  return Color.textTertiary
        }
    }

    private var instanceDateSpan: String? {
        let dates = pattern.instanceDates
        guard dates.count >= 2 else { return nil }
        let sorted = dates.sorted()
        let days = Calendar.current.dateComponents([.day], from: sorted.first!, to: sorted.last!).day ?? 0
        guard days > 0 else { return nil }
        return "\(days) days"
    }

    private var confidenceCountAndDuration: String {
        guard let span = instanceDateSpan else { return pattern.confidenceCountText }
        return "\(pattern.confidenceCountText) · \(span)"
    }

    private var confidenceAccessibilityLabel: String {
        let base = "Pattern confidence: \(pattern.confidenceQualifier), \(pattern.confidenceCountText)"
        guard let span = instanceDateSpan else { return base }
        return "\(base), tracked over \(span)"
    }

    // MARK: - Coaching Row (accent border rule)

    private var coachingRow: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color.accent)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: .spacingXs) {
                Text(pattern.coachingResponse)
                    .font(.coachGuidance)
                    .foregroundStyle(Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Updated \(pattern.detectedAt.relativeTimeString)")
                    .font(.dataAxis)
                    .foregroundStyle(Color.textTertiary)
            }
        }
    }

    // MARK: - Pattern Color

    private var patternColor: Color {
        switch pattern.patternType {
        case .blockCrashCycle:    return Color.statusWarning
        case .hrvPrecursor:       return Color.statusMonitoring
        case .sleepFragmentation: return Color.statusRest
        case .backToBackCrash:    return Color.accent
        case .performancePeak:    return Color.statusOptimal
        case .tapering:           return Color.textSecondary
        }
    }
}

// MARK: - Date Helpers

private extension Date {
    var relativeTimeString: String {
        let days = Calendar.current.dateComponents([.day], from: self, to: Date()).day ?? 0
        switch days {
        case 0:  return "today"
        case 1:  return "yesterday"
        default: return "\(days) days ago"
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    let pattern = TrainingPattern(
        patternType: .blockCrashCycle,
        detectedAt: Date(),
        confidenceNumerator: 4,
        confidenceDenominator: 4,
        evidenceSummary: "Your HRV and training load consistently drop in the final days of each training block.",
        citationKey: "meeusen2013",
        instanceDates: [
            Calendar.current.date(byAdding: .day, value: -150, to: Date())!,
            Calendar.current.date(byAdding: .day, value: -90, to: Date())!,
            Calendar.current.date(byAdding: .day, value: -45, to: Date())!,
            Calendar.current.date(byAdding: .day, value: -10, to: Date())!
        ],
        coachingResponse: "Try adding an extra deload day at the end of each block before intensity drops."
    )
    return ScrollView {
        VStack(spacing: .spacingMd) {
            TrainingDNACard(pattern: pattern)
        }
        .padding()
    }
    .background(Color.background)
}
#endif
