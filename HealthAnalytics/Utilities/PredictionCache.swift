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
        if let cached = try? modelContext.fetch(descriptor).last {
            self.lastFingerprint = DataFingerprint(
                workoutCount: cached.workoutCount,
                sleepCount: cached.sleepCount,
                hrvCount: cached.hrvCount,
                rhrCount: cached.rhrCount
            )
        }
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
    
    func store(models: [PerformancePredictor.TrainedModel], fingerprint: DataFingerprint, instruction: CoachingService.DailyInstruction) {
        self.models          = models
        self.lastFingerprint = fingerprint
        self.lastError       = nil
        
        // Map status to Hex for persistence
        let colorHex = instruction.status == .perform ? "#34C759" : (instruction.status == .recover ? "#FF9500" : "#007AFF")
        
        saveToPersistence(
            fingerprint: fingerprint,
            headline: instruction.headline,
            targetAction: instruction.targetAction ?? "View dashboard",
            colorHex: colorHex
        )
    }

    private func saveToPersistence(fingerprint: DataFingerprint, headline: String, targetAction: String, colorHex: String) {
        try? modelContext.delete(model: CachedAnalysis.self)
        let newCache = CachedAnalysis(
            fingerprint: fingerprint,
            headline: headline,
            targetAction: targetAction,
            statusColorHex: colorHex
        )
        modelContext.insert(newCache)
        try? modelContext.save()
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
