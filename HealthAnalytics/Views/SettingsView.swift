//
//  SettingsView.swift
//  HealthAnalytics
//
//  Created by Craig Faist on 1/25/26.
//


import SwiftUI

struct SettingsView: View {
    @StateObject private var healthKitManager = HealthKitManager.shared
    @State private var isRequestingAuth = false
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        ZStack {
            // 🔹 Tab background color (same system as other tabs)
            TabBackgroundColor.settings(for: colorScheme)
                .ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    
                    // MARK: - App
                    VStack(alignment: .leading, spacing: 12) {
                        Text("App")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        
                        HStack {
                            Text("Version")
                            Spacer()
                            Text("1.0.0")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding()
                    .cardStyle(for: .info)
                    
                    // MARK: - Data Sources
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Data Sources")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        
                        Button {
                            isRequestingAuth = true
                            Task {
                                _ = await healthKitManager.requestAuthorization()
                                isRequestingAuth = false
                            }
                        } label: {
                            HStack {
                                Label("Re-authorize HealthKit", systemImage: "heart.fill")
                                Spacer()
                                if isRequestingAuth {
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(isRequestingAuth)
                        
                        NavigationLink {
                            StravaConnectionView()
                        } label: {
                            Label("Strava", systemImage: "bicycle")
                        }
                    }
                    .padding()
                    .cardStyle(for: .info)
                    
                    // MARK: - Permissions
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Permissions")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        
                        Text("Tap “Re-authorize HealthKit” to grant access to nutrition data.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .cardStyle(for: .info)
                }
                .padding(.horizontal)
                .padding(.top, 12)
            }
        }
        .navigationTitle("Settings")
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}


