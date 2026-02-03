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
    
    // Coaching fields for the Widget
    var headline: String
    var targetAction: String
    var statusColorHex: String
    
    var lastUpdated: Date
    
    init(
        fingerprint: PredictionCache.DataFingerprint,
        headline: String,
        targetAction: String,
        statusColorHex: String
    ) {
        self.id = "singleton_cache"
        self.workoutCount = fingerprint.workoutCount
        self.sleepCount = fingerprint.sleepCount
        self.hrvCount = fingerprint.hrvCount
        self.rhrCount = fingerprint.rhrCount
        self.headline = headline
        self.targetAction = targetAction
        self.statusColorHex = statusColorHex
        self.lastUpdated = Date()
    }
}
