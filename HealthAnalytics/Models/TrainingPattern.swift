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
        case .tapering:           return "Taper Underway"
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
            return "Your readiness consistently crashes after back-to-back hard training days."
        case .performancePeak:
            return "HRV elevated 7+ days and optimal training load — race-ready window."
        case .tapering:
            return "Training load dropping 30%+ with HRV trending up — pre-race peak window approaching."
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

    var confidenceQualifier: String {
        let ratio = confidenceDenominator > 0
            ? Double(confidenceNumerator) / Double(confidenceDenominator)
            : 0
        if confidenceNumerator == 2 && patternType == .sleepFragmentation {
            return "Early signal"
        }
        if confidenceNumerator <= 3 { return "Tentative" }
        if ratio >= 0.75 { return "Consistent" }
        return "Mixed signal"
    }

    var confidenceCountText: String {
        "seen in \(confidenceNumerator) of \(confidenceDenominator) \(patternType.instanceNoun)"
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
}
