//
//  StravaManager.swift
//  HealthAnalytics
//
//  Created by Craig Faist on 1/25/26.
//


import Foundation
import Combine

class StravaManager: ObservableObject {
    
    static let shared = StravaManager()
    
    @Published var isAuthenticated = false
    @Published var athlete: StravaAthlete?
    @Published var activities: [StravaActivity] = []
    
    private var accessToken: String?
    private var refreshToken: String?
    private var tokenExpiresAt: Date?
    
    private init() {
        loadTokensFromKeychain()
    }
    
    // MARK: - Authentication
    
    var authorizationURL: URL? {
        var components = URLComponents(string: StravaConfig.authorizationURL)
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: StravaConfig.clientID),
            URLQueryItem(name: "redirect_uri", value: StravaConfig.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: StravaConfig.scope),
            URLQueryItem(name: "state", value: "healthanalytics") // This identifies the app
        ]
        return components?.url
    }
    
    func handleOAuthCallback(url: URL) async throws {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw StravaError.invalidCallback
        }
        
        try await exchangeCodeForToken(code: code)
    }
    
    private func exchangeCodeForToken(code: String) async throws {
        let url = URL(string: StravaConfig.tokenURL)!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "client_id": StravaConfig.clientID,
            "client_secret": StravaConfig.clientSecret,
            "code": code,
            "grant_type": "authorization_code"
        ]
        
        #if DEBUG
        print("🔑 Token Exchange Request:")
        print("   URL: \(url)")
        print("   Client ID: \(StravaConfig.clientID)")
        print("   Code: \(code)")
        #endif
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse {
            #if DEBUG
            print("📡 Token Response Status: \(httpResponse.statusCode)")
            #endif
        }

        if let responseString = String(data: data, encoding: .utf8) {
            #if DEBUG
            print("📡 Token Response Body: \(responseString)")
            #endif
        }

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            #if DEBUG
            print("❌ Token exchange failed with status: \((response as? HTTPURLResponse)?.statusCode ?? 0)")
            #endif
            throw StravaError.authenticationFailed
        }
        
        let tokenResponse = try JSONDecoder().decode(StravaTokenResponse.self, from: data)
        
        await MainActor.run {
            self.accessToken = tokenResponse.accessToken
            self.refreshToken = tokenResponse.refreshToken
            self.tokenExpiresAt = Date(timeIntervalSince1970: TimeInterval(tokenResponse.expiresAt))
            self.athlete = tokenResponse.athlete
            self.isAuthenticated = true
            #if DEBUG
            print("✅ Successfully authenticated as \(tokenResponse.athlete?.fullName ?? "Unknown")")
            #endif
        }
        
        saveTokensToKeychain()
    }
    
    /// Fetch activities from Strava
    func fetchActivities(page: Int = 1, perPage: Int = 30) async throws -> [StravaActivity] {
        // Refresh token if needed
        try await refreshTokenIfNeeded()
        
        guard let accessToken = accessToken else {
            throw StravaError.notAuthenticated
        }
        
        var components = URLComponents(string: "\(StravaConfig.apiBaseURL)/athlete/activities")
        components?.queryItems = [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "per_page", value: "\(perPage)")
        ]
        
        guard let url = components?.url else {
            throw StravaError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw StravaError.fetchFailed
        }
        
        let fetchedActivities = try JSONDecoder().decode([StravaActivity].self, from: data)
        
        #if DEBUG
        print("📊 Fetched \(fetchedActivities.count) activities from Strava")
        #endif
        
        return fetchedActivities
    }
    
    // MARK: - Athlete Profile

    /// Fetches full athlete profile including FTP. Call from StravaConnectionView on appear (24h guard).
    /// Returns the fetched FTP in watts (nil if the athlete profile has no FTP set).
    /// The caller is responsible for persisting an FTPSnapshot if the value changed.
    @discardableResult
    func fetchAthleteProfile() async throws -> Int? {
        try await refreshTokenIfNeeded()
        guard let token = accessToken else { throw StravaError.notAuthenticated }
        var request = URLRequest(url: URL(string: "\(StravaConfig.apiBaseURL)/athlete")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw StravaError.apiError
        }
        #if DEBUG
        if let raw = String(data: data, encoding: .utf8) {
            print("🏃 /athlete raw response: \(raw.prefix(500))")
        }
        #endif
        let fetched = try JSONDecoder().decode(StravaAthlete.self, from: data)
        #if DEBUG
        print("🏃 Decoded athlete: \(fetched.fullName), ftp=\(fetched.ftp.map(String.init) ?? "nil")")
        #endif
        if let ftp = fetched.ftp, ftp > 0 {
            UserDefaults.standard.set(ftp, forKey: "strava_ftp")
        }
        await MainActor.run { self.athlete = fetched }
        return fetched.ftp.flatMap { $0 > 0 ? $0 : nil }
    }

    // MARK: - Sign Out

    func signOut() {
        accessToken = nil
        refreshToken = nil
        tokenExpiresAt = nil
        athlete = nil
        isAuthenticated = false
        activities = []
        clearTokensFromKeychain()
    }
    
    // MARK: - Keychain Storage (simplified for now)
    
    private func saveTokensToKeychain() {
        UserDefaults.standard.set(accessToken, forKey: "strava_access_token")
        UserDefaults.standard.set(refreshToken, forKey: "strava_refresh_token")
        if let expiresAt = tokenExpiresAt {
            UserDefaults.standard.set(expiresAt, forKey: "strava_token_expires_at")
        }
    }
    
    private func loadTokensFromKeychain() {
        accessToken = UserDefaults.standard.string(forKey: "strava_access_token")
        refreshToken = UserDefaults.standard.string(forKey: "strava_refresh_token")
        tokenExpiresAt = UserDefaults.standard.object(forKey: "strava_token_expires_at") as? Date
        
        if accessToken != nil {
            // Check if token is expired
            if let expiresAt = tokenExpiresAt, Date() >= expiresAt {
                #if DEBUG
                print("⚠️ Loaded token is expired. Will need to refresh on next use.")
                #endif
            }
            isAuthenticated = true
        }
    }
    
    private func clearTokensFromKeychain() {
        UserDefaults.standard.removeObject(forKey: "strava_access_token")
        UserDefaults.standard.removeObject(forKey: "strava_refresh_token")
        UserDefaults.standard.removeObject(forKey: "strava_token_expires_at")
    }
    
    /// Checks if token needs refresh and refreshes it automatically
    private func refreshTokenIfNeeded() async throws {
        guard let _ = accessToken,
              let refreshToken = refreshToken,
              let expiresAt = tokenExpiresAt else {
            throw StravaError.notAuthenticated
        }
        
        // Check if token expires within the next hour (safety margin)
        let needsRefresh = Date().timeIntervalSince1970 >= expiresAt.timeIntervalSince1970 - 3600
        
        if !needsRefresh {
            return // Token is still valid
        }
        
        #if DEBUG
        print("🔄 Strava token expired or expiring soon. Refreshing...")
        #endif
        
        guard let tokenURL = URL(string: StravaConfig.tokenURL) else {
            throw StravaError.invalidURL
        }
        
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "client_id": StravaConfig.clientID,
            "client_secret": StravaConfig.clientSecret,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw StravaError.fetchFailed
        }
        
        #if DEBUG
        print("📡 Token refresh response: \(httpResponse.statusCode)")
        #endif
        
        guard httpResponse.statusCode == 200 else {
            // If refresh fails, clear tokens and force re-auth
            await MainActor.run {
                self.accessToken = nil
                self.refreshToken = nil
                self.tokenExpiresAt = nil
                self.athlete = nil
                self.isAuthenticated = false
            }
            saveTokensToKeychain() // This will delete them since they're nil
            throw StravaError.authenticationFailed
        }
        
        let tokenResponse = try JSONDecoder().decode(StravaTokenResponse.self, from: data)
        
        await MainActor.run {
            self.accessToken = tokenResponse.accessToken
            self.refreshToken = tokenResponse.refreshToken
            self.tokenExpiresAt = Date(timeIntervalSince1970: TimeInterval(tokenResponse.expiresAt))
            self.isAuthenticated = true
            #if DEBUG
            print("✅ Token refreshed successfully. Expires at: \(self.tokenExpiresAt?.formatted() ?? "unknown")")
            #endif
        }
        
        saveTokensToKeychain()
    }
    
    /// Fetch raw watts stream for a cycling activity and return seconds spent in each of 7 power zones.
    /// Zones are computed against `ftp`. Returns nil if the activity has no power data.
    /// Zone boundaries: Z1 <55%, Z2 55-75%, Z3 76-90%, Z4 91-105%, Z5 106-120%, Z6 121-150%, Z7 >150%
    func fetchPowerZoneSeconds(activityId: Int, ftp: Double) async throws -> [Double]? {
        try await refreshTokenIfNeeded()
        guard let token = accessToken else { throw StravaError.notAuthenticated }

        let url = URL(string: "\(StravaConfig.apiBaseURL)/activities/\(activityId)/streams?keys=watts&key_by_type=true")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw StravaError.fetchFailed
        }

        struct WattsStream: Decodable {
            struct StreamData: Decodable { let data: [Double?] }
            let watts: StreamData?
        }
        let streams = try JSONDecoder().decode(WattsStream.self, from: data)
        guard let samples = streams.watts?.data else { return nil }

        // Boundaries as fraction of FTP
        let boundaries: [Double] = [0.55, 0.75, 0.90, 1.05, 1.20, 1.50]
        var zoneSecs = [Double](repeating: 0, count: 7)

        for watts in samples.compactMap({ $0 }) {
            let ratio = watts / ftp
            let zone: Int
            if      ratio < boundaries[0] { zone = 0 }
            else if ratio < boundaries[1] { zone = 1 }
            else if ratio < boundaries[2] { zone = 2 }
            else if ratio < boundaries[3] { zone = 3 }
            else if ratio < boundaries[4] { zone = 4 }
            else if ratio < boundaries[5] { zone = 5 }
            else                          { zone = 6 }
            zoneSecs[zone] += 1  // each sample = 1 second
        }

        #if DEBUG
        let total = zoneSecs.reduce(0, +)
        let pcts = zoneSecs.map { String(format: "%.0f%%", total > 0 ? $0/total*100 : 0) }
        print("📊 Zones for activity \(activityId): Z1=\(pcts[0]) Z2=\(pcts[1]) Z3=\(pcts[2]) Z4=\(pcts[3]) Z5=\(pcts[4]) Z6=\(pcts[5]) Z7=\(pcts[6])")
        #endif

        return zoneSecs
    }

    /// Fetches the raw watts stream and calculates the maximum 5-minute rolling average power.
    func fetchPeak5MinPower(activityId: Int) async throws -> Double? {
        try await refreshTokenIfNeeded()
        guard let token = accessToken else { throw StravaError.notAuthenticated }

        let url = URL(string: "\(StravaConfig.apiBaseURL)/activities/\(activityId)/streams?keys=watts&key_by_type=true")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw StravaError.fetchFailed
        }

        struct WattsStream: Decodable {
            struct StreamData: Decodable { let data: [Double?] }
            let watts: StreamData?
        }
        let streams = try JSONDecoder().decode(WattsStream.self, from: data)
        guard let rawSamples = streams.watts?.data else { return nil }

        // Strava streams can contain nil, assume 0 for dropped connections/coasting to keep window time valid
        let samples = rawSamples.map { $0 ?? 0.0 }
        
        // 5-minute rolling average (300 samples, assuming 1 sample = 1 second)
        let windowSize = 300
        guard samples.count >= windowSize else { return nil }

        var currentSum: Double = 0
        // Initial window sum
        for i in 0..<windowSize {
            currentSum += samples[i]
        }
        
        var maxAvg: Double = currentSum / Double(windowSize)

        // Slide window
        for i in windowSize..<samples.count {
            currentSum += samples[i]
            currentSum -= samples[i - windowSize]
            let avg = currentSum / Double(windowSize)
            if avg > maxAvg {
                maxAvg = avg
            }
        }

        return maxAvg > 0 ? maxAvg : nil
    }

    /// Fetch detailed activity with streams (HR, power, etc.)
    func fetchActivityDetails(activityId: Int) async throws -> StravaActivityDetail {
        try await refreshTokenIfNeeded()
        
        guard let accessToken = accessToken else {
            throw StravaError.notAuthenticated
        }
        
        // Fetch activity summary
        let activityURL = URL(string: "\(StravaConfig.apiBaseURL)/activities/\(activityId)")!
        var activityRequest = URLRequest(url: activityURL)
        activityRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (activityData, _) = try await URLSession.shared.data(for: activityRequest)
        var activity = try JSONDecoder().decode(StravaActivity.self, from: activityData)
        
        // If summary doesn't have HR/power, fetch streams
        if activity.averageHeartrate == nil || activity.averageWatts == nil {
            let streamsURL = URL(string: "\(StravaConfig.apiBaseURL)/activities/\(activityId)/streams?keys=heartrate,watts&key_by_type=true")!
            var streamsRequest = URLRequest(url: streamsURL)
            streamsRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            
            let (streamsData, _) = try await URLSession.shared.data(for: streamsRequest)
            let streams = try JSONDecoder().decode(StravaStreams.self, from: streamsData)
            
            // Calculate averages from streams if missing
            if activity.averageHeartrate == nil, let hrData = streams.heartrate?.data, !hrData.isEmpty {
                activity = activity.withAverageHR(hrData.reduce(0, +) / Double(hrData.count))
            }
            
            if activity.averageWatts == nil, let powerData = streams.watts?.data, !powerData.isEmpty {
                activity = activity.withAveragePower(powerData.reduce(0, +) / Double(powerData.count))
            }
        }
        
        return StravaActivityDetail(activity: activity)
    }

    struct StravaStreams: Codable {
        let heartrate: StreamData?
        let watts: StreamData?
        
        struct StreamData: Codable {
            let data: [Double]
        }
    }

    struct StravaActivityDetail {
        let activity: StravaActivity
    }
}

enum StravaError: Error, LocalizedError {
    case invalidCallback
    case authenticationFailed
    case notAuthenticated
    case invalidURL
    case fetchFailed
    case apiError
    
    var errorDescription: String? {
        switch self {
        case .invalidCallback:
            return "Invalid OAuth callback"
        case .authenticationFailed:
            return "Failed to authenticate with Strava"
        case .notAuthenticated:
            return "Not authenticated with Strava"
        case .invalidURL:
            return "Invalid URL"
        case .fetchFailed:
            return "Failed to fetch data from Strava"
        case .apiError:
            return "Strava API returned an error"
        }
    }
}
