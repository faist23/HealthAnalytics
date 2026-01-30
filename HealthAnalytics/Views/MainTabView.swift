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

// Replace the solid color backgrounds
struct ModernBackground: View {
    let baseColor: Color
    
    var body: some View {
        let meshColors: [Color] = [
            baseColor.opacity(0.8), baseColor.opacity(0.4), baseColor.opacity(0.9),
            baseColor.opacity(0.4), baseColor, baseColor.opacity(0.7),
            baseColor.opacity(0.6), baseColor.opacity(0.4), baseColor
        ]
        
        MeshGradient(width: 3, height: 3, points: [
            [0, 0], [0.5, 0], [1, 0],
            [0, 0.5], [0.5, 0.5], [1, 0.5],
            [0, 1], [0.5, 1], [1, 1]
        ], colors: meshColors)
        .ignoresSafeArea()
        .blur(radius: 50)
        Color.black.opacity(0.15)
    }
}

// MARK: - Tab Background Colors
struct TabBackgroundColor {
    static func dashboard(for colorScheme: ColorScheme) -> Color { .blue }
    static func nutrition(for colorScheme: ColorScheme) -> Color {
        // Deep Emerald instead of bright green
        colorScheme == .dark ? Color(red: 0.05, green: 0.25, blue: 0.15) : Color(red: 0.9, green: 1.0, blue: 0.95)
    }
    static func insights(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.15, green: 0.12, blue: 0.08) // Deep Espresso/Charcoal
            : Color(red: 0.98, green: 0.94, blue: 0.85) // Soft Vanilla
    }
    
    // Recovery burgundy looks better slightly cooler
    static func recovery(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(red: 0.25, green: 0.05, blue: 0.1) : Color(red: 1.0, green: 0.93, blue: 0.95)
    }
    static func settings(for colorScheme: ColorScheme) -> Color { .gray }
}


#Preview {
    MainTabView()
}
