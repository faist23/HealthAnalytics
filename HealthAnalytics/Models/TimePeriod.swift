//
//  TimePeriod.swift
//  HealthAnalytics
//
//  Created by Craig Faist on 1/26/26.
//

import Foundation

enum TimePeriod: String, CaseIterable, Identifiable {
    case week = "7D"
    case month = "30D"
    case quarter = "90D"
    case sixMonths = "6M"
    case year = "1Y"
    case all = "All"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .week: return "Week"
        case .month: return "Month"
        case .quarter: return "90D"
        case .sixMonths: return "180D"
        case .year: return "Year"
        case .all: return "All"
        }
    }
    
    var days: Int? {
        switch self {
        case .week: return 7
        case .month: return 30
        case .quarter: return 90
        case .sixMonths: return 180
        case .year: return 365
        case .all: return nil
        }
    }
    
    func startDate(from endDate: Date = Date()) -> Date {
        guard let days = days else {
            // For "all", go back 5 years
            return Calendar.current.date(byAdding: .year, value: -5, to: endDate) ?? endDate
        }
        return Calendar.current.date(byAdding: .day, value: -days, to: endDate) ?? endDate
    }

    /// X-axis stride used by Charts. Moved here from the deleted ContentView.swift.
    var xAxisStride: (component: Calendar.Component, count: Int) {
        switch self {
        case .week:      return (.day, 1)
        case .month:     return (.day, 7)
        case .quarter:   return (.day, 14)
        case .sixMonths: return (.month, 1)
        case .year:      return (.month, 2)
        case .all:       return (.year, 1)
        }
    }
}
