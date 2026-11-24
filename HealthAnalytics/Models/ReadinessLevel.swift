//
//  ReadinessLevel.swift
//  HealthAnalytics
//
//  Moved out of RecoveryViewModel.swift when that preview-only screen was deleted.
//

import SwiftUI

enum ReadinessLevel: String {
    case excellent = "Excellent"
    case good = "Good"
    case moderate = "Moderate"
    case poor = "Poor"
    
    var emoji: String {
        switch self {
        case .excellent: return "🚀"
        case .good: return "✅"
        case .moderate: return "⚠️"
        case .poor: return "🔴"
        }
    }
    
    var color: Color {
        switch self {
        case .excellent: return .green
        case .good: return .blue
        case .moderate: return .orange
        case .poor: return .red
        }
    }
    
    var description: String {
        switch self {
        case .excellent: return "Peak condition - great for hard training"
        case .good: return "Well recovered - ready for quality work"
        case .moderate: return "Moderate recovery - easy to moderate training"
        case .poor: return "Low recovery - rest or very easy activity recommended"
        }
    }
}
