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
        // Kiviniemi et al., Eur J Appl Physiol 2007;101:743–751.
        // "Endurance training guided individually by daily heart rate variability measurements"
        referenceURL: URL(string: "https://doi.org/10.1007/s00421-007-0552-2"),
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
        // Gabbett, Br J Sports Med 2016;50:273–280.
        // "The training—injury prevention paradox: should athletes be training smarter and harder?"
        referenceURL: URL(string: "https://doi.org/10.1136/bjsports-2015-095788"),
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
        // Simpson, Gibbs & Matheson, Scand J Med Sci Sports 2017;27:266–274.
        // "Optimizing sleep to maximize performance: implications and recommendations for elite athletes"
        referenceURL: URL(string: "https://doi.org/10.1111/sms.12703"),
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

    // MARK: Training Balance — Momma 2022
    // This signal measures the endurance / strength / mobility mix (see
    // BalancedTrainingAnalyzer), NOT periodisation or monotony. It previously
    // carried a tapering + monotony citation that described a metric this app
    // does not have — keep the citation topic matched to what the card measures.
    static let trainingBalance = ScienceCitation(
        signal: .trainingBalance,
        author: "Momma",
        year: 2022,
        finding: "Muscle-strengthening activity is associated with 10–17% lower risk of all-cause, cardiovascular and cancer mortality, independent of aerobic activity. Risk reduction peaks at roughly 30–60 min/week. Doing both muscle-strengthening and aerobic activity is associated with lower mortality than doing neither.",
        studyPopulation: "Systematic review and meta-analysis of 16 prospective cohort studies; adults 18+ without severe health conditions.",
        lowerBound: nil,
        upperBound: nil,
        dangerAbove: nil,
        optimalRange: nil,
        unit: "AU",
        // Momma, Kawakami, Honda & Sawada, Br J Sports Med 2022;56:755–763.
        // "Muscle-strengthening activities are associated with lower risk and
        //  mortality in major non-communicable diseases"
        referenceURL: URL(string: "https://doi.org/10.1136/bjsports-2021-105061"),
        lastVerified: 2026
    )
}
