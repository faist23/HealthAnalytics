//
//  Spacing+DesignTokens.swift
//  HealthAnalytics
//
//  Design token spacing values from DESIGN.md (Warm Signal system).
//  Base unit: 8pt iOS grid.
//

import CoreFoundation

extension CGFloat {

    // MARK: - Spacing Scale

    /// 4pt — tight internal gaps (icon + label, badge dot + text)
    static let spacingXs: CGFloat = 4

    /// 8pt — default internal padding, stack spacing
    static let spacingSm: CGFloat = 8

    /// 16pt — card internal padding, section spacing
    static let spacingMd: CGFloat = 16

    /// 24pt — between cards, section gaps
    static let spacingLg: CGFloat = 24

    /// 32pt — major section separators
    static let spacingXl: CGFloat = 32

    /// 48pt — hero section vertical breathing room
    static let spacing2Xl: CGFloat = 48
}
