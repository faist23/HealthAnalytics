//
//  HealthDataContainer.swift
//  HealthAnalytics
//
//  Created by Craig Faist on 2/2/26.
//


import Foundation
import SwiftData

@MainActor
public enum HealthDataContainer {
    public static let shared: ModelContainer = {
        // 1. Define the schema (must include your CachedAnalysis model)
        let schema = Schema([
            CachedAnalysis.self,
            StoredWorkout.self,
            StoredHealthMetric.self,
            StoredNutrition.self
        ])
        
        let appGroupID = "group.com.ridepro.HealthAnalytics"
        
        // 1. Manually ensure the directory exists in the App Group container
        let fileManager = FileManager.default
        if let groupURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            let appSupportURL = groupURL.appendingPathComponent("Library/Application Support", isDirectory: true)
            
            if !fileManager.fileExists(atPath: appSupportURL.path) {
                try? fileManager.createDirectory(at: appSupportURL, withIntermediateDirectories: true)
                print("📦 HealthDataContainer: Created missing Application Support directory in App Group.")
            }
        }
        
        let configuration = ModelConfiguration(
            "HealthAnalyticsShared",
            schema: schema,
            groupContainer: .identifier(appGroupID)
        )
        
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not create shared ModelContainer: \(error)")
        }
    }()
}
