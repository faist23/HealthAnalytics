//
//  CitationDatabase.swift
//  HealthAnalytics
//
//  Static O(1) registry of sport-science citations.
//  All thresholds cross-checked against CLAUDE.md mandates.
//
//  lastVerified: 2026 — review by 2028
//

import Foundation

enum CitationDatabase {

    /// Returns the science citation for a given signal, or nil for internal estimates.
    static func citation(for signal: SignalType) -> ScienceCitation? {
        switch signal {
        case .hrv:              return .hrv
        case .acwr:             return .acwr
        case .sleep:            return .sleep
        case .metMinutes:       return .metMinutes
        case .trainingBalance:  return .trainingBalance
        case .biologicalAge:    return nil   // internal model — no external citation
        }
    }

    /// Returns true when the citation is more than 2 years old and should be re-reviewed.
    static func isStale(_ citation: ScienceCitation) -> Bool {
        abs(Calendar.current.component(.year, from: Date()) - citation.lastVerified) > 2
    }
}

// MARK: - Citation Constants

private extension ScienceCitation {

    // MARK: HRV — Kiviniemi 2007
    // % deviation from personal 30-day baseline (not absolute ms).
    // Optimal band: −5% to +5%; caution outside −15% to +15%.
    static let hrv = ScienceCitation(
        signal: .hrv,
        author: "Kiviniemi",
        year: 2007,
        finding: "Day-to-day HRV fluctuates; ±5% from personal baseline is normal. > ±15% deviation indicates meaningful ANS stress or adaptation.",
        studyPopulation: "Endurance athletes, resting supine HRV. Baseline computed over prior 30 days.",
        lowerBound: -15.0,   // % — lower caution threshold
        upperBound: 15.0,    // % — upper caution threshold
        dangerAbove: nil,
        optimalRange: "−5% to +5%",
        unit: "% of baseline",
        referenceURL: URL(string: "https://doi.org/10.1007/s10286-007-0409-1"),
        lastVerified: 2026
    )

    // MARK: ACWR — Gabbett 2016
    // Cross-checked against CLAUDE.md: "ACWR sweet spot: 0.8–1.3"
    static let acwr = ScienceCitation(
        signal: .acwr,
        author: "Gabbett",
        year: 2016,
        finding: "ACWR 0.8–1.3 minimises injury risk. Athletes with ACWR > 1.5 are twice as likely to be injured in the next 1–2 weeks.",
        studyPopulation: "Elite rugby union and league players, multi-season tracking.",
        lowerBound: 0.8,
        upperBound: 1.3,
        dangerAbove: 1.5,
        optimalRange: "0.8 – 1.3",
        unit: "ratio",
        referenceURL: URL(string: "https://doi.org/10.1136/bjsports-2016-096308"),
        lastVerified: 2026
    )

    // MARK: Sleep — Simpson 2017
    static let sleep = ScienceCitation(
        signal: .sleep,
        author: "Simpson",
        year: 2017,
        finding: "7–9 hours of sleep optimises athletic performance, reaction time, and injury resistance. < 6 hours is associated with 1.7× injury risk.",
        studyPopulation: "Collegiate and professional athletes across multiple sports.",
        lowerBound: 7.0,    // hours
        upperBound: 9.0,
        dangerAbove: nil,
        optimalRange: "7 – 9 h",
        unit: "hours",
        referenceURL: URL(string: "https://doi.org/10.1249/JSR.0000000000000418"),
        lastVerified: 2026
    )

    // MARK: MET-minutes — WHO 2020
    // WHO 2020 does NOT cap benefit — no upper danger zone.
    // Three zones only: [0–149 insufficient][150–599 active][600+ optimal]
    static let metMinutes = ScienceCitation(
        signal: .metMinutes,
        author: "WHO",
        year: 2020,
        finding: "≥ 600 MET-min/week meets WHO physical activity guidelines. ≥ 1500 MET-min/week provides additional cardioprotective benefit with no documented upper harm threshold.",
        studyPopulation: "General adult population, global epidemiological review.",
        lowerBound: 150.0,   // min for 'active' zone
        upperBound: nil,     // WHO does not cap benefit
        dangerAbove: nil,
        optimalRange: "≥ 600 MET-min/week",
        unit: "MET-min/week",
        referenceURL: URL(string: "https://doi.org/10.1136/bjsports-2020-102955"),
        lastVerified: 2026
    )

    // MARK: Training Balance — Mujika & Padilla 2003 + Foster 1998
    static let trainingBalance = ScienceCitation(
        signal: .trainingBalance,
        author: "Mujika / Foster",
        year: 2003,
        finding: "Appropriate periodisation (build → peak → taper) maximises performance. Monotony index > 2.0 predicts overreaching and illness within 2 weeks.",
        studyPopulation: "Competitive endurance and team-sport athletes.",
        lowerBound: nil,
        upperBound: nil,
        dangerAbove: nil,
        optimalRange: nil,
        unit: "AU",
        referenceURL: URL(string: "https://doi.org/10.1249/01.MSS.0000078990.10047.1F"),
        lastVerified: 2026
    )
}
