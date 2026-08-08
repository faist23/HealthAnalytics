//
//  MainTabView.swift
//  HealthAnalytics
//

import SwiftUI
import SwiftData

struct MainTabView: View {
    @EnvironmentObject var coordinator: TabCoordinator
    @ObservedObject var syncManager = SyncManager.shared
    @Environment(\.colorScheme) var colorScheme

    // R.5: count of patterns detected in the past 7 days drives a numeric
    // badge on the Patterns tab icon — so users can see at a glance from any
    // tab whether there's something new to look at on Patterns.
    @Query private var detectedPatterns: [TrainingPattern]

    private var activePatternCount: Int {
        detectedPatterns.filter { $0.isActive }.count
    }

    var body: some View {
        ZStack {
            TabView(selection: $coordinator.selectedTab) {
                CoachTabView()
                    .tabItem {
                        Label("Coach", systemImage: "sparkles")
                    }
                    .tag(0)

                RecoveryTabView()
                    .tabItem {
                        Label("Recovery", systemImage: "battery.100")
                    }
                    .tag(1)

                StrainTabView()
                    .tabItem {
                        Label("Load", systemImage: "flame.fill")
                    }
                    .tag(2)

                PatternsTabView()
                    .tabItem {
                        Label("Patterns", systemImage: "waveform.path.ecg")
                    }
                    .badge(activePatternCount)
                    .tag(3)

                LabsTabView()
                    .tabItem {
                        Label("Labs", systemImage: "flask")
                    }
                    .tag(4)
            }
            .tint(AppColors.accentColor(for: coordinator.selectedTab))

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
                RoundedRectangle(cornerRadius: .radiusMd, style: .continuous)
                    .fill(colorScheme == .dark ? Color.surface : .white)
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
    // Card tints — mapped to Warm Signal semantic tokens (DESIGN.md)
    static let heartRate = Color.statusWarning   // Ember — HR elevation signals stress
    static let hrv       = Color.statusOptimal   // Bio-green — HRV health indicator
    static let sleep     = Color.statusRest      // Sky blue — rest/recovery mode
    static let steps     = Color.accent          // Terracotta — daily activity energy
    static let workouts  = Color.accent          // Terracotta — training effort
    static let recovery  = Color.statusOptimal   // Bio-green — recovery quality
    static let nutrition = Color.statusMonitoring // Amber — nutrition monitoring
    static let error     = Color.statusWarning   // Ember — high-risk / error state
    static let info      = Color.statusRest      // Sky blue — informational

    // Tab backgrounds — all use the app background token (no per-tab tinting per DESIGN.md)
    static let dashboardBG = Color.background
    static let nutritionBG = Color.background
    static let recoveryBG  = Color.background
    static let insightsBG  = Color.background
    static let settingsBG  = Color.background

    // Unified tab bar tint — terracotta accent across all tabs
    static func accentColor(for tab: Int) -> Color {
        Color.accent
    }
}

// MARK: - Tinted Card Modifier
struct TintedCardStyle: ViewModifier {
    var tint: Color

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: .radiusMd, style: .continuous)
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
