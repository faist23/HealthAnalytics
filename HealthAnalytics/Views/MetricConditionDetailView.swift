//
//  MetricConditionDetailView.swift
//  HealthAnalytics
//
//  Extracted from SupportingMetricsCard. Takes MetricDisplayConfig (not
//  SupportingMetricsCard.SelectedMetric) so it has no backwards dependency.
//
//  Sheet layout order:
//    1. Header (icon + current value + status badge)
//    2. ResearchThresholdBar      ← only when citation has scalar thresholds
//    3. WHY THIS STATUS?
//    4. RESEARCH BASIS            ← if science citation exists
//       OR ML ESTIMATE CARD       ← if citation is nil (estimate tile)
//    5. COACH'S GUIDANCE
//

import SwiftUI

// MARK: - MetricDisplayConfig

/// All display properties needed by MetricConditionDetailView.
/// Created at the sheet call site in SupportingMetricsCard.
struct MetricDisplayConfig: Identifiable {
    let id: String              // e.g. "hrv", "acwr"
    let title: String
    let icon: String
    let currentValueFormatted: String
    let status: MetricStatus
    let citation: ScienceCitation?
    /// Pre-computed value in the citation's native unit (for ResearchThresholdBar).
    let thresholdBarValue: Double?
    let conditionReasoning: String
    let guidanceText: String
    let detailedInsight: String?
    /// Whether this tile is an ML estimate (shows estimate card instead of research basis).
    var badgeType: ScienceBadgeType = .none
    /// True when multiple HealthKit sources are writing HRV and data is being blended.
    var isBlendedHRVSource: Bool = false
}

// MARK: - MetricConditionDetailView

struct MetricConditionDetailView: View {
    let config: MetricDisplayConfig
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {

                    // 1. HEADER
                    HStack(spacing: 20) {
                        Image(systemName: config.icon)
                            .font(.system(size: 44))
                            .foregroundStyle(config.status.color)
                            .frame(width: 60, height: 60)
                            .background(config.status.color.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 12))

                        VStack(alignment: .leading, spacing: .spacingXs) {
                            Text(config.title)
                                .font(.headline)
                                .foregroundStyle(Color.textSecondary)

                            HStack(alignment: .firstTextBaseline, spacing: .spacingXs) {
                                Text(config.currentValueFormatted)
                                    .font(.system(size: 32, weight: .bold, design: .rounded))
                                    .foregroundStyle(Color.textPrimary)

                                Text(config.status.label.uppercased())
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .padding(.horizontal, .spacingSm)
                                    .padding(.vertical, 2)
                                    .background(config.status.color.opacity(0.2))
                                    .foregroundStyle(config.status.color)
                                    .clipShape(Capsule())
                            }

                            if config.isBlendedHRVSource {
                                Text("Multiple sources detected")
                                    .font(.dataAxis)
                                    .foregroundStyle(Color.textSecondary)
                            }
                        }
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.top, 10)

                    // 2. RESEARCH THRESHOLD BAR
                    // Only shown when citation has scalar thresholds (not trainingBalance/estimate).
                    if let citation = config.citation,
                       citation.lowerBound != nil || citation.dangerAbove != nil {
                        VStack(alignment: .leading, spacing: .spacingSm) {
                            ResearchThresholdBar(
                                citation: citation,
                                currentValue: config.thresholdBarValue
                            )
                        }
                        .padding(.horizontal)
                    }

                    // 3. WHY THIS STATUS?
                    VStack(alignment: .leading, spacing: .spacingSm) {
                        HStack {
                            Image(systemName: "info.circle.fill")
                                .font(.caption)
                            Text("WHY THIS STATUS?")
                                .font(.caption)
                                .fontWeight(.bold)
                        }
                        .foregroundStyle(config.status.color)

                        Text(config.conditionReasoning)
                            .font(.subheadline)
                            .foregroundStyle(Color.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12).fill(config.status.color.opacity(0.05)))
                    .padding(.horizontal)

                    // 4a. RESEARCH BASIS (science citation)
                    if let citation = config.citation {
                        researchBasisSection(citation: citation)
                    }

                    // 4b. ML ESTIMATE CARD (when no external citation)
                    if config.citation == nil && config.badgeType == .estimate {
                        mlEstimateSection
                    }

                    // 5. COACH'S GUIDANCE
                    VStack(alignment: .leading, spacing: .spacingSm) {
                        HStack {
                            Image(systemName: "bolt.fill")
                                .font(.caption)
                            Text("COACH'S GUIDANCE")
                                .font(.caption)
                                .fontWeight(.bold)
                        }
                        .foregroundStyle(Color.textPrimary)

                        Text(config.guidanceText)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(Color.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.surface))
                    .padding(.horizontal)

                    // Optional detailed footnote
                    if let detail = config.detailedInsight {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                            .padding(.horizontal, .spacingLg)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle(config.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Research Basis Section

    @ViewBuilder
    private func researchBasisSection(citation: ScienceCitation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "book.fill")
                    .font(.caption)
                Text("RESEARCH BASIS")
                    .font(.caption)
                    .fontWeight(.bold)
            }
            .foregroundStyle(Color.statusRest)

            VStack(alignment: .leading, spacing: .spacingXs) {
                // Author · Year · Finding
                Text("\(citation.author) \(String(citation.year))")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.textPrimary)

                Text(citation.finding)
                    .font(.subheadline)
                    .foregroundStyle(Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                // Study population caveat
                Text(citation.studyPopulation)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .padding(.top, 2)

                // Verified year
                Text("Verified \(String(citation.lastVerified))")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
            }

            // [View source ↗]
            if let url = citation.referenceURL {
                Link(destination: url) {
                    HStack(spacing: .spacingXs) {
                        Text("View source")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                    }
                    .foregroundStyle(Color.statusRest)
                    .frame(minHeight: 44)   // 44pt touch target
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.statusRest.opacity(0.06)))
        .padding(.horizontal)
    }

    // MARK: - ML Estimate Section

    private var mlEstimateSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "cpu.fill")
                    .font(.caption)
                Text("ML ESTIMATE")
                    .font(.caption)
                    .fontWeight(.bold)
            }
            .foregroundStyle(Color.statusMonitoring)

            Text("This value is predicted by an on-device ML model trained on your personal HRV, sleep, and training history. It improves with more data and does not rely on external research benchmarks.")
                .font(.subheadline)
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.statusMonitoring.opacity(0.06)))
        .padding(.horizontal)
    }
}
