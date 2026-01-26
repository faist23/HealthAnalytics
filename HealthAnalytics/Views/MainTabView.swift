//
//  MainTabView.swift
//  HealthAnalytics
//
//  Created by Craig Faist on 1/25/26.
//


import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            NavigationStack {
                ContentView()
            }
            .tabItem {
                Label("Dashboard", systemImage: "chart.line.uptrend.xyaxis")
            }
            
            NavigationStack {
                InsightsView()
            }
            .tabItem {
                Label("Insights", systemImage: "lightbulb.fill")
            }
            
            NavigationStack {
                StravaConnectionView()
            }
            .tabItem {
                Label("Strava", systemImage: "bicycle")
            }
            
            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
        }
    }
}

#Preview {
    MainTabView()
}
