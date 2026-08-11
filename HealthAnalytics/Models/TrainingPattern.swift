//
//  TrainingPattern.swift
//  HealthAnalytics
//
//  Phase 2 — Pattern Engine
//

import Foundation
import SwiftData

// MARK: - PatternType

enum PatternType: String, Codable, CaseIterable {
    case blockCrashCycle
    case hrvPrecursor
    case sleepFragmentation
    case backToBackCrash
    case performancePeak
    case tapering

    var displayName: String {
        switch self {
        case .blockCrashCycle:    return "Block Crash Cycle"
        case .hrvPrecursor:       return "HRV Precursor"
        case .sleepFragmentation: return "Sleep Fragmentation"
        case .backToBackCrash:    return "14-Day Signature"
        case .performancePeak:    return "Peak Form"
        // Names what was measured, not why. The detector fires on "volume down >= 30%
        // AND HRV rising", which is equally the signature of injury, illness, or a week
        // of work travel — it cannot see intent, so the card must not claim it.
        case .tapering:           return "Load Dropping"
        }
    }

    var definition: String {
        switch self {
        case .blockCrashCycle:
            return "Your HRV and sleep decline in the final days of each training block."
        case .hrvPrecursor:
            return "Your HRV drops 36–72h before illness — a detectable early warning."
        case .sleepFragmentation:
            return "Sleep quality fragments after sustained high training loads."
        case .backToBackCrash:
            return "Your recovery consistently crashes after back-to-back hard training days."
        case .performancePeak:
            return "HRV elevated 7+ days and optimal training load — race-ready window."
        case .tapering:
            return "Training volume down 30%+ while HRV recovers — the shape a pre-race taper makes."
        }
    }

    /// The unit noun used in confidence language ("3 of 4 blocks")
    var instanceNoun: String {
        switch self {
        case .blockCrashCycle:    return "blocks"
        case .hrvPrecursor:       return "events"
        case .sleepFragmentation: return "periods"
        case .backToBackCrash:    return "sequences"
        case .performancePeak:    return "peak"
        case .tapering:           return "taper"
        }
    }

    var icon: String {
        switch self {
        case .blockCrashCycle:    return "chart.bar.fill"
        case .hrvPrecursor:       return "waveform.path.ecg"
        case .sleepFragmentation: return "moon.zzz.fill"
        case .backToBackCrash:    return "bolt.horizontal.fill"
        case .performancePeak:    return "trophy.fill"
        case .tapering:           return "arrow.down.circle.fill"
        }
    }

    /// Render priority for UI tie-breaking (0 = highest priority).
    static func displayPriority(_ type: PatternType) -> Int {
        let order: [PatternType] = [
            .hrvPrecursor, .backToBackCrash, .blockCrashCycle,
            .sleepFragmentation, .performancePeak, .tapering
        ]
        return order.firstIndex(of: type) ?? 99
    }

    /// Default citation key for this pattern type
    nonisolated var citationKey: String {
        switch self {
        case .blockCrashCycle:    return "meeusen2013"
        case .hrvPrecursor:       return "plews2013"
        case .sleepFragmentation: return "halson2014"
        case .backToBackCrash:    return "gabbett2016"
        case .performancePeak:    return "pyne2009"
        case .tapering:           return "mujika2003"
        }
    }
}

// MARK: - TrainingPattern Model

@Model
final class TrainingPattern {
    var patternType: PatternType
    var detectedAt: Date
    var confidenceNumerator: Int
    var confidenceDenominator: Int
    var evidenceSummary: String
    var citationKey: String
    var instanceDates: [Date]
    var coachingResponse: String
    var notificationSent: Bool
    // backToBackCrash-specific fields (nil for all other pattern types)
    var lagCorrelation: Double?   // Pearson r between sequence index and readiness drop magnitude
    var peakDropDay: Int?         // Day offset (1 or 2) where the crash is deepest on average
    // performancePeak-specific field: 0.0–1.0 signal strength (nil for other types)
    var probability: Double?
    // tapering-specific field: predicted race-peak date (nil for other types)
    var peakDate: Date?

    init(
        patternType: PatternType,
        detectedAt: Date = Date(),
        confidenceNumerator: Int,
        confidenceDenominator: Int,
        evidenceSummary: String,
        citationKey: String,
        instanceDates: [Date],
        coachingResponse: String,
        notificationSent: Bool = false,
        lagCorrelation: Double? = nil,
        peakDropDay: Int? = nil,
        probability: Double? = nil,
        peakDate: Date? = nil
    ) {
        self.patternType = patternType
        self.detectedAt = detectedAt
        self.confidenceNumerator = confidenceNumerator
        self.confidenceDenominator = confidenceDenominator
        self.evidenceSummary = evidenceSummary
        self.citationKey = citationKey
        self.instanceDates = instanceDates
        self.coachingResponse = coachingResponse
        self.notificationSent = notificationSent
        self.lagCorrelation = lagCorrelation
        self.peakDropDay = peakDropDay
        self.probability = probability
        self.peakDate = peakDate
    }

    // MARK: - Computed

    /// Normalized 0–1 strength, used by `confidenceQualifier` and by
    /// `TrainingDNACard.confidenceTier` for the colour pill.
    ///
    /// Every pattern except tapering stores an occurrence count over a number of
    /// chances, so numerator/denominator is already a 0–1 ratio. Tapering stores a
    /// load-drop PERCENTAGE over the 30% trigger threshold, so its raw ratio is
    /// always >= 1.0 — which pinned every taper, including the weakest qualifying
    /// one, to the strongest tier and a green pill. Scale it across the band that
    /// actually varies instead: 30% drop (the trigger) → 0.0, 60%+ → 1.0.
    var confidenceRatio: Double {
        guard confidenceDenominator > 0 else { return 0 }
        if patternType == .tapering {
            let trigger = Double(confidenceDenominator)
            return min(1.0, max(0.0, (Double(confidenceNumerator) - trigger) / trigger))
        }
        return Double(confidenceNumerator) / Double(confidenceDenominator)
    }

    var confidenceQualifier: String {
        if confidenceNumerator == 2 && patternType == .sleepFragmentation {
            return "Early signal"
        }
        // Tapering has no instance count, so the `<= 3` floor doesn't apply to it —
        // its numerator is a percentage and is always >= 30.
        if patternType == .tapering {
            if confidenceRatio >= 0.75 { return "Consistent" }
            if confidenceRatio >= 0.25 { return "Mixed signal" }
            return "Tentative"
        }
        if confidenceNumerator <= 3 { return "Tentative" }
        if confidenceRatio >= 0.75 { return "Consistent" }
        return "Mixed signal"
    }

    var confidenceCountText: String {
        // Tapering has no instances to count — `detectTaperUnderway` packs the load-drop
        // percentage into the numerator and the 30% trigger threshold into the denominator.
        // The shared "seen in N of M" phrasing turns that into "seen in 41 of 30 taper":
        // a fraction above 1 against a singular noun. Render it as what it actually is.
        if patternType == .tapering {
            return "load down \(confidenceNumerator)% (\(confidenceDenominator)% threshold)"
        }
        return "seen in \(confidenceNumerator) of \(confidenceDenominator) \(patternType.instanceNoun)"
    }

    var shareText: String {
        """
        Training DNA · \(patternType.displayName)
        \(confidenceQualifier) · \(confidenceCountText)

        \(evidenceSummary)

        Based on: \(citationKey) — Detected by HealthAnalytics on iOS.
        """
    }

    /// True when detected within the last 48 hours.
    var isNewlyDetected: Bool {
        Date().timeIntervalSince(detectedAt) < 48 * 3600
    }

    /// How recently a pattern must have been re-detected to count as "active".
    /// `upsertPatterns` refreshes `detectedAt` on every run where the pattern still
    /// holds, so a pattern that stops being true simply ages out of this window.
    ///
    /// MUST stay strictly greater than the pattern-analysis cadence in
    /// `ReadinessRepository.runPatternAnalysis` (7 days). At exactly 7 the two
    /// coincided: patterns expired at the same instant a refresh became eligible,
    /// so any user who hadn't opened the Patterns tab in a week saw every surface
    /// read zero until an analysis run completed. The 3-day margin keeps patterns
    /// on screen while their refresh comes due.
    static let activeWindowDays = 10

    /// True when the pattern was re-detected within the active window.
    ///
    /// Nothing ever deletes a `TrainingPattern` — `TrainingDNAAnalyzer.upsertPatterns`
    /// only inserts and updates, deliberately, so `notificationSent` survives. That
    /// makes recency the ONLY signal that a pattern still holds, and every surface
    /// that shows patterns MUST filter on it. Skipping the filter freezes a card on
    /// screen forever: a taper detected once kept claiming "Taper Underway / Load
    /// down 41%" weeks after the load came back up, while the Load tab correctly
    /// read ACWR ~1.0. Do not re-introduce a local `sevenDaysAgo` cutoff in a view.
    var isActive: Bool {
        let cutoff = Calendar.current.date(
            byAdding: .day, value: -Self.activeWindowDays, to: Date()
        ) ?? Date()
        return detectedAt >= cutoff
    }
}
