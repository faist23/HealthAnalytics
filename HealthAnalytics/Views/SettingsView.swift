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
    @AppStorage("preferredHRVSource") private var preferredHRVSource: String = "auto"
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        ZStack {
            // 🔹 Tab background color (same system as other tabs)
            TabBackgroundColor.settings(for: colorScheme)
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: .spacingMd) {
                    
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
                            HStack {
                                Label("Strava", systemImage: "bicycle")
                                Spacer()
                                Text(StravaManager.shared.isAuthenticated
                                     ? (StravaManager.shared.athlete?.fullName ?? "Connected")
                                     : "Not connected")
                                    .font(.caption)
                                    .foregroundStyle(StravaManager.shared.isAuthenticated
                                                     ? Color.statusOptimal : Color.textTertiary)
                            }
                        }

                        NavigationLink {
                            WorkoutAuditView()
                        } label: {
                            Label("Today's Workouts", systemImage: "figure.run.circle")
                        }

                        NavigationLink {
                            CoachMemoryView()
                        } label: {
                            Label("Coach Memory", systemImage: "brain.head.profile")
                        }

                        Divider()

                        // MARK: HRV Source Preference
                        VStack(alignment: .leading, spacing: 6) {
                            NavigationLink {
                                List {
                                    Section {
                                        Button {
                                            preferredHRVSource = "auto"
                                        } label: {
                                            HStack {
                                                Text("Auto-detect")
                                                Spacer()
                                                if preferredHRVSource == "auto" {
                                                    Image(systemName: "checkmark")
                                                        .foregroundStyle(Color.accent)
                                                }
                                            }
                                        }
                                        Button {
                                            preferredHRVSource = "appleWatch"
                                        } label: {
                                            HStack {
                                                Text("Apple Watch")
                                                Spacer()
                                                if preferredHRVSource == "appleWatch" {
                                                    Image(systemName: "checkmark")
                                                        .foregroundStyle(Color.accent)
                                                }
                                            }
                                        }
                                        Button {
                                            preferredHRVSource = "dedicatedDevice"
                                        } label: {
                                            HStack {
                                                Text("Dedicated Device (Polar, Garmin, Oura)")
                                                Spacer()
                                                if preferredHRVSource == "dedicatedDevice" {
                                                    Image(systemName: "checkmark")
                                                        .foregroundStyle(Color.accent)
                                                }
                                            }
                                        }
                                    } footer: {
                                        Text("Training DNA pattern detection uses this source when multiple devices write HRV to HealthKit.")
                                            .font(.system(size: 13, weight: .regular, design: .default))
                                            .foregroundStyle(Color.textSecondary)
                                    }
                                }
                                .navigationTitle("HRV Source")
                            } label: {
                                HStack {
                                    Label("HRV Source", systemImage: "waveform.path.ecg")
                                    Spacer()
                                    Text(hrvSourceLabel)
                                        .font(.coachGuidance)
                                        .foregroundStyle(Color.textSecondary)
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(Color.textTertiary)
                                }
                            }

                            Text("Controls which device's HRV readings are used for Training DNA pattern detection.")
                                .font(.system(size: 13, weight: .regular, design: .default))
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                    .padding()
                    .cardStyle(for: .info)

                    // MARK: - Training Zones (FTP)
                    FTPSettingsCard()

                    // MARK: - Strain Sensitivity
                    StrainSensitivityCard()

                    // MARK: - Analysis Settings
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Analysis Settings")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        
                        VStack(alignment: .leading, spacing: .spacingSm) {
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
                                            .foregroundStyle(Color.accent)
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
    
    private var hrvSourceLabel: String {
        switch preferredHRVSource {
        case "appleWatch":      return "Apple Watch"
        case "dedicatedDevice": return "Dedicated Device"
        default:                return "Auto"
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

// MARK: - FTP Settings Card

private struct FTPSettingsCard: View {
    @Query(sort: \StoredFTPSnapshot.date, order: .reverse) private var snapshots: [StoredFTPSnapshot]
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var syncManager = SyncManager.shared
    @State private var isFetching = false
    @State private var fetchMessage: String?

    private var currentFTP: Int {
        snapshots.first?.watts ?? UserDefaults.standard.integer(forKey: "strava_ftp")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Training Zones")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
                if StravaManager.shared.isAuthenticated {
                    Button {
                        Task { await refreshFTP() }
                    } label: {
                        if isFetching {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Label("Sync", systemImage: "arrow.clockwise")
                                .font(.caption)
                                .foregroundStyle(Color.accent)
                        }
                    }
                    .disabled(isFetching)
                }
            }

            HStack {
                Label("FTP", systemImage: "bolt.fill")
                Spacer()
                if currentFTP > 0 {
                    Text("\(currentFTP) W")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.accent)
                } else {
                    Text("Not set — using 200W default")
                        .font(.caption)
                        .foregroundStyle(Color.statusWarning)
                }
            }

            if let msg = fetchMessage {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(currentFTP > 0 ? Color.statusOptimal : Color.statusWarning)
            } else if currentFTP > 0 {
                Text("Used for zone-based load calculations on Strava cycling workouts.")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            } else {
                Text("Set your FTP in Strava profile, then tap Sync. Zone-based intensity calculations will be used for all cycling workouts.")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }

            if let progress = syncManager.zoneBackfillProgress {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.75)
                    Text("Re-computing zones (\(progress.current)/\(progress.total))...")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
            }

            Divider()

            NavigationLink {
                FTPHistoryView()
            } label: {
                HStack {
                    Text("Manage FTP History")
                        .font(.subheadline)
                        .foregroundStyle(Color.accent)
                    Spacer()
                    if !snapshots.isEmpty {
                        Text("\(snapshots.count) \(snapshots.count == 1 ? "entry" : "entries")")
                            .font(.caption)
                            .foregroundStyle(Color.textTertiary)
                    }
                }
            }
        }
        .padding()
        .cardStyle(for: .info)
    }

    private func refreshFTP() async {
        isFetching = true
        fetchMessage = nil
        // Clear the 24h guard so StravaConnectionView doesn't also skip on next open
        UserDefaults.standard.removeObject(forKey: "strava_athlete_last_fetch")
        do {
            let watts = try await StravaManager.shared.fetchAthleteProfile()
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "strava_athlete_last_fetch")
            if let w = watts {
                StoredFTPSnapshot.upsertIfChanged(watts: w, source: "strava_profile", context: modelContext)
                fetchMessage = "FTP updated: \(w)W"
            } else {
                fetchMessage = "Strava profile has no FTP set. Add it at strava.com/settings."
            }
        } catch {
            fetchMessage = "Could not reach Strava. Check your connection."
        }
        isFetching = false
    }
}

private struct StrainSensitivityCard: View {
    @AppStorage("strainSensitivityOffset") private var offset: Double = 0.0

    /// Representative raw strain for a hard 90-min effort at baseline normalization 70.
    /// rawStrain ≈ 50 units → baseline score of 15.0 at normalization 70.
    private static let referenceRawStrain: Double = 50.0
    private static let baselineNorm: Double = 70.0

    private var previewScore: Double {
        let clampedOffset = max(-0.2, min(0.2, offset))
        let effectiveNorm = Self.baselineNorm * (1.0 - clampedOffset)
        return min(21.0, Self.referenceRawStrain / effectiveNorm * 21.0)
    }

    private var offsetLabel: String {
        if offset < -0.05 { return "Less sensitive" }
        if offset > 0.05  { return "More sensitive" }
        return "Default"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Strain Sensitivity")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Reset") { offset = 0.0 }
                    .font(.caption)
                    .foregroundStyle(Color.accent)
                    .opacity(abs(offset) < 0.01 ? 0 : 1)
            }

            Text("Adjust how heavily cardiovascular effort maps to your 0–21 strain score.")
                .font(.caption)
                .foregroundStyle(Color.textSecondary)

            VStack(spacing: 6) {
                Slider(value: $offset, in: -0.2...0.2, step: 0.01)
                    .tint(Color.accent)

                HStack {
                    Text("Lower")
                        .font(.caption2)
                        .foregroundStyle(Color.textTertiary)
                    Spacer()
                    Text(offsetLabel)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.accent)
                    Spacer()
                    Text("Higher")
                        .font(.caption2)
                        .foregroundStyle(Color.textTertiary)
                }
            }

            Divider()

            HStack {
                Image(systemName: "waveform.path.ecg")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                Text("A hard 90-min effort would score")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                HStack(spacing: 4) {
                    Text("~15")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Color.textTertiary)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.textTertiary)
                    Text(String(format: "%.1f", previewScore))
                        .font(.system(.caption, design: .monospaced))
                        .fontWeight(.semibold)
                        .foregroundStyle(CardiovascularStrainService.color(for: previewScore))
                }
            }
        }
        .padding()
        .cardStyle(for: .info)
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}


