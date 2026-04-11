//
//  StravaConnectionView.swift
//  HealthAnalytics
//
//  Created by Craig Faist on 1/25/26.
//


import SwiftUI

struct StravaConnectionView: View {
    @StateObject private var stravaManager = StravaManager.shared
    @State private var isAuthenticating = false
    @State private var errorMessage: String?
    @State private var fetchError: String?
    @Environment(\.openURL) private var openURL
    
    var body: some View {
        VStack(spacing: 30) {
            if stravaManager.isAuthenticated {
                // Connected state
                connectedView
            } else {
                // Not connected state
                disconnectedView
            }
        }
        .padding()
        .navigationTitle("Strava")
        .task {
            guard stravaManager.isAuthenticated else { return }
            let lastFetch = UserDefaults.standard.double(forKey: "strava_athlete_last_fetch")
            guard Date().timeIntervalSince1970 - lastFetch > 86400 else { return }
            do {
                try await StravaManager.shared.fetchAthleteProfile()
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "strava_athlete_last_fetch")
            } catch {
                fetchError = "Could not refresh Strava data. Check your connection."
            }
        }
    }
    
    private var connectedView: some View {
        VStack(spacing: 20) {
            // Success icon
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(Color.statusOptimal)

            Text("Connected to Strava")
                .font(.title2)
                .fontWeight(.semibold)
            
            if let athlete = stravaManager.athlete {
                Text(athlete.fullName)
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            // FTP display
            let ftp = UserDefaults.standard.integer(forKey: "strava_ftp")
            if ftp > 0 {
                HStack {
                    Text("FTP")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.textSecondary)
                    Spacer()
                    Text("\(ftp)W")
                        .font(.subheadline)
                        .fontWeight(.bold)
                }
                .padding(.horizontal, 4)
            } else if stravaManager.isAuthenticated {
                Text("Set your FTP in Strava to improve ride intensity calculations")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
            }

            if let err = fetchError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(Color.statusWarning)
                    .multilineTextAlignment(.center)
            }

            Divider()
                .padding(.vertical)
            
            // Navigate to activities
            NavigationLink {
                StravaActivitiesView()
            } label: {
                HStack {
                    Label("View Activities", systemImage: "list.bullet")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Spacer()
            
            // Sign out button
            Button(role: .destructive) {
                stravaManager.signOut()
            } label: {
                Text("Disconnect Strava")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.red)
            
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Color.statusWarning)
                    .multilineTextAlignment(.center)
            }
        }
    }
    
    private var disconnectedView: some View {
        VStack(spacing: 20) {
            // Strava logo placeholder
            Image(systemName: "bicycle")
                .font(.system(size: 60))
                .foregroundStyle(Color.statusWarning)

            Text("Connect to Strava")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Import your workout data from Strava to get deeper insights and correlations with your health metrics.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            Spacer()
            
            // Connect button
            Button {
                connectToStrava()
            } label: {
                HStack {
                    Image(systemName: "link")
                    Text("Connect with Strava")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.accent)
                .foregroundStyle(.white)
                .cornerRadius(12)
            }
            .disabled(isAuthenticating)
            
            if isAuthenticating {
                ProgressView("Connecting...")
            }
            
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Color.statusWarning)
                    .multilineTextAlignment(.center)
            }
        }
    }
    
    private func connectToStrava() {
        guard let authURL = stravaManager.authorizationURL else {
            errorMessage = "Invalid authorization URL"
            return
        }
        
        isAuthenticating = true
        openURL(authURL)
    }
}

#Preview {
    NavigationStack {
        StravaConnectionView()
    }
}
