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
        
        print("🔑 Token Exchange Request:")
        print("   URL: \(url)")
        print("   Client ID: \(StravaConfig.clientID)")
        print("   Code: \(code)")
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse {
            print("📡 Token Response Status: \(httpResponse.statusCode)")
        }
        
        if let responseString = String(data: data, encoding: .utf8) {
            print("📡 Token Response Body: \(responseString)")
        }
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            print("❌ Token exchange failed with status: \((response as? HTTPURLResponse)?.statusCode ?? 0)")
            throw StravaError.authenticationFailed
        }
        
        let tokenResponse = try JSONDecoder().decode(StravaTokenResponse.self, from: data)
        
        await MainActor.run {
            self.accessToken = tokenResponse.accessToken
            self.refreshToken = tokenResponse.refreshToken
            self.tokenExpiresAt = Date(timeIntervalSince1970: TimeInterval(tokenResponse.expiresAt))
            self.athlete = tokenResponse.athlete
            self.isAuthenticated = true
            print("✅ Successfully authenticated as \(tokenResponse.athlete?.fullName ?? "Unknown")")
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
        
        print("📊 Fetched \(fetchedActivities.count) activities from Strava")
        
        return fetchedActivities
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
                print("⚠️ Loaded token is expired. Will need to refresh on next use.")
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
        
        print("🔄 Strava token expired or expiring soon. Refreshing...")
        
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
        
        print("📡 Token refresh response: \(httpResponse.statusCode)")
        
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
            print("✅ Token refreshed successfully. Expires at: \(self.tokenExpiresAt?.formatted() ?? "unknown")")
        }
        
        saveTokensToKeychain()
    }
}

enum StravaError: Error, LocalizedError {
    case invalidCallback
    case authenticationFailed
    case notAuthenticated
    case invalidURL
    case fetchFailed
    
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
        }
    }
}
