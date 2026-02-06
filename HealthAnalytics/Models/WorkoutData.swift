//
//  WorkoutData.swift
//  HealthAnalytics
//
//  Created by Craig Faist on 1/25/26.
//


import Foundation
import HealthKit

enum WorkoutSource: String {
    case appleWatch = "Apple Watch"
    case strava = "Strava"
    case other = "Other"
    
    var iconName: String {
        switch self {
        case .appleWatch: return "applewatch"
        case .strava: return "figure.outdoor.cycle"  // Strava doesn't have an SF Symbol
        case .other: return "heart.circle"
        }
    }
    
    var color: String {
        switch self {
        case .appleWatch: return "blue"
        case .strava: return "orange"
        case .other: return "gray"
        }
    }
}

struct WorkoutData: Identifiable {
    let id: UUID
    let workoutType: HKWorkoutActivityType
    let startDate: Date
    let endDate: Date
    let duration: TimeInterval
    let totalEnergyBurned: Double?
    let totalDistance: Double?
    let averagePower: Double?
    let source: WorkoutSource
    
    init(
            id: UUID = UUID(), // Default for previews only
            workoutType: HKWorkoutActivityType,
            startDate: Date,
            endDate: Date,
            duration: TimeInterval,
            totalEnergyBurned: Double?,
            totalDistance: Double?,
            averagePower: Double?,
            source: WorkoutSource
        ) {
            self.id = id
            self.workoutType = workoutType
            self.startDate = startDate
            self.endDate = endDate
            self.duration = duration
            self.totalEnergyBurned = totalEnergyBurned
            self.totalDistance = totalDistance
            self.averagePower = averagePower
            self.source = source
        }

    var workoutName: String {
        switch workoutType {
        case .running:
            return "Running"
        case .cycling:
            return "Cycling"
        case .swimming:
            return "Swimming"
        case .walking:
            return "Walking"
        case .hiking:
            return "Hiking"
        case .functionalStrengthTraining:
            return "Strength Training"
        case .traditionalStrengthTraining:
            return "Weight Training"
        case .coreTraining:
            return "Core Training"
        case .yoga:
            return "Yoga"
        case .rowing:
            return "Rowing"
        case .elliptical:
            return "Elliptical"
        case .stairClimbing:
            return "Stairs"
        default:
            return "Workout"
        }
    }
    
    var iconName: String {
        switch workoutType {
        case .running:
            return "figure.run"
        case .cycling:
            return "figure.outdoor.cycle"
        case .swimming:
            return "figure.pool.swim"
        case .walking:
            return "figure.walk"
        case .hiking:
            return "figure.hiking"
        case .rowing:
            return "figure.rower"
        case .yoga:
            return "figure.yoga"
        case .functionalStrengthTraining, .traditionalStrengthTraining:
            return "dumbbell.fill"
        case .coreTraining:
            return "figure.core.training"
        case .elliptical:
            return "figure.elliptical"
        case .stairClimbing:
            return "figure.stairs"
        default:
            return "figure.mixed.cardio"
        }
    }
    
    var formattedDuration: String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) / 60 % 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
    
    var formattedCalories: String {
        guard let calories = totalEnergyBurned else { return "N/A" }
        return "\(Int(calories)) cal"
    }
    
    var formattedDistance: String? {
        guard let distance = totalDistance else { return nil }
        let miles = distance / 1609.34
        return String(format: "%.2f mi", miles)
    }
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter.string(from: startDate)
    }
    
    // NEW: Formatted average power
    var formattedPower: String? {
        guard let power = averagePower, power > 0 else { return nil }
        return "\(Int(power)) W"
    }
}
