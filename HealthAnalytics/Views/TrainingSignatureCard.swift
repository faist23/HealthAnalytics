//
//  TrainingSignatureCard.swift
//  HealthAnalytics
//
//  Phase 2b — 14-Day Signature Pattern Card
//  Shows the user's back-to-back crash pattern with a spaghetti sparkline,
//  stat chips, and a tappable detail sheet.
//
//  Design: Warm Signal system — Color.surface card, Color.accent sparkline avg,
//  Color.textTertiary individual session lines.
//

import SwiftUI
import SwiftData

// MARK: - Main Card

struct TrainingSignatureCard: View {
    @Query private var allPatterns: [TrainingPattern]
    @Query private var allScores: [StoredDailyScore]
    @ObservedObject private var repo = ReadinessRepository.shared

    @State private var showDetail = false

    private var signature: TrainingPattern? {
        allPatterns.first { $0.patternType == .backToBackCrash }
    }

    private var historyDays: Int {
        UserDefaults.standard.integer(forKey: "healthKitHistoryDays")
    }

    var body: some View {
        Group {
            if repo.isAnalyzing && signature == nil {
                loadingState
            } else if historyDays < 90 {
                insufficientHistoryState
            } else if signature == nil {
                insufficientSequencesState
            } else if let pattern = signature {
                confirmedCard(pattern: pattern)
                    .onTapGesture { showDetail = true }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(accessibilityLabel(for: pattern))
                    .accessibilityHint("Double-tap to explore your pattern")
                    .sheet(isPresented: $showDetail) {
                        SignatureDetailSheet(pattern: pattern, allScores: allScores)
                    }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: signature != nil)
    }

    // MARK: - States

    private var loadingState: some View {
        RoundedRectangle(cornerRadius: .radiusMd)
            .fill(Color.surface)
            .frame(height: 160)
            .overlay(
                ProgressView()
                    .tint(Color.accent)
            )
            .padding(.horizontal)
    }

    private var insufficientHistoryState: some View {
        VStack(spacing: .spacingMd) {
            Image(systemName: "lock.fill")
                .font(.system(size: 24))
                .foregroundStyle(Color.textTertiary)
            Text("14-Day Signature")
                .font(.cardTitle)
                .foregroundStyle(Color.textPrimary)
            Text("Needs 90 days of training history to detect your crash pattern.")
                .font(.coachGuidance)
                .foregroundStyle(Color.textTertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.spacingLg)
        .frame(maxWidth: .infinity)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: .radiusMd))
        .padding(.horizontal)
    }

    private var insufficientSequencesState: some View {
        VStack(spacing: .spacingMd) {
            Image(systemName: "bolt.horizontal.fill")
                .font(.system(size: 24))
                .foregroundStyle(Color.textTertiary)
            Text("14-Day Signature")
                .font(.cardTitle)
                .foregroundStyle(Color.textPrimary)
            Text("Not enough back-to-back training sequences detected yet. Keep logging workouts.")
                .font(.coachGuidance)
                .foregroundStyle(Color.textTertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.spacingLg)
        .frame(maxWidth: .infinity)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: .radiusMd))
        .padding(.horizontal)
    }

    // MARK: - Confirmed Card

    @ViewBuilder
    private func confirmedCard(pattern: TrainingPattern) -> some View {
        let trajectories = buildTrajectories(from: pattern)
        let avgDrop = computeAvgDrop(trajectories: trajectories)

        VStack(alignment: .leading, spacing: .spacingMd) {
            // Header
            HStack(spacing: .spacingSm) {
                Image(systemName: "bolt.horizontal.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.accent)
                Text("14-DAY SIGNATURE")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.textTertiary)
                    .tracking(1)
                Spacer()
                if pattern.isNewlyDetected {
                    Text("NEW")
                        .font(.system(size: 10, weight: .heavy, design: .monospaced))
                        .foregroundStyle(Color.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accent.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                }
            }

            // Stat Chips
            HStack(spacing: .spacingSm) {
                // CONFIRMED chip (wider, statusOptimal border)
                StatChip(
                    value: "\(pattern.confidenceNumerator)/\(pattern.confidenceDenominator)",
                    label: "CONFIRMED",
                    borderColor: Color.statusOptimal,
                    flex: 2
                )
                // AVG DROP chip
                StatChip(
                    value: avgDrop > 0 ? "-\(Int(avgDrop.rounded()))pts" : "--",
                    label: "AVG DROP",
                    borderColor: Color.surfaceRaised,
                    flex: 1
                )
                // LAG CORR chip (monospaced, accent)
                if let r = pattern.lagCorrelation {
                    StatChip(
                        value: String(format: "r=%.2f", r),
                        label: "LAG CORR",
                        borderColor: Color.surfaceRaised,
                        valueColor: Color.accent,
                        useMonospaced: true,
                        flex: 1
                    )
                }
            }

            // Sparkline
            if !trajectories.isEmpty {
                SignatureSparkline(trajectories: trajectories)
                    .frame(height: 72)
                    .padding(.vertical, .spacingXs)
            }

            Divider().background(Color.surfaceRaised)

            // Coaching response
            Text(pattern.coachingResponse)
                .font(.coachGuidance)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            // Tap hint
            HStack {
                Spacer()
                Text("EXPLORE PATTERN")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.accent)
                    .tracking(1)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.accent)
            }
        }
        .padding(.spacingMd)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: .radiusMd))
        .overlay(
            RoundedRectangle(cornerRadius: .radiusMd)
                .stroke(Color.accentBorder, lineWidth: 1)
        )
        .padding(.horizontal)
    }

    // MARK: - Trajectory Data

    /// Builds 4-point readiness trajectories: [day-2, day-1, crashDay, day+1]
    /// normalized 0–1 (score / 100). Returns only sequences with all 4 points available.
    private func buildTrajectories(from pattern: TrainingPattern) -> [[Double]] {
        let scoreByDay = Dictionary(
            uniqueKeysWithValues: allScores.map { (dayKey($0.date), $0.readinessScore) }
        )
        let calendar = Calendar.current
        var result: [[Double]] = []

        for crashDate in pattern.instanceDates {
            guard
                let dm2 = calendar.date(byAdding: .day, value: -2, to: crashDate),
                let dm1 = calendar.date(byAdding: .day, value: -1, to: crashDate),
                let dp1 = calendar.date(byAdding: .day, value: 1, to: crashDate),
                let s0 = scoreByDay[dayKey(dm2)],
                let s1 = scoreByDay[dayKey(dm1)],
                let s2 = scoreByDay[dayKey(crashDate)],
                let s3 = scoreByDay[dayKey(dp1)]
            else { continue }

            result.append([
                Double(s0) / 100.0,
                Double(s1) / 100.0,
                Double(s2) / 100.0,
                Double(s3) / 100.0
            ])
        }
        return result
    }

    private func computeAvgDrop(trajectories: [[Double]]) -> Double {
        guard !trajectories.isEmpty else { return 0 }
        // Drop = day-1 score minus crash day score
        let drops = trajectories.compactMap { t -> Double? in
            guard t.count >= 3 else { return nil }
            let drop = (t[1] - t[2]) * 100.0   // convert back to readiness points
            return drop > 0 ? drop : nil
        }
        guard !drops.isEmpty else { return 0 }
        return drops.reduce(0, +) / Double(drops.count)
    }

    private func dayKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone.current
        return f.string(from: date)
    }

    private func accessibilityLabel(for pattern: TrainingPattern) -> String {
        let avgDrop = computeAvgDrop(trajectories: buildTrajectories(from: pattern))
        return "Training signature pattern. \(pattern.confidenceNumerator) of \(pattern.confidenceDenominator) sequences confirmed. Average readiness drop: \(Int(avgDrop.rounded())) points."
    }
}

// MARK: - Stat Chip

private struct StatChip: View {
    let value: String
    let label: String
    let borderColor: Color
    var valueColor: Color = Color.textPrimary
    var useMonospaced: Bool = false
    var flex: Int = 1

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(useMonospaced
                    ? .system(size: 15, weight: .bold, design: .monospaced)
                    : .system(size: 15, weight: .bold))
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color.textTertiary)
                .tracking(0.5)
        }
        .padding(.horizontal, .spacingSm)
        .padding(.vertical, .spacingXs)
        .frame(maxWidth: .infinity)
        .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: .radiusSm))
        .overlay(
            RoundedRectangle(cornerRadius: .radiusSm)
                .stroke(borderColor, lineWidth: 1)
        )
    }
}

// MARK: - Sparkline

private struct SignatureSparkline: View {
    let trajectories: [[Double]]   // Each: 4 points, 0–1 normalized readiness

    private var avgTrajectory: [Double] {
        guard !trajectories.isEmpty else { return [] }
        let count = trajectories[0].count
        return (0..<count).map { i in
            trajectories.compactMap { $0.count > i ? $0[i] : nil }
                .reduce(0, +) / Double(trajectories.count)
        }
    }

    var body: some View {
        Canvas { ctx, size in
            // Individual session lines
            for trajectory in trajectories {
                let path = makePath(trajectory, in: size)
                ctx.stroke(path, with: .color(Color.textTertiary.opacity(0.5)), lineWidth: 0.8)
            }
            // Average line
            if !avgTrajectory.isEmpty {
                let path = makePath(avgTrajectory, in: size)
                ctx.stroke(path, with: .color(Color.accent), lineWidth: 2.5)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: .radiusSm))
        .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: .radiusSm))
    }

    private func makePath(_ points: [Double], in size: CGSize) -> Path {
        guard points.count >= 2 else { return Path() }
        let xStep = size.width / Double(points.count - 1)
        var path = Path()
        path.move(to: CGPoint(x: 0, y: (1.0 - points[0]) * Double(size.height)))
        for i in 1..<points.count {
            path.addLine(to: CGPoint(
                x: Double(i) * xStep,
                y: (1.0 - points[i]) * Double(size.height)
            ))
        }
        return path
    }
}

// MARK: - Detail Sheet

struct SignatureDetailSheet: View {
    let pattern: TrainingPattern
    let allScores: [StoredDailyScore]

    @Environment(\.dismiss) private var dismiss
    @State private var showCitationSheet = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: .spacingLg) {
                    // Pattern definition
                    VStack(alignment: .leading, spacing: .spacingSm) {
                        Text("WHAT'S HAPPENING")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.textTertiary)
                            .tracking(1)
                        Text(pattern.evidenceSummary)
                            .font(.coachGuidance)
                            .foregroundStyle(Color.textPrimary)
                    }
                    .padding(.spacingMd)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.surface, in: RoundedRectangle(cornerRadius: .radiusMd))

                    // Stats
                    VStack(alignment: .leading, spacing: .spacingSm) {
                        Text("STATISTICS")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.textTertiary)
                            .tracking(1)
                        HStack(spacing: .spacingMd) {
                            DetailStatRow(label: "Sequences confirmed",
                                          value: "\(pattern.confidenceNumerator) of \(pattern.confidenceDenominator)")
                            if let r = pattern.lagCorrelation {
                                DetailStatRow(label: "Lag correlation (r)",
                                              value: String(format: "%.2f", r))
                            }
                            if let peakDay = pattern.peakDropDay {
                                DetailStatRow(label: "Peak crash",
                                              value: "Day +\(peakDay)")
                            }
                        }
                    }
                    .padding(.spacingMd)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.surface, in: RoundedRectangle(cornerRadius: .radiusMd))

                    // TODAY footer — only if pattern detected recently
                    if pattern.isNewlyDetected {
                        VStack(alignment: .leading, spacing: .spacingSm) {
                            Text("TODAY")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color.statusWarning)
                                .tracking(1)
                            Text("This pattern was detected recently. Consider today a recovery day if you trained hard yesterday.")
                                .font(.coachGuidance)
                                .foregroundStyle(Color.textSecondary)
                        }
                        .padding(.spacingMd)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.surface, in: RoundedRectangle(cornerRadius: .radiusMd))
                        .overlay(
                            RoundedRectangle(cornerRadius: .radiusMd)
                                .stroke(Color.statusWarning.opacity(0.3), lineWidth: 1)
                        )
                    }

                    // What to do
                    VStack(alignment: .leading, spacing: .spacingSm) {
                        Text("WHAT TO DO")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.textTertiary)
                            .tracking(1)
                        Text(pattern.coachingResponse)
                            .font(.coachGuidance)
                            .foregroundStyle(Color.textPrimary)
                    }
                    .padding(.spacingMd)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.surface, in: RoundedRectangle(cornerRadius: .radiusMd))

                    // Science section
                    Button { showCitationSheet = true } label: {
                        VStack(alignment: .leading, spacing: .spacingSm) {
                            Text("SCIENCE")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color.textTertiary)
                                .tracking(1)
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Gabbett TJ, 2016")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(Color.textPrimary)
                                    Text("The training-injury prevention paradox: should athletes train smarter and harder?")
                                        .font(.system(size: 12))
                                        .foregroundStyle(Color.textSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text("Br J Sports Med · doi:10.1136/bjsports-2016-096308")
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(Color.textTertiary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.textTertiary)
                            }
                        }
                        .padding(.spacingMd)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.surface, in: RoundedRectangle(cornerRadius: .radiusMd))
                    }
                    .buttonStyle(.plain)
                }
                .padding()
            }
            .background(Color(white: 0.05).ignoresSafeArea())
            .navigationTitle("14-Day Signature")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .sheet(isPresented: $showCitationSheet) {
            CitationDetailSheet()
        }
    }
}

// MARK: - Detail Stat Row

private struct DetailStatRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Color.textTertiary)
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Citation Detail Sheet

private struct CitationDetailSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: .spacingLg) {
                    VStack(alignment: .leading, spacing: .spacingSm) {
                        Text("Gabbett TJ")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Color.textPrimary)
                        Text("2016 · British Journal of Sports Medicine")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.textSecondary)
                        Text("The training-injury prevention paradox: should athletes train smarter and harder?")
                            .font(.system(size: 15))
                            .foregroundStyle(Color.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 4)
                    }

                    Divider().background(Color.surfaceRaised)

                    VStack(alignment: .leading, spacing: .spacingSm) {
                        Text("FINDING")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.textTertiary)
                            .tracking(1)
                        Text("ACWR 0.8–1.3 minimises injury risk. Athletes with ACWR > 1.5 are twice as likely to be injured in the next 1–2 weeks.")
                            .font(.coachGuidance)
                            .foregroundStyle(Color.textPrimary)
                    }

                    VStack(alignment: .leading, spacing: .spacingSm) {
                        Text("HOW IT APPLIES")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.textTertiary)
                            .tracking(1)
                        Text("Your 14-Day Signature pattern is the personal expression of this principle. The crash you see after back-to-back sessions is acute load exceeding your chronic base — your body's signal to pace the ramp.")
                            .font(.coachGuidance)
                            .foregroundStyle(Color.textPrimary)
                    }

                    Text("doi:10.1136/bjsports-2016-096308")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Color.textTertiary)
                }
                .padding()
            }
            .background(Color(white: 0.05).ignoresSafeArea())
            .navigationTitle("Science")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
