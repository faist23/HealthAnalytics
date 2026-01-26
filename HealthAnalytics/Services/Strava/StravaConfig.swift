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
            print("❌ StravaConfig.plist not found in bundle")
            print("Bundle path: \(Bundle.main.bundlePath)")
            return nil
        }
        
        guard let xml = FileManager.default.contents(atPath: path) else {
            print("❌ Could not read StravaConfig.plist contents")
            return nil
        }
        
        guard let plistData = try? PropertyListSerialization.propertyList(from: xml, options: .mutableContainersAndLeaves, format: nil) as? [String: Any] else {
            print("❌ Could not parse StravaConfig.plist")
            return nil
        }
        
        print("✅ StravaConfig.plist loaded successfully")
        print("Keys found: \(plistData.keys)")
        return plistData
    }()
    
    static var clientID: String {
        let id = plist?["StravaClientID"] as? String ?? ""
        print("Client ID: \(id.isEmpty ? "EMPTY" : "Found (\(id.prefix(5))...)")")
        return id
    }
    
    static var clientSecret: String {
        let secret = plist?["StravaClientSecret"] as? String ?? ""
        print("Client Secret: \(secret.isEmpty ? "EMPTY" : "Found")")
        return secret
    }
    
    static var redirectURI: String {
        let uri = plist?["RedirectURI"] as? String ?? ""
        print("Redirect URI: \(uri)")
        return uri
    }
    
    // API Endpoints
    static let authorizationURL = "https://www.strava.com/oauth/authorize"
    static let tokenURL = "https://www.strava.com/oauth/token"
    static let apiBaseURL = "https://www.strava.com/api/v3"
    
    // Scopes
    static let scope = "read,activity:read_all"
}
