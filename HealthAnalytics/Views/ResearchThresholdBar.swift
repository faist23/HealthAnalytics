//
//  ResearchThresholdBar.swift
//  HealthAnalytics
//
//  Population-curve threshold bar for MetricConditionDetailView.
//  Renders colored zone segments with a vertical position marker.
//
//  Zone logic is extracted into a static func for unit testing:
//    ResearchThresholdBar.zone(for: value, citation: citation) -> ZoneInfo
//

import SwiftUI

// MARK: - Zone Info

struct ZoneInfo: Equatable {
    enum ZoneLabel: String, Equatable {
        case insufficient       // < lower caution
        case optimal            // within optimal band
        case monitoring         // above optimal but below danger
        case danger             // above danger threshold
        case insufficientData   // nil currentValue
    }

    let label: ZoneLabel
    let color: Color
    let isClamped: Bool   // marker pinned at bar edge because value exceeds max zone

    static let insufficientData = ZoneInfo(label: .insufficientData, color: .textTertiary, isClamped: false)
}

// MARK: - ResearchThresholdBar

struct ResearchThresholdBar: View {

    let citation: ScienceCitation
    /// Pre-computed value in the citation's native unit.
    /// Pass nil when data is insufficient to show a position.
    let currentValue: Double?

    // MARK: Static zone function (testable)

    /// Maps a numeric value to its ZoneInfo using the citation's thresholds.
    static func zone(for value: Double?, citation: ScienceCitation) -> ZoneInfo {
        guard let value else { return .insufficientData }

        switch citation.signal {
        case .acwr:
            return acwrZone(value: value, citation: citation)
        case .hrv:
            return hrvZone(value: value, citation: citation)
        case .sleep:
            return sleepZone(value: value, citation: citation)
        case .metMinutes:
            return metZone(value: value)
        default:
            return symmetricZone(value: value, citation: citation)
        }
    }

    // MARK: Body

    var body: some View {
        let info = Self.zone(for: currentValue, citation: citation)

        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .leading) {
                segmentedBar
                if currentValue != nil {
                    marker(zone: info)
                }
            }
            .frame(height: 8)
            .clipShape(Capsule())

            zoneLabelRow

            if currentValue == nil {
                Text("Insufficient data")
                    .font(.caption2)
                    .foregroundStyle(Color.textSecondary)
            }
        }
    }

    // MARK: - Private Helpers

    private var segmentedBar: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(segments, id: \.label.rawValue) { seg in
                    Rectangle()
                        .fill(seg.color.opacity(0.7))
                        .frame(width: geo.size.width * seg.fraction - 2)
                }
            }
        }
    }

    private func marker(zone: ZoneInfo) -> some View {
        GeometryReader { geo in
            let fraction = markerFraction(barWidth: geo.size.width)
            Rectangle()
                .fill(Color.textPrimary)
                .frame(width: 3, height: 14)
                .offset(x: fraction * geo.size.width - 1.5, y: -3)
        }
    }

    private var zoneLabelRow: some View {
        HStack {
            ForEach(segments, id: \.label.rawValue) { seg in
                Text(seg.shortLabel)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Color.textSecondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: Segments per signal

    private struct Segment {
        let label: ZoneInfo.ZoneLabel
        let color: Color
        let fraction: Double   // proportional width of bar
        let shortLabel: String
    }

    private var segments: [Segment] {
        switch citation.signal {
        case .acwr:
            // [0–0.8 blue · under-training][0.8–1.3 green · optimal][1.3–1.5 amber][1.5–2.0 orange · danger]
            return [
                Segment(label: .insufficient,  color: .statusRest,      fraction: 0.22, shortLabel: "< 0.8"),
                Segment(label: .optimal,       color: .statusOptimal,   fraction: 0.36, shortLabel: "0.8–1.3"),
                Segment(label: .monitoring,    color: .statusMonitoring, fraction: 0.14, shortLabel: "1.3–1.5"),
                Segment(label: .danger,        color: .statusWarning,   fraction: 0.28, shortLabel: "≥ 1.5")
            ]
        case .hrv:
            // [< -15% red][−15%–−5% yellow][−5%–+5% green][+5%–+15% blue][>+15% yellow]
            return [
                Segment(label: .insufficient,  color: .statusWarning,   fraction: 0.20, shortLabel: "< −15%"),
                Segment(label: .monitoring,    color: .statusMonitoring, fraction: 0.20, shortLabel: "−15..−5%"),
                Segment(label: .optimal,       color: .statusOptimal,   fraction: 0.20, shortLabel: "−5..+5%"),
                Segment(label: .monitoring,    color: .statusRest,      fraction: 0.20, shortLabel: "+5..+15%"),
                Segment(label: .monitoring,    color: .statusMonitoring, fraction: 0.20, shortLabel: "> +15%")
            ]
        case .sleep:
            // [< 6h red][6–7h yellow][7–9h green][> 9h yellow]
            return [
                Segment(label: .insufficient,  color: .statusWarning,   fraction: 0.20, shortLabel: "< 6h"),
                Segment(label: .monitoring,    color: .statusMonitoring, fraction: 0.20, shortLabel: "6–7h"),
                Segment(label: .optimal,       color: .statusOptimal,   fraction: 0.40, shortLabel: "7–9h"),
                Segment(label: .monitoring,    color: .statusMonitoring, fraction: 0.20, shortLabel: "> 9h")
            ]
        case .metMinutes:
            // [0–149 red][150–599 yellow][600+ green] — WHO: no upper cap
            return [
                Segment(label: .insufficient,  color: .statusWarning,   fraction: 0.15, shortLabel: "< 150"),
                Segment(label: .monitoring,    color: .statusMonitoring, fraction: 0.35, shortLabel: "150–599"),
                Segment(label: .optimal,       color: .statusOptimal,   fraction: 0.50, shortLabel: "≥ 600")
            ]
        default:
            // Symmetric 3-zone from lowerBound/upperBound
            return [
                Segment(label: .insufficient,  color: .statusWarning,   fraction: 0.25, shortLabel: "Low"),
                Segment(label: .optimal,       color: .statusOptimal,   fraction: 0.50, shortLabel: "Optimal"),
                Segment(label: .monitoring,    color: .statusMonitoring, fraction: 0.25, shortLabel: "High")
            ]
        }
    }

    // MARK: Marker position

    private func markerFraction(barWidth: Double) -> Double {
        guard let value = currentValue else { return 0 }

        switch citation.signal {
        case .acwr:
            // Scale: 0 → 0, 2.0 → 1.0 (clamped)
            let clamped = min(value, 2.0)
            return min(max(clamped / 2.0, 0), 1.0)
        case .hrv:
            // Scale: −30% → 0, +30% → 1.0 (clamped)
            let shifted = value + 30.0
            let clamped = min(max(shifted, 0), 60.0)
            return clamped / 60.0
        case .sleep:
            // Scale: 0h → 0, 12h → 1.0 (clamped)
            let clamped = min(value, 12.0)
            return clamped / 12.0
        case .metMinutes:
            // Scale: 0 → 0, 1500+ → 1.0 (clamped at 1500 — no upper harm)
            let clamped = min(value, 1500.0)
            return clamped / 1500.0
        default:
            guard let lower = citation.lowerBound, let upper = citation.upperBound else { return 0.5 }
            let range = (upper - lower) * 2
            let shifted = value - (lower - (upper - lower) / 2)
            return min(max(shifted / range, 0), 1.0)
        }
    }
}

// MARK: - Zone Helpers (private static)

private extension ResearchThresholdBar {

    static func acwrZone(value: Double, citation: ScienceCitation) -> ZoneInfo {
        let lower = citation.lowerBound ?? 0.8
        let upper = citation.upperBound ?? 1.3
        let danger = citation.dangerAbove ?? 1.5
        let isClamped = value >= 2.0

        if value < lower {
            // Under-training zone uses sky blue (statusRest) — per DESIGN.md grey/blue semantics
            return ZoneInfo(label: .insufficient, color: .statusRest, isClamped: false)
        } else if value <= upper {
            return ZoneInfo(label: .optimal, color: .statusOptimal, isClamped: false)
        } else if value < danger {
            return ZoneInfo(label: .monitoring, color: .statusMonitoring, isClamped: false)
        } else {
            return ZoneInfo(label: .danger, color: .statusWarning, isClamped: isClamped)
        }
    }

    static func hrvZone(value: Double, citation: ScienceCitation) -> ZoneInfo {
        // value is % deviation from baseline: negative = below, positive = above
        if value < -15.0 {
            return ZoneInfo(label: .insufficient, color: .statusWarning, isClamped: value < -30)
        } else if value < -5.0 {
            return ZoneInfo(label: .monitoring, color: .statusMonitoring, isClamped: false)
        } else if value <= 5.0 {
            return ZoneInfo(label: .optimal, color: .statusOptimal, isClamped: false)
        } else if value <= 15.0 {
            return ZoneInfo(label: .monitoring, color: .statusRest, isClamped: false)
        } else {
            return ZoneInfo(label: .monitoring, color: .statusMonitoring, isClamped: value > 30)
        }
    }

    static func sleepZone(value: Double, citation: ScienceCitation) -> ZoneInfo {
        if value < 6.0 {
            return ZoneInfo(label: .insufficient, color: .statusWarning, isClamped: false)
        } else if value < 7.0 {
            return ZoneInfo(label: .monitoring, color: .statusMonitoring, isClamped: false)
        } else if value <= 9.0 {
            return ZoneInfo(label: .optimal, color: .statusOptimal, isClamped: false)
        } else {
            return ZoneInfo(label: .monitoring, color: .statusMonitoring, isClamped: false)
        }
    }

    static func metZone(value: Double) -> ZoneInfo {
        // WHO 2020: no upper cap — 1500+ is still optimal (not caution)
        if value < 150.0 {
            return ZoneInfo(label: .insufficient, color: .statusWarning, isClamped: false)
        } else if value < 600.0 {
            return ZoneInfo(label: .monitoring, color: .statusMonitoring, isClamped: false)
        } else {
            return ZoneInfo(label: .optimal, color: .statusOptimal, isClamped: false)
        }
    }

    static func symmetricZone(value: Double, citation: ScienceCitation) -> ZoneInfo {
        guard let lower = citation.lowerBound, let upper = citation.upperBound else {
            return .insufficientData
        }
        if value < lower {
            return ZoneInfo(label: .insufficient, color: .statusWarning, isClamped: false)
        } else if value <= upper {
            return ZoneInfo(label: .optimal, color: .statusOptimal, isClamped: false)
        } else {
            return ZoneInfo(label: .monitoring, color: .statusMonitoring, isClamped: value > upper * 1.5)
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    VStack(spacing: 24) {
        Group {
            Text("ACWR 1.4 (monitoring)").font(.caption).foregroundStyle(Color.textSecondary)
            if let c = CitationDatabase.citation(for: .acwr) {
                ResearchThresholdBar(citation: c, currentValue: 1.4)
            }

            Text("Sleep 7.5h (optimal)").font(.caption).foregroundStyle(Color.textSecondary)
            if let c = CitationDatabase.citation(for: .sleep) {
                ResearchThresholdBar(citation: c, currentValue: 7.5)
            }

            Text("MET-min 2000 (optimal — no cap)").font(.caption).foregroundStyle(Color.textSecondary)
            if let c = CitationDatabase.citation(for: .metMinutes) {
                ResearchThresholdBar(citation: c, currentValue: 2000)
            }

            Text("No data").font(.caption).foregroundStyle(Color.textSecondary)
            if let c = CitationDatabase.citation(for: .acwr) {
                ResearchThresholdBar(citation: c, currentValue: nil)
            }
        }
    }
    .padding()
    .background(Color.background)
}
#endif
