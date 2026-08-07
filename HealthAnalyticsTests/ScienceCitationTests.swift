//
//  ScienceCitationTests.swift
//  HealthAnalyticsTests
//

import XCTest
@testable import HealthAnalytics

final class ScienceCitationTests: XCTestCase {

    // MARK: - CitationDatabase lookup

    func testDatabaseReturnsNonNilForKnownSignals() {
        XCTAssertNotNil(CitationDatabase.citation(for: .hrv))
        XCTAssertNotNil(CitationDatabase.citation(for: .acwr))
        XCTAssertNotNil(CitationDatabase.citation(for: .sleep))
        XCTAssertNotNil(CitationDatabase.citation(for: .metMinutes))
        XCTAssertNotNil(CitationDatabase.citation(for: .trainingBalance))
    }

    func testBiologicalAgeReturnsNil() {
        // Biological age is an internal estimate — no external citation
        XCTAssertNil(CitationDatabase.citation(for: .biologicalAge))
    }

    // MARK: - ACWR (Gabbett 2016) — cross-checked against CLAUDE.md "0.8–1.3"

    func testACWRCitationAuthorAndYear() throws {
        let c = try XCTUnwrap(CitationDatabase.citation(for: .acwr))
        XCTAssertEqual(c.author, "Gabbett")
        XCTAssertEqual(c.year, 2016)
    }

    func testACWRBoundsMatchCLAUDEmdMandate() throws {
        let c = try XCTUnwrap(CitationDatabase.citation(for: .acwr))
        // CLAUDE.md: "ACWR sweet spot: 0.8–1.3"
        let lower = try XCTUnwrap(c.lowerBound)
        let upper = try XCTUnwrap(c.upperBound)
        let danger = try XCTUnwrap(c.dangerAbove)
        XCTAssertEqual(lower, 0.8, accuracy: 0.001)
        XCTAssertEqual(upper, 1.3, accuracy: 0.001)
        XCTAssertEqual(danger, 1.5, accuracy: 0.001)
    }

    func testACWRFindingIsNonEmpty() throws {
        let c = try XCTUnwrap(CitationDatabase.citation(for: .acwr))
        XCTAssertFalse(c.finding.isEmpty)
        XCTAssertFalse(c.studyPopulation.isEmpty)
    }

    // MARK: - HRV (Kiviniemi 2007)

    func testHRVCitationAuthorAndYear() throws {
        let c = try XCTUnwrap(CitationDatabase.citation(for: .hrv))
        XCTAssertEqual(c.author, "Kiviniemi")
        XCTAssertEqual(c.year, 2007)
    }

    // MARK: - Sleep (Simpson 2017)

    func testSleepCitationYear() throws {
        let c = try XCTUnwrap(CitationDatabase.citation(for: .sleep))
        XCTAssertEqual(c.year, 2017)
        let lower = try XCTUnwrap(c.lowerBound)
        let upper = try XCTUnwrap(c.upperBound)
        XCTAssertEqual(lower, 7.0, accuracy: 0.001)
        XCTAssertEqual(upper, 9.0, accuracy: 0.001)
    }

    // MARK: - MET-minutes (WHO 2020) — no upper danger zone

    func testMETMinutesHasNoUpperBound() throws {
        let c = try XCTUnwrap(CitationDatabase.citation(for: .metMinutes))
        // WHO 2020 does NOT cap benefit — upper bound must be nil
        XCTAssertNil(c.upperBound, "WHO 2020 has no upper harm threshold — upperBound must be nil")
        XCTAssertNil(c.dangerAbove, "WHO 2020 has no upper danger zone — dangerAbove must be nil")
    }

    // MARK: - Reference URLs ("View source" link target)

    /// Every citation the UI can show must carry a link, or `MetricConditionDetailView`
    /// silently drops the "View source" row.
    func testEveryCitationHasAReferenceURL() {
        for signal in SignalType.allCases {
            guard let c = CitationDatabase.citation(for: signal) else { continue }
            XCTAssertNotNil(c.referenceURL, "\(signal) has no referenceURL — 'View source' would not render")
        }
    }

    /// Pins each DOI to the exact paper whose author/year/finding we display.
    ///
    /// Regression: the HRV and training-balance DOIs were unregistered (doi.org 404 —
    /// "DOI Not Found"), and the sleep + ACWR DOIs resolved to *different* papers than
    /// the ones attributed on screen. Verified against the DOI handle API 2026-08-07.
    /// If you change a DOI here, resolve it first — do not hand-assemble a suffix.
    func testReferenceURLsPointAtTheAttributedPaper() throws {
        let expected: [SignalType: String] = [
            // Kiviniemi et al. 2007, Eur J Appl Physiol
            .hrv: "https://doi.org/10.1007/s00421-007-0552-2",
            // Gabbett 2016, BJSM — the training–injury prevention paradox
            .acwr: "https://doi.org/10.1136/bjsports-2015-095788",
            // Simpson, Gibbs & Matheson 2017, Scand J Med Sci Sports
            .sleep: "https://doi.org/10.1111/sms.12703",
            // Bull et al. 2020, BJSM — WHO physical activity guidelines
            .metMinutes: "https://doi.org/10.1136/bjsports-2020-102955",
            // Momma et al. 2022, BJSM — muscle-strengthening + mortality
            .trainingBalance: "https://doi.org/10.1136/bjsports-2021-105061",
        ]

        for (signal, urlString) in expected {
            let c = try XCTUnwrap(CitationDatabase.citation(for: signal))
            let actual = try XCTUnwrap(c.referenceURL)
            XCTAssertEqual(actual.absoluteString, urlString, "\(signal) links to the wrong paper")
        }

        // Guard the pin list itself: a signal added later must be pinned here,
        // otherwise it would ship an unverified DOI and this test would still pass.
        for signal in SignalType.allCases where CitationDatabase.citation(for: signal) != nil {
            XCTAssertNotNil(expected[signal],
                            "\(signal) has a citation but no pinned DOI — resolve it and add it here")
        }
    }

    /// The Training Balance card measures the endurance/strength/mobility mix
    /// (`BalancedTrainingAnalyzer`), so its citation must be about combining
    /// strength with aerobic work — not periodisation, tapering, or monotony.
    ///
    /// Regression: it shipped citing "Mujika / Foster 2003" with a tapering paper,
    /// describing a metric this app does not have.
    func testTrainingBalanceCitesStrengthResearchNotPeriodisation() throws {
        let c = try XCTUnwrap(CitationDatabase.citation(for: .trainingBalance))
        XCTAssertEqual(c.author, "Momma")
        XCTAssertEqual(c.year, 2022)

        let text = (c.finding + " " + c.studyPopulation).lowercased()
        XCTAssertTrue(text.contains("muscle-strengthening"),
                      "Training Balance citation should describe strength work")
        for offTopic in ["periodisation", "taper", "monotony"] {
            XCTAssertFalse(text.contains(offTopic),
                           "Training Balance citation must not describe \(offTopic) — wrong metric")
        }
    }

    // MARK: - All populated fields are non-empty strings

    func testAllCitationStringsAreNonEmpty() {
        for signal in SignalType.allCases {
            guard let c = CitationDatabase.citation(for: signal) else { continue }
            XCTAssertFalse(c.author.isEmpty, "\(signal) author is empty")
            XCTAssertFalse(c.finding.isEmpty, "\(signal) finding is empty")
            XCTAssertFalse(c.studyPopulation.isEmpty, "\(signal) studyPopulation is empty")
            XCTAssertFalse(c.unit.isEmpty, "\(signal) unit is empty")
        }
    }

    // MARK: - lastVerified + shortCitation + isStale

    func testLastVerifiedIs2026() {
        // All citations verified this cycle; none should be stale until 2028.
        for signal in SignalType.allCases {
            guard let c = CitationDatabase.citation(for: signal) else { continue }
            XCTAssertEqual(c.lastVerified, 2026, "\(signal) lastVerified should be 2026")
        }
    }

    func testShortCitationFormat() throws {
        let acwr = try XCTUnwrap(CitationDatabase.citation(for: .acwr))
        // "Gabbett '16" — author + space + apostrophe + 2-digit year
        XCTAssertEqual(acwr.shortCitation, "Gabbett '16")

        let hrv = try XCTUnwrap(CitationDatabase.citation(for: .hrv))
        XCTAssertEqual(hrv.shortCitation, "Kiviniemi '07")

        let sleep = try XCTUnwrap(CitationDatabase.citation(for: .sleep))
        XCTAssertEqual(sleep.shortCitation, "Simpson '17")
    }

    func testIsStale_logic() throws {
        // Verify the isStale predicate using explicit reference years, not wall-clock Date().
        // This avoids a time-bomb failure when currentYear - 2026 > 2 (i.e. after 2028).
        // Use CitationDatabase.citation(for:) — ScienceCitation static properties are fileprivate.
        let currentYear = Calendar.current.component(.year, from: Date())
        let base = try XCTUnwrap(CitationDatabase.citation(for: .hrv))
        let recentCitation = base.withLastVerified(currentYear - 1)
        XCTAssertFalse(CitationDatabase.isStale(recentCitation), "1-year-old citation should not be stale")
        let staleCitation = base.withLastVerified(currentYear - 3)
        XCTAssertTrue(CitationDatabase.isStale(staleCitation), "3-year-old citation should be stale")
    }
}

// MARK: - Test helpers

private extension ScienceCitation {
    /// Returns a copy of the citation with a different lastVerified year — used to test
    /// CitationDatabase.isStale() without depending on the wall-clock date.
    func withLastVerified(_ year: Int) -> ScienceCitation {
        ScienceCitation(
            signal: signal, author: author, year: self.year, finding: finding,
            studyPopulation: studyPopulation, lowerBound: lowerBound, upperBound: upperBound,
            dangerAbove: dangerAbove, optimalRange: optimalRange, unit: unit,
            referenceURL: referenceURL, lastVerified: year
        )
    }
}
