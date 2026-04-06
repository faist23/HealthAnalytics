//
//  CardiovascularStrainService.swift
//  HealthAnalytics
//
//  Computes a continuous cardiovascular strain score (0–21) from raw heart-rate
//  samples, using the Heart Rate Reserve (HRR) method.
//
//  Model parameters (per CLAUDE.md science constraints):
//  - Exponent: HRR^2 (balances sensitivity vs ambient-activity noise)
//  - HRR floor: 20% — below this HR is essentially resting, contributes 0
//  - Normalization: 90 raw units → 21 strain points
//    Calibrated so a hard 90-min workout + light day ≈ 15–16,
//    a rest day ≈ 1–3, a race/marathon ≈ 21 (capped).
//
//  maxHR is always derived from the user's own peak recorded HR, never from
//  the 220-age population formula (CLAUDE.md mandate).
//

import Foundation
import SwiftUI

struct CardiovascularStrainService {

    struct Result {
        /// Cardiovascular strain on the 0–21 scale.
        let strain: Double
        /// The max HR value used for this calculation (bpm).
        let estimatedMaxHR: Double
        /// The resting HR value used for this calculation (bpm).
        let restingHRUsed: Double
        /// Number of raw HR samples that fed the calculation.
        let sampleCount: Int
        let dataQuality: Quality

        enum Quality {
            /// 500+ samples — Apple Watch worn most of the day.
            case good
            /// 50–499 samples — partial day or watch worn intermittently.
            case fair
            /// <50 samples — score is unreliable, show with caveat.
            case insufficient
        }
    }

    // MARK: - Model constants

    /// Minimum HRR fraction that contributes load. Below this the heart is
    /// essentially at rest and adds negligible cardiovascular strain.
    private static let hrrFloor: Double = 0.20

    /// Raw units that map to 21 strain points.
    /// Calibrated so a hard 60-min zone 4-5 effort (≈90% HRR) scores ~16-18 (STRENUOUS),
    /// a 90-min hard workout hits the 21-point cap, and a rest day lands 2-5 (LIGHT).
    private static let normalization: Double = 70.0

    // MARK: - Main entry point

    /// Compute today's cardiovascular strain from raw HR samples.
    ///
    /// - Parameters:
    ///   - todayHRSamples: Timestamped HR readings from midnight to now.
    ///   - estimatedMaxHR: User's personal max HR (from `fetchPersonalMaxHR`).
    ///   - restingHR: User's most recent resting HR reading.
    func compute(
        todayHRSamples: [(date: Date, bpm: Double)],
        estimatedMaxHR: Double,
        restingHR: Double
    ) -> Result {
        let hrRange = estimatedMaxHR - restingHR

        guard hrRange > 10, !todayHRSamples.isEmpty else {
            return Result(
                strain: 0,
                estimatedMaxHR: estimatedMaxHR,
                restingHRUsed: restingHR,
                sampleCount: 0,
                dataQuality: .insufficient
            )
        }

        let sorted = todayHRSamples.sorted { $0.date < $1.date }
        var rawStrain: Double = 0

        for i in 1..<sorted.count {
            let current = sorted[i]
            let previous = sorted[i - 1]

            let timeDeltaMinutes = current.date.timeIntervalSince(previous.date) / 60.0

            // Skip gaps > 10 min — watch removed, sleep segment, or data dropout.
            guard timeDeltaMinutes > 0, timeDeltaMinutes <= 10 else { continue }

            // Average HR across this interval.
            let avgBPM = (current.bpm + previous.bpm) / 2.0
            let hrr = (avgBPM - restingHR) / hrRange

            // Apply floor: ambient/resting HR contributes zero.
            guard hrr >= Self.hrrFloor else { continue }

            rawStrain += pow(hrr, 2) * timeDeltaMinutes
        }

        let strain = min(21.0, rawStrain / Self.normalization * 21.0)

        let quality: Result.Quality
        switch sorted.count {
        case 500...: quality = .good
        case 50..<500: quality = .fair
        default: quality = .insufficient
        }

        return Result(
            strain: strain,
            estimatedMaxHR: estimatedMaxHR,
            restingHRUsed: restingHR,
            sampleCount: sorted.count,
            dataQuality: quality
        )
    }

    // MARK: - Strain label + color

    /// Single source of truth for zone thresholds.
    /// Both label(for:) and color(for:) delegate here — they cannot disagree.
    private static func zone(for strain: Double) -> (label: String, color: Color) {
        switch strain {
        case 0..<7:   return ("LIGHT",     Color.statusOptimal)
        case 7..<13:  return ("MODERATE",  Color.statusMonitoring)
        case 13..<18: return ("STRENUOUS", Color.statusWarning)
        default:      return ("ALL-OUT",   Color.statusAllOut)
        }
    }

    static func label(for strain: Double) -> String { zone(for: strain).label }
    static func color(for strain: Double) -> Color  { zone(for: strain).color }
}
