//
//  TrainingPatternTimelineView.swift
//  HealthAnalytics
//
//  Phase 2 — Pattern Engine
//  44pt horizontal dot plot. Dots proportionally spaced by calendar distance.
//  Decorative only — not tappable.
//

import SwiftUI

struct TrainingPatternTimelineView: View {
    let pattern: TrainingPattern

    /// The analysis window spans 180 days back from today.
    private var windowStart: Date {
        Calendar.current.date(byAdding: .day, value: -180, to: Date()) ?? Date()
    }

    private var windowSpan: TimeInterval {
        max(Date().timeIntervalSince(windowStart), 1)
    }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                // Dot row (28pt) + axis line + labels (16pt) = 44pt total
                ZStack(alignment: .bottom) {
                    // Axis line
                    Rectangle()
                        .fill(Color.textTertiary)
                        .frame(height: 1)
                        .padding(.bottom, 15)

                    // 30-day tick marks
                    ForEach(tickOffsets(width: geo.size.width), id: \.self) { xOffset in
                        Rectangle()
                            .fill(Color.textTertiary)
                            .frame(width: 1, height: 4)
                            .offset(x: xOffset - geo.size.width / 2, y: -14)
                    }

                    // Dots — one per instance date, proportionally positioned
                    ForEach(Array(pattern.instanceDates.enumerated()), id: \.offset) { _, date in
                        Circle()
                            .fill(dotColor)
                            .frame(width: 8, height: 8)
                            .offset(x: xOffset(for: date, width: geo.size.width), y: -20)
                    }
                }
                .frame(height: 28)

                // Axis labels
                HStack {
                    Text("180d ago")
                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                        .foregroundStyle(Color.textTertiary)
                    Spacer()
                    Text("Now")
                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                        .foregroundStyle(Color.textTertiary)
                }
                .frame(height: 16)
            }
        }
        .frame(height: 44)
        .accessibilityLabel(accessibilityDescription)
    }

    // MARK: - Layout Helpers

    private func xOffset(for date: Date, width: CGFloat) -> CGFloat {
        let elapsed = date.timeIntervalSince(windowStart)
        let fraction = CGFloat(elapsed / windowSpan).clamped(to: 0...1)
        return (fraction - 0.5) * width
    }

    private func tickOffsets(width: CGFloat) -> [CGFloat] {
        let thirtyDays: TimeInterval = 30 * 86400
        var offsets: [CGFloat] = []
        var t = windowStart
        while t < Date() {
            let elapsed = t.timeIntervalSince(windowStart)
            let fraction = CGFloat(elapsed / windowSpan).clamped(to: 0...1)
            offsets.append(fraction * width)
            t = t.addingTimeInterval(thirtyDays)
        }
        return offsets
    }

    // MARK: - Color

    private var dotColor: Color {
        let ratio = pattern.confidenceDenominator > 0
            ? Double(pattern.confidenceNumerator) / Double(pattern.confidenceDenominator)
            : 0
        if pattern.confidenceNumerator <= 3 { return Color.textTertiary }
        if ratio >= 0.75 { return Color.accent }
        return Color.statusMonitoring
    }

    // MARK: - Accessibility

    private var accessibilityDescription: String {
        let count = pattern.instanceDates.count
        return "\(count) instance\(count == 1 ? "" : "s") of \(pattern.patternType.displayName) over the past 180 days."
    }
}

// MARK: - Clamp helper

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
