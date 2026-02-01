//
//  PredictionCache.swift
//  HealthAnalytics
//
//  Created by Craig Faist on 2/1/26.
//
//  Lightweight in-memory cache for trained ML models.
//  Invalidates automatically when the workout count changes,
//  so we only retrain when there's actually new data.
//

import Foundation

/// Singleton that holds the most recently trained models and the
/// data fingerprint that produced them.  Thread-safe via serial actor.
@MainActor
final class PredictionCache {

    static let shared = PredictionCache()

    // ── Cached state ──
    private(set) var models:           [PerformancePredictor.TrainedModel] = []
    private(set) var lastPrediction:   PerformancePredictor.Prediction?
    private(set) var lastError:        Error?

    /// The fingerprint we trained on last time.  If the current data
    /// produces the same fingerprint we skip retraining entirely.
    private var lastFingerprint: DataFingerprint?

    private init() {}

    // MARK: - Fingerprint

    /// A cheap summary of the data used for training.  If any of these
    /// numbers change we know new data arrived and need to retrain.
    struct DataFingerprint: Equatable {
        let workoutCount:  Int
        let sleepCount:    Int
        let hrvCount:      Int
        let rhrCount:      Int
    }

    /// Build a fingerprint from the current data sets.
    static func fingerprint(
        workoutCount: Int,
        sleepCount:   Int,
        hrvCount:     Int,
        rhrCount:     Int
    ) -> DataFingerprint {
        DataFingerprint(
            workoutCount: workoutCount,
            sleepCount:   sleepCount,
            hrvCount:     hrvCount,
            rhrCount:     rhrCount
        )
    }

    // MARK: - Cache operations

    /// Returns true if the provided fingerprint matches what we already trained on.
    func isUpToDate(fingerprint: DataFingerprint) -> Bool {
        fingerprint == lastFingerprint
    }

    /// Stores a freshly trained set of models under the given fingerprint.
    func store(models: [PerformancePredictor.TrainedModel], fingerprint: DataFingerprint) {
        self.models          = models
        self.lastFingerprint = fingerprint
        self.lastError       = nil
        print("📦 PredictionCache: stored \(models.count) model(s), fingerprint \(fingerprint)")
    }

    /// Stores an error so the UI can surface it without crashing.
    func storeError(_ error: Error) {
        self.lastError = error
        print("📦 PredictionCache: stored error — \(error.localizedDescription)")
    }

    /// Stores the most recent prediction result for quick UI access.
    func storePrediction(_ prediction: PerformancePredictor.Prediction?) {
        self.lastPrediction = prediction
    }

    /// Nukes everything — call on sign-out or data reset.
    func invalidate() {
        models           = []
        lastFingerprint  = nil
        lastPrediction   = nil
        lastError        = nil
        print("📦 PredictionCache: invalidated")
    }
}
