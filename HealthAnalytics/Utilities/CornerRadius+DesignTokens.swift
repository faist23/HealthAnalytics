//
//  CornerRadius+DesignTokens.swift
//  HealthAnalytics
//
//  Design token corner-radius values from DESIGN.md (Warm Signal system).
//  Never hardcode radius values — use these named tokens.
//

import CoreFoundation

extension CGFloat {

    // MARK: - Border Radius Scale

    /// Small elements: badges, status pills, tags — 8pt
    static let radiusSm: CGFloat = 8

    /// Cards, tiles, buttons — 16pt
    static let radiusMd: CGFloat = 16

    /// Large sheets, bottom sheets, modal containers — 24pt
    static let radiusLg: CGFloat = 24

    /// Pills, circular elements — 9999pt
    static let radiusFull: CGFloat = 9999
}
