//
//  CachedAnalysis.swift
//  HealthAnalytics
//
//  Created by Craig Faist on 2/2/26.
//


import Foundation
import SwiftData

@Model
final class CachedAnalysis {
    var id: String
    var workoutCount: Int
    var sleepCount: Int
    var hrvCount: Int
    var rhrCount: Int
    var lastUpdated: Date
    
    // Using a simple identifier for the singleton instance
    init(fingerprint: PredictionCache.DataFingerprint) {
        self.id = "singleton_cache"
        self.workoutCount = fingerprint.workoutCount
        self.sleepCount = fingerprint.sleepCount
        self.hrvCount = fingerprint.hrvCount
        self.rhrCount = fingerprint.rhrCount
        self.lastUpdated = Date()
    }
}