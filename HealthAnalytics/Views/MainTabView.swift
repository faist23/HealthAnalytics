//
//  MainTabView.swift
//  HealthAnalytics
//
//  Created by Craig Faist on 1/25/26.
//

import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0
    @ObservedObject var syncManager = SyncManager.shared
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        ZStack {
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
            
            // Global sync indicator
            if syncManager.isSyncing {
                LoadingOverlay(message: syncManager.syncProgress)
            }
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

struct TabBackgroundColor {
    static func dashboard(for colorScheme: ColorScheme) -> Color { AppColors.dashboardBG }
    static func nutrition(for colorScheme: ColorScheme) -> Color { AppColors.nutritionBG }
    static func recovery(for colorScheme: ColorScheme) -> Color { AppColors.recoveryBG }
    static func insights(for colorScheme: ColorScheme) -> Color { AppColors.insightsBG }
    static func settings(for colorScheme: ColorScheme) -> Color { AppColors.settingsBG }
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

struct AppColors {
    // Card tints
    static let heartRate = Color.red
    static let hrv       = Color.green
    static let sleep     = Color.blue
    static let steps     = Color.orange
    static let workouts  = Color.pink
    static let recovery  = Color.purple
    static let nutrition = Color.teal
    static let error     = Color.red
    static let info      = Color.indigo

    // Tab background colors
    static let dashboardBG = Color(red: 0.1, green: 0.05, blue: 0.15)
    static let nutritionBG = Color(red: 0.05, green: 0.15, blue: 0.1)
    static let recoveryBG  = Color(red: 0.15, green: 0.05, blue: 0.1)
    static let insightsBG  = Color(red: 0.05, green: 0.1, blue: 0.15)
    static let settingsBG  = Color(red: 0.1, green: 0.1, blue: 0.1)
}

// MARK: - Tinted Card Modifier
struct TintedCardStyle: ViewModifier {
    var tint: Color
    
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(tint.opacity(0.15))
                    .shadow(color: tint.opacity(0.3), radius: 8, y: 4)
            )
            .padding(.horizontal, 0)
    }
}

extension View {
    func tintedCard(tint: Color) -> some View {
        modifier(TintedCardStyle(tint: tint))
    }
}
extension View {
    func cardStyle(for type: CardType) -> some View {
        switch type {
        case .heartRate: return tintedCard(tint: AppColors.heartRate)
        case .hrv:       return tintedCard(tint: AppColors.hrv)
        case .sleep:     return tintedCard(tint: AppColors.sleep)
        case .steps:     return tintedCard(tint: AppColors.steps)
        case .workouts:  return tintedCard(tint: AppColors.workouts)
        case .recovery:  return tintedCard(tint: AppColors.recovery)
        case .nutrition: return tintedCard(tint: AppColors.nutrition)
        case .error:     return tintedCard(tint: AppColors.error)
        case .info:      return tintedCard(tint: AppColors.info)
        }
    }
}

enum CardType {
    case heartRate, hrv, sleep, steps, workouts, recovery, nutrition, error, info
}


#Preview {
    MainTabView()
}
