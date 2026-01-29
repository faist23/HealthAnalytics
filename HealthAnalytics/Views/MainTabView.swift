//
//  MainTabView.swift
//  HealthAnalytics
//
//  Created by Craig Faist on 1/25/26.
//


import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                ContentView()
            }
            .tabItem {
                Label("Dashboard", systemImage: "chart.line.uptrend.xyaxis")
            }
            .tag(0)
            
            NavigationStack {
                NutritionView()
            }
            .tabItem {
                Label("Nutrition", systemImage: "fork.knife")
            }
            .tag(1)
            
            RecoveryTabView()
                .tabItem {
                    Label("Recovery", systemImage: "heart.circle.fill")
                }
                .tag(2)
            
            NavigationStack {
                InsightsView()
            }
            .tabItem {
                Label("Insights", systemImage: "lightbulb.fill")
            }
            .tag(3)
            
            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
            .tag(4)
        }
    }
}

// MARK: - Tab Background Colors (for use in individual views)

struct TabBackgroundColor {
    static func dashboard(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.15, green: 0.20, blue: 0.35) // Rich deep blue
            : Color(red: 0.85, green: 0.92, blue: 1.0)  // Bright sky blue
    }
    
    static func nutrition(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.12, green: 0.30, blue: 0.15) // Rich forest green
            : Color(red: 0.85, green: 1.0, blue: 0.88)  // Bright mint green
    }
    
    static func recovery(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.35, green: 0.15, blue: 0.20) // Rich burgundy/wine
            : Color(red: 1.0, green: 0.88, blue: 0.92)  // Bright pink
    }
    
    static func insights(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.32, green: 0.24, blue: 0.12) // Rich warm brown/amber
            : Color(red: 1.0, green: 0.93, blue: 0.78)  // Bright golden yellow
    }
    
    static func settings(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.18, green: 0.18, blue: 0.22) // Cool slate blue-gray
            : Color(red: 0.92, green: 0.92, blue: 0.94) // Light neutral
    }
}

#Preview {
    MainTabView()
}
