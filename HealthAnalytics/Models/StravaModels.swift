//
//  StravaModels.swift
//  HealthAnalytics
//
//  Created by Craig Faist on 1/25/26.
//


import Foundation

// MARK: - Authentication Models

struct StravaTokenResponse: Codable {
    let tokenType: String
    let expiresAt: Int
    let expiresIn: Int
    let refreshToken: String
    let accessToken: String
    let athlete: StravaAthlete
    
    enum CodingKeys: String, CodingKey {
        case tokenType = "token_type"
        case expiresAt = "expires_at"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case accessToken = "access_token"
        case athlete
    }
}

struct StravaAthlete: Codable {
    let id: Int
    let username: String?
    let firstname: String?
    let lastname: String?
    
    var fullName: String {
        let first = firstname ?? ""
        let last = lastname ?? ""
        return "\(first) \(last)".trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Activity Models

struct StravaActivity: Codable, Identifiable {
    let id: Int
    let name: String
    let type: String
    let startDate: String
    let distance: Double
    let movingTime: Int
    let elapsedTime: Int
    let totalElevationGain: Double
    let averageSpeed: Double?
    let maxSpeed: Double?
    let averageHeartrate: Double?
    let maxHeartrate: Double?
    let kilojoules: Double?
    let averageWatts: Double?
    let maxWatts: Int?
    let sufferScore: Int?
    
    enum CodingKeys: String, CodingKey {
        case id, name, type, distance
        case startDate = "start_date"
        case movingTime = "moving_time"
        case elapsedTime = "elapsed_time"
        case totalElevationGain = "total_elevation_gain"
        case averageSpeed = "average_speed"
        case maxSpeed = "max_speed"
        case averageHeartrate = "average_heartrate"
        case maxHeartrate = "max_heartrate"
        case kilojoules
        case averageWatts = "average_watts"
        case maxWatts = "max_watts"
        case sufferScore = "suffer_score"
    }
    
    var startDateFormatted: Date? {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: startDate)
    }
    
    var distanceInMiles: Double {
        distance / 1609.34
    }
    
    var durationFormatted: String {
        let hours = movingTime / 3600
        let minutes = (movingTime % 3600) / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
    
    var paceFormatted: String? {
        guard averageSpeed ?? 0 > 0 else { return nil }
        let speed = averageSpeed ?? 0
        let paceInSeconds = 1609.34 / speed // seconds per mile
        let minutes = Int(paceInSeconds) / 60
        let seconds = Int(paceInSeconds) % 60
        return "\(minutes):\(String(format: "%02d", seconds))/mi"
    }
}
