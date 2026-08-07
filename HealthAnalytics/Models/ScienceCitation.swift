//
//  ScienceCitation.swift
//  HealthAnalytics
//
//  Plain-Swift structs — NOT SwiftData models.
//  Carrying the science behind each readiness signal.
//

import Foundation

// MARK: - Signal Type

/// Identifies which readiness signal a citation covers.
enum SignalType: String, CaseIterable {
    case hrv
    case acwr
    case sleep
    case metMinutes
    case trainingBalance
    case biologicalAge
    /// Cycling Compound Score — surfaced only by `CyclingCompoundScoreCard`,
    /// not by `SupportingMetricsCard`. It lives here so its citation is stored
    /// (and DOI-pinned by tests) alongside every other one.
    case compoundScore
}

// MARK: - Science Citation

/// A citable sports-science reference that grounds a readiness signal's thresholds.
///
/// `lowerBound` / `upperBound` define the optimal zone.
/// `dangerAbove` marks the risk threshold above the optimal zone (used for ACWR).
/// All values are in the signal's native `unit`.
struct ScienceCitation {
    let signal: SignalType
    let author: String
    let year: Int
    let finding: String
    /// E.g. "ACWR < 0.8 = under-training; 0.8–1.3 = optimal; > 1.5 = 2× injury risk"
    let studyPopulation: String
    let lowerBound: Double?
    let upperBound: Double?
    /// Hard-ceiling above which risk escalates sharply (e.g. ACWR 1.5).
    let dangerAbove: Double?
    /// Human-readable optimal range string for display (e.g. "0.8 – 1.3").
    let optimalRange: String?
    /// Native measurement unit for the bar's axis labels.
    let unit: String
    /// DOI / PubMed URL for the source paper.
    let referenceURL: URL?
    /// Year this citation was last verified against current literature.
    /// Staleness predicate: abs(currentYear - lastVerified) > 2
    let lastVerified: Int

    // MARK: - Computed

    /// Inline author attribution for metric tile display. E.g. "Gabbett '16".
    var shortCitation: String {
        "\(author) '\(String(year).suffix(2))"
    }
}
