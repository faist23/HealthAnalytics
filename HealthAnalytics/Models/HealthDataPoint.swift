//
//  HealthDataPoint.swift
//  HealthAnalytics
//
//  Created by Craig Faist on 1/25/26.
//


import Foundation
import HealthKit

struct HealthDataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
    
    var unit: String = ""
    var dataType: HKQuantityTypeIdentifier? = nil
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
    
    var formattedValue: String {
        String(format: "%.0f", value)
    }
}
