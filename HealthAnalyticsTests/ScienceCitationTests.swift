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
