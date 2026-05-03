//
//  Color+DesignTokens.swift
//  HealthAnalytics
//
//  Design token Color extensions from DESIGN.md (Signal Indigo system).
//  Never use system defaults (Color.green, .blue, etc.) — use these tokens.
//

import SwiftUI

extension Color {

    // MARK: - Foundation (Dark Mode)

    /// App background — cool near-black, indigo undertone (#09090E)
    static let background = Color(hex: 0x09090E)

    /// Cards, sheets, list rows (#0F0F18)
    static let surface = Color(hex: 0x0F0F18)

    /// Elevated sheets, modal backgrounds, separators (#1A1A2E)
    static let surfaceRaised = Color(hex: 0x1A1A2E)

    /// Main text — cool white, slight indigo cast (#EDEDFF)
    static let textPrimary = Color(hex: 0xEDEDFF)

    /// Supporting text, labels, captions (#8A8AA8)
    static let textSecondary = Color(hex: 0x8A8AA8)

    /// Deemphasized text, axis labels, timestamps (#4A4A65)
    static let textTertiary = Color(hex: 0x4A4A65)

    // MARK: - Brand Accent

    /// Electric violet — score ring, CTA buttons, active tab indicator (#7C5CFC)
    static let accent = Color(hex: 0x7C5CFC)

    /// Accent tinted background for coach recommendation cards
    static let accentDim = Color(hex: 0x7C5CFC).opacity(0.12)

    /// Accent card border
    static let accentBorder = Color(hex: 0x7C5CFC).opacity(0.22)

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
