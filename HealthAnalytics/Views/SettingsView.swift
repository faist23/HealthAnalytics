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
            // Apply the background at the root
//            ModernBackground(baseColor: TabBackgroundColor.settings(for: colorScheme))
//                .ignoresSafeArea()
            
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
                
                Section("Permissions") {
                    Text("Tap 'Re-authorize HealthKit' to grant access to nutrition data")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Settings")
//       .background(ModernBackground(baseColor: TabBackgroundColor.settings(for: colorScheme)))
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
