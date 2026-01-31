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
            
/*            RecoveryTabView()
                .tabItem {
                    Label("Recovery", systemImage: "heart.circle.fill")
                }
                .tag(2)
 */
            NavigationStack {
                ReadinessView()
            }
            .tabItem {
                Label("Readiness", systemImage: "bolt.circle.fill")
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

// MARK: - Header Gradient (Only for nav bar area)
struct HeaderGradient: View {
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
        .blur(radius: 50)
        .opacity(0.3) // Dimmed for readability
    }
}

// MARK: - Tab Background Colors (Solid for content)
struct TabBackgroundColor {
    static func dashboard(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(red: 0.05, green: 0.05, blue: 0.08) : Color(red: 0.97, green: 0.97, blue: 0.99)
    }
    
    static func nutrition(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(red: 0.05, green: 0.08, blue: 0.05) : Color(red: 0.97, green: 0.99, blue: 0.97)
    }
    
    static func recovery(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(red: 0.08, green: 0.05, blue: 0.05) : Color(red: 0.99, green: 0.97, blue: 0.97)
    }
    
    static func insights(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(red: 0.06, green: 0.05, blue: 0.08) : Color(red: 0.98, green: 0.97, blue: 0.99)
    }
    
    static func settings(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(red: 0.05, green: 0.05, blue: 0.05) : Color(red: 0.97, green: 0.97, blue: 0.97)
    }
    
    // Header gradient colors (for nav bar area only)
    static func headerGradient(for colorScheme: ColorScheme) -> Color {
        .blue
    }
}

// MARK: - New Solid Card Style (Replaces glass effect)
struct SolidCardStyle: ViewModifier {
    @Environment(\.colorScheme) var colorScheme
    
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(colorScheme == .dark ? Color(white: 0.12) : .white)
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 12, y: 4)
            )
    }
}

extension View {
    func solidCard() -> some View {
        modifier(SolidCardStyle())
    }
}

#Preview {
    MainTabView()
}
