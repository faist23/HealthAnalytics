//
//  DataWindowManager.swift
//  HealthAnalytics
//
//  Manages the historical data window setting
//

import Foundation
import SwiftUI

struct DataWindowManager {
    
    /// Get the cutoff date based on user's historical data window preference
    static func getCutoffDate() -> Date? {
        @AppStorage("historicalDataWindowYears") var historicalDataWindowYears: Int = 0
        
        // 0 means all-time (no cutoff)
        guard historicalDataWindowYears > 0 else {
            return nil
        }
        
        let calendar = Calendar.current
        let currentDate = Date()
        
        // Calculate cutoff date (e.g., 5 years ago from today)
        guard let cutoffDate = calendar.date(byAdding: .year, value: -historicalDataWindowYears, to: currentDate) else {
            return nil
        }
        
        return cutoffDate
    }
    
    /// Get the start date for data syncing
    static func getDataSyncStartDate() -> Date {
        if let cutoff = getCutoffDate() {
            return cutoff
        } else {
            // All-time: go back 10 years as maximum
            let calendar = Calendar.current
            return calendar.date(byAdding: .year, value: -10, to: Date()) ?? Date()
        }
    }
    
    /// Check if a date is within the current data window
    static func isWithinDataWindow(_ date: Date) -> Bool {
        guard let cutoff = getCutoffDate() else {
            return true // All-time mode, everything is valid
        }
        
        return date >= cutoff
    }
    
    /// Get years to backfill based on setting
    static func getYearsToBackfill() -> Int {
        @AppStorage("historicalDataWindowYears") var historicalDataWindowYears: Int = 0
        
        return historicalDataWindowYears == 0 ? 10 : historicalDataWindowYears
    }
}
