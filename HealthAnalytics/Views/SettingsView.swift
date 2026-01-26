//
//  SettingsView.swift
//  HealthAnalytics
//
//  Created by Craig Faist on 1/25/26.
//


import SwiftUI

struct SettingsView: View {
    var body: some View {
        List {
            Section("App") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text("1.0.0")
                        .foregroundStyle(.secondary)
                }
            }
            
            Section("Data Sources") {
                NavigationLink {
                    Text("HealthKit settings coming soon")
                } label: {
                    Label("HealthKit", systemImage: "heart.fill")
                }
                
                NavigationLink {
                    StravaConnectionView()
                } label: {
                    Label("Strava", systemImage: "bicycle")
                }
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