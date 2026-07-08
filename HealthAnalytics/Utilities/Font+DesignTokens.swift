//
//  Font+DesignTokens.swift
//  HealthAnalytics
//
//  Design token Font extensions from DESIGN.md (Warm Signal system).
//  Never hardcode sizes — use these named tokens.
//

import SwiftUI

extension Font {

    // MARK: - Hero

    /// Readiness score. One per screen. SF Pro Rounded, 64pt Bold.
    static let heroNumeral = Font.system(size: 64, weight: .bold, design: .rounded)

    // MARK: - Headings

    /// Tab / screen-level headings ("Today", "Recovery", "Training"). SF Pro Display, 28pt Semibold.
    static let sectionTitle = Font.system(size: 28, weight: .semibold, design: .default)

    /// Card headers ("Health Signals", "Training Load"). SF Pro Text, 17pt Semibold.
    static let cardTitle = Font.system(size: 17, weight: .semibold, design: .default)

    // MARK: - Body

    /// Coaching voice — sentence-level recommendations. SF Pro Text, 15pt Regular.
    static let coachGuidance = Font.system(size: 15, weight: .regular, design: .default)

    // MARK: - Metrics

    /// Tile display values ("52ms", "7.4h", "1.04"). SF Pro Rounded, 22pt Bold.
    static let metricValue = Font.system(size: 22, weight: .bold, design: .rounded)

    // MARK: - Supporting

    /// Tile subtitles, chart axis labels, baseline callouts. SF Pro Text, 12pt Medium.
    static let labelCaption = Font.system(size: 12, weight: .medium, design: .default)

    /// Raw measurements, axis values, timestamps, ACWR decimals. SF Pro Mono, 11pt Regular.
    /// Reserved exclusively for raw data — signals to user "this is a number from your body."
    static let dataAxis = Font.system(size: 11, weight: .regular, design: .monospaced)
}
