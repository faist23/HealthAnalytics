//
//  Color+DesignTokens.swift
//  HealthAnalytics
//
//  Design token Color extensions from DESIGN.md (Warm Signal system).
//  Never use system defaults (Color.green, .blue, etc.) — use these tokens.
//

import SwiftUI

extension Color {

    // MARK: - Foundation (Dark Mode)

    /// App background — near-black with brown warmth (#0F0D0B)
    static let background = Color(hex: 0x0F0D0B)

    /// Cards, sheets, list rows (#1C1915)
    static let surface = Color(hex: 0x1C1915)

    /// Elevated sheets, modal backgrounds, separators (#262118)
    static let surfaceRaised = Color(hex: 0x262118)

    /// Main text — warm white, slight cream (#F2EDE6)
    static let textPrimary = Color(hex: 0xF2EDE6)

    /// Supporting text, labels, captions (#8C8078)
    static let textSecondary = Color(hex: 0x8C8078)

    /// Deemphasized text, axis labels, timestamps (#4D4540)
    static let textTertiary = Color(hex: 0x4D4540)

    // MARK: - Brand Accent

    /// Terracotta — score ring, CTA buttons, active tab indicator (#E8885A)
    static let accent = Color(hex: 0xE8885A)

    /// Accent tinted background for coach recommendation cards
    static let accentDim = Color(hex: 0xE8885A).opacity(0.12)

    /// Accent card border
    static let accentBorder = Color(hex: 0xE8885A).opacity(0.22)

    // MARK: - Semantic Status

    /// Bio-green — HRV above baseline, ACWR in sweet spot (#4ADE8F)
    static let statusOptimal = Color(hex: 0x4ADE8F)

    /// Sky blue — recovery mode, scheduled rest (#5BA8FF)
    static let statusRest = Color(hex: 0x5BA8FF)

    /// Amber — off-baseline, caution (#F5C842)
    static let statusMonitoring = Color(hex: 0xF5C842)

    /// Ember — high risk, significant deviation (#F07240)
    static let statusWarning = Color(hex: 0xF07240)

    /// Red — all-out effort, overreaching (#E53E3E)
    static let statusAllOut = Color(hex: 0xE53E3E)

    // MARK: - Private init

    /// Initialise from a 6-digit hex integer, e.g. `Color(hex: 0xE8885A)`.
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8)  & 0xFF) / 255.0
        let b = Double( hex        & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}
