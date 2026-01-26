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
    }
    
    private var connectedView: some View {
        VStack(spacing: 20) {
            // Success icon
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)
            
            Text("Connected to Strava")
                .font(.title2)
                .fontWeight(.semibold)
            
            if let athlete = stravaManager.athlete {
                Text(athlete.fullName)
                    .font(.headline)
                    .foregroundStyle(.secondary)
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
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }
        }
    }
    
    private var disconnectedView: some View {
        VStack(spacing: 20) {
            // Strava logo placeholder
            Image(systemName: "bicycle")
                .font(.system(size: 60))
                .foregroundStyle(.orange)
            
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
                .background(Color.orange)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(isAuthenticating)
            
            if isAuthenticating {
                ProgressView("Connecting...")
            }
            
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
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
