//
//  SettingsView.swift
//  HealthAnalytics
//
//  Created by Craig Faist on 1/25/26.
//


import SwiftUI
import SwiftData

struct SettingsView: View {
    @StateObject private var healthKitManager = HealthKitManager.shared
    @ObservedObject var syncManager = SyncManager.shared
    @State private var isRequestingAuth = false
    @State private var showingClearConfirmation = false
    @State private var showingDataWindowAlert = false
    @State private var isResettingData = false
    @State private var isClearingCache = false
    @State private var isClassifyingWorkouts = false
    @AppStorage("historicalDataWindowYears") private var historicalDataWindowYears: Int = 0
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.modelContext) private var modelContext
    
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
                    
                    // MARK: - Analysis Settings
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Analysis Settings")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Label("Historical Data Window", systemImage: "calendar")
                                Spacer()
                                Menu {
                                    Button("All-Time") {
                                        updateDataWindow(0)
                                    }
                                    Divider()
                                    ForEach([5, 6, 7, 8, 9, 10], id: \.self) { years in
                                        Button("\(years) Years") {
                                            updateDataWindow(years)
                                        }
                                    }
                                } label: {
                                    HStack {
                                        Text(historicalDataWindowYears == 0 ? "All-Time" : "\(historicalDataWindowYears) Years")
                                            .foregroundStyle(.blue)
                                        Image(systemName: "chevron.up.chevron.down")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            
                            Text("Limits analysis to data from the selected time period. Useful for excluding old or inaccurate data (like virtual power estimates).")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding()
                    .cardStyle(for: .info)
                    
                    // MARK: - Machine Learning
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Machine Learning")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        
                        Button {
                            Task {
                                await classifyAllWorkouts()
                            }
                        } label: {
                            HStack {
                                Label("Auto-Classify Workouts", systemImage: "brain")
                                Spacer()
                                if isClassifyingWorkouts {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                }
                            }
                        }
                        .disabled(isClassifyingWorkouts)
                        
                        Text("Automatically assigns intent labels (Race, Tempo, Easy, etc.) to all workouts based on heart rate and other metrics. Labels are used for training load analysis and recommendations.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .cardStyle(for: .info)
                    
                    // MARK: - Data Management
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Data Management")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        
                        Button(role: .destructive) {
                            showingClearConfirmation = true
                        } label: {
                            HStack {
                                Label("Clear Analysis Cache", systemImage: "trash")
                                Spacer()
                            }
                        }
                        
                        Text("This will remove all cached analysis and trained models. Your raw health and workout data will remain safe.")
                            .font(.caption)
                            .foregroundStyle(.secondary)


                        Button(role: .destructive) {
                            // Trigger reset
                            isResettingData = true
                            Task {
                                await SyncManager.shared.resetAllData()
                                isResettingData = false
                            }
                        } label: {
                            HStack {
                                Label("Reset Workout & Wellness Data", systemImage: "arrow.counterclockwise")
                                Spacer()
                                if isResettingData {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                }
                            }
                        }
                        .disabled(isResettingData || syncManager.isSyncing)
                        
                        Text("Deletes all duplicate workouts and re-syncs from scratch.")
                            .font(.caption)
                        .foregroundStyle(.secondary)                    }
                   
                    .padding()
                    .cardStyle(for: .info)
                }
                .padding(.horizontal)
                .padding(.top, 12)
            }
            
            // Loading overlay when syncing or resetting
            if syncManager.isSyncing || isResettingData {
                if syncManager.isSyncing {
                    LoadingOverlay(
                        message: syncManager.syncProgress,
                        showProgress: syncManager.syncProgress.contains("Sync complete"),
                        progress: nil
                    )
                } else if isResettingData {
                    LoadingOverlay(message: "Resetting data...")
                }
            }
        }
        .navigationTitle("Settings")
        .confirmationDialog(
            "Clear Analysis Cache?",
            isPresented: $showingClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear All Cached Data", role: .destructive) {
                isClearingCache = true
                Task {
                    PredictionCache.shared.invalidate()
                    try? await Task.sleep(nanoseconds: 500_000_000) // Brief delay for UX
                    isClearingCache = false
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure? This will force the app to re-analyze your training data and re-train models from scratch.")
        }
        .alert("Data Window Changed", isPresented: $showingDataWindowAlert) {
            Button("Reload Data", role: .destructive) {
                Task {
                    // Clear all caches first
                    PredictionCache.shared.invalidate()
                    
                    // Reset and reload data
                    await SyncManager.shared.resetAllData()
                    
                    // Post notification to force view models to recalculate
                    NotificationCenter.default.post(name: NSNotification.Name("DataWindowChanged"), object: nil)
                }
            }
            Button("Later", role: .cancel) {}
        } message: {
            Text("To apply the new data window, the app needs to reload your data. This will clear cached analysis and re-sync from HealthKit and Strava.")
        }
    }
    
    private func updateDataWindow(_ years: Int) {
        let oldValue = historicalDataWindowYears
        historicalDataWindowYears = years
        
        if oldValue != years {
            showingDataWindowAlert = true
        }
    }
    
    @MainActor
    private func classifyAllWorkouts() async {
        isClassifyingWorkouts = true
        
        // Run classification in background actor
        let container = HealthDataContainer.shared
        let actor = DataPersistenceActor(modelContainer: container)
        
        await actor.autoClassifyWorkoutIntents()
        
        // Notify that data changed
        NotificationCenter.default.post(name: NSNotification.Name("DataSyncCompleted"), object: nil)
        
        isClassifyingWorkouts = false
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}


