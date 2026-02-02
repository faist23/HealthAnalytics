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
import SwiftData

@MainActor
final class PredictionCache {

    static let shared = PredictionCache()

    // ── Cached state ──
    private(set) var models:           [PerformancePredictor.TrainedModel] = []
    private(set) var lastPrediction:   PerformancePredictor.Prediction?
    private(set) var lastError:        Error?

    private var lastFingerprint: DataFingerprint?
    
    // Step 4: Add Context Reference
    private var modelContext: ModelContext {
        HealthDataContainer.shared.mainContext
    }

    private init() {
        loadFromPersistence()
    }

    // MARK: - Persistence Logic

    private func loadFromPersistence() {
        let descriptor = FetchDescriptor<CachedAnalysis>()
        do {
            if let cached = try modelContext.fetch(descriptor).last {
                self.lastFingerprint = DataFingerprint(
                    workoutCount: cached.workoutCount,
                    sleepCount: cached.sleepCount,
                    hrvCount: cached.hrvCount,
                    rhrCount: cached.rhrCount
                )
                print("📦 PredictionCache: Restored fingerprint from persistence")
            }
        } catch {
            print("📦 PredictionCache: Load failed — \(error)")
        }
    }

    private func saveToPersistence(fingerprint: DataFingerprint) {
        // Clear old entry and save new one
        try? modelContext.delete(model: CachedAnalysis.self)
        let newCache = CachedAnalysis(fingerprint: fingerprint)
        modelContext.insert(newCache)
        try? modelContext.save()
    }

    // MARK: - Cache operations

    struct DataFingerprint: Equatable {
        let workoutCount:  Int
        let sleepCount:    Int
        let hrvCount:      Int
        let rhrCount:      Int
    }

    static func fingerprint(workoutCount: Int, sleepCount: Int, hrvCount: Int, rhrCount: Int) -> DataFingerprint {
        DataFingerprint(workoutCount: workoutCount, sleepCount: sleepCount, hrvCount: hrvCount, rhrCount: rhrCount)
    }

    func isUpToDate(fingerprint: DataFingerprint) -> Bool {
        fingerprint == lastFingerprint
    }

    func store(models: [PerformancePredictor.TrainedModel], fingerprint: DataFingerprint) {
        self.models          = models
        self.lastFingerprint = fingerprint
        self.lastError       = nil
        saveToPersistence(fingerprint: fingerprint) // Save to App Group
        print("📦 PredictionCache: stored \(models.count) model(s), fingerprint \(fingerprint)")
    }

    func storeError(_ error: Error) {
        self.lastError = error
    }

    func storePrediction(_ prediction: PerformancePredictor.Prediction?) {
        self.lastPrediction = prediction
    }

    func invalidate() {
        models           = []
        lastFingerprint  = nil
        lastPrediction   = nil
        lastError        = nil
        try? modelContext.delete(model: CachedAnalysis.self)
        try? modelContext.save()
        print("📦 PredictionCache: invalidated")
    }
    
    // MARK: - Manual Cache Clear

    /// Manually clears all persistent and in-memory cache data.
    func clearAllData() {
        invalidate()
        print("📦 PredictionCache: Manual database clear triggered.")
    }
}
