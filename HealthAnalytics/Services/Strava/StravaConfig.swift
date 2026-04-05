//
//  StravaConfig.swift
//  HealthAnalytics
//
//  Created by Craig Faist on 1/25/26.
//


import Foundation

struct StravaConfig {
    
    private static var plist: [String: Any]? = {
        guard let path = Bundle.main.path(forResource: "StravaConfig", ofType: "plist") else {
            #if DEBUG
            print("❌ StravaConfig.plist not found in bundle")
            print("Bundle path: \(Bundle.main.bundlePath)")
            #endif
            return nil
        }

        guard let xml = FileManager.default.contents(atPath: path) else {
            #if DEBUG
            print("❌ Could not read StravaConfig.plist contents")
            #endif
            return nil
        }

        guard let plistData = try? PropertyListSerialization.propertyList(from: xml, options: .mutableContainersAndLeaves, format: nil) as? [String: Any] else {
            #if DEBUG
            print("❌ Could not parse StravaConfig.plist")
            #endif
            return nil
        }

        #if DEBUG
        print("✅ StravaConfig.plist loaded successfully")
        print("Keys found: \(plistData.keys)")
        #endif
        return plistData
    }()
    
    static var clientID: String {
        let id = plist?["StravaClientID"] as? String ?? ""
        #if DEBUG
        print("Client ID: \(id.isEmpty ? "EMPTY" : "Found (\(id.prefix(5))...)")")
        #endif
        return id
    }

    static var clientSecret: String {
        let secret = plist?["StravaClientSecret"] as? String ?? ""
        #if DEBUG
        print("Client Secret: \(secret.isEmpty ? "EMPTY" : "Found")")
        #endif
        return secret
    }

    static var redirectURI: String {
        let uri = plist?["RedirectURI"] as? String ?? ""
        #if DEBUG
        print("Redirect URI: \(uri)")
        #endif
        return uri
    }
    
    // API Endpoints
    static let authorizationURL = "https://www.strava.com/oauth/authorize"
    static let tokenURL = "https://www.strava.com/oauth/token"
    static let apiBaseURL = "https://www.strava.com/api/v3"
    
    // Scopes
    static let scope = "read,activity:read_all"
}
