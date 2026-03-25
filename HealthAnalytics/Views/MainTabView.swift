//
//  MainTabView.swift
//  HealthAnalytics
//
//  Created by Craig Faist on 1/25/26.
//

import SwiftUI

// MARK: - App Mode

enum AppMode: String, CaseIterable {
    case morning = "Morning"
    case evening = "Evening"

    var systemImage: String {
        switch self {
        case .morning: return "sunrise.fill"
        case .evening: return "sunset.fill"
        }
    }

    /// (primaryLabel, secondaryLabel) for the sub-view picker.
    var subTitles: (String, String) {
        switch self {
        case .morning: return ("Readiness", "Today")
        case .evening: return ("Training", "Nutrition")
        }
    }

    /// Auto-detect: before 13:00 → morning, 13:00+ → evening.
    static var currentDefault: AppMode {
        Calendar.current.component(.hour, from: Date()) < 13 ? .morning : .evening
    }
}

// MARK: - MainTabView

struct MainTabView: View {

    @State private var activeMode: AppMode = AppMode.currentDefault
    /// 0 = Readiness, 1 = Today  (preserved when switching to evening and back)
    @State private var morningTab  = 0
    /// 0 = Training,  1 = Nutrition  (preserved when switching to morning and back)
    @State private var eveningTab  = 0

    @State private var showSettings = false
    @State private var showInsights = false

    @ObservedObject var syncManager = SyncManager.shared
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack {
            contentArea
                .safeAreaInset(edge: .bottom) { bottomBar }

            if syncManager.isSyncing {
                LoadingOverlay(message: syncManager.syncProgress)
            }
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                SettingsView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showSettings = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $showInsights) {
            NavigationStack {
                InsightsView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showInsights = false }
                        }
                    }
            }
        }
    }

    // MARK: - Content Area

    @ViewBuilder
    private var contentArea: some View {
        switch activeMode {
        case .morning:
            if morningTab == 0 {
                NavigationStack {
                    ReadinessView()
                        .toolbar { sharedToolbar }
                }
            } else {
                NavigationStack {
                    ContentView()
                        .toolbar { sharedToolbar }
                }
            }
        case .evening:
            if eveningTab == 0 {
                NavigationStack {
                    TrainingView()
                        .toolbar { sharedToolbar }
                }
            } else {
                NavigationStack {
                    NutritionView()
                        .toolbar { sharedToolbar }
                }
            }
        }
    }

    // MARK: - Shared Toolbar

    @ToolbarContentBuilder
    private var sharedToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { showInsights = true } label: {
                Image(systemName: "lightbulb")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
            }
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: 10) {
            subViewPicker
            modeToggle
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial, ignoresSafeAreaEdges: .bottom)
    }

    private var subViewPicker: some View {
        let (primary, secondary) = activeMode.subTitles
        let binding = subTabBinding
        return Picker("", selection: binding) {
            Text(primary).tag(0)
            Text(secondary).tag(1)
        }
        .pickerStyle(.segmented)
    }

    private var modeToggle: some View {
        HStack(spacing: 4) {
            ForEach(AppMode.allCases, id: \.self) { mode in
                modeButton(mode)
            }
        }
        .padding(4)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: 14))
    }

    private func modeButton(_ mode: AppMode) -> some View {
        let isActive = activeMode == mode
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                activeMode = mode
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: mode.systemImage).font(.caption)
                Text(mode.rawValue).font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(isActive ? Color.background : Color.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 10).fill(isActive ? Color.accent : Color.clear))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Sub-tab Binding

    private var subTabBinding: Binding<Int> {
        switch activeMode {
        case .morning: return $morningTab
        case .evening: return $eveningTab
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
