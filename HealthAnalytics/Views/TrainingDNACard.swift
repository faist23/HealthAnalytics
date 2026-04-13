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

            confidenceLine
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

    // MARK: - Confidence Line

    private var confidenceLine: some View {
        HStack(spacing: 0) {
            Text(pattern.confidenceQualifier + " · ")
                .font(.system(size: 13, weight: .medium, design: .default))
                .foregroundStyle(Color.textSecondary)
            Text(pattern.confidenceCountText)
                .font(.system(size: 13, weight: .medium, design: .default))
                .foregroundStyle(Color.textPrimary)
            Spacer()
        }
        .accessibilityLabel("\(pattern.confidenceQualifier), \(pattern.confidenceCountText)")
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
