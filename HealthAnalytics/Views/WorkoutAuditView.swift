//
//  WorkoutAuditView.swift
//  HealthAnalytics
//
//  Shows today's workouts with auto-detected categories so users can verify
//  the app's workout classification is accurate.
//

import SwiftUI
import HealthKit
import SwiftData

struct WorkoutAuditView: View {
    @StateObject private var viewModel = ReadinessViewModel()
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        ZStack {
            Color.background.ignoresSafeArea()

            if viewModel.isLoading {
                LoadingOverlay(message: "Loading workouts...")
            } else if viewModel.todayWorkouts.isEmpty {
                VStack(spacing: .spacingSm) {
                    Text("No workouts recorded today")
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                    Text("Workouts appear here after syncing from Apple Health.")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                        .multilineTextAlignment(.center)
                }
                .padding()
            } else {
                ScrollView {
                    VStack(spacing: .spacingSm) {
                        ForEach(viewModel.todayWorkouts.sorted { $0.startDate < $1.startDate }) { workout in
                            WorkoutAuditRow(workout: workout)
                                .padding(.horizontal)
                        }
                    }
                    .padding(.vertical)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("Today's Workouts")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if viewModel.modelContainer == nil {
                viewModel.configure(container: modelContext.container)
            }
            await viewModel.analyze(modelContext: modelContext)
        }
    }
}

// MARK: - Row

private struct WorkoutAuditRow: View {
    let workout: WorkoutData

    var body: some View {
        VStack(spacing: 4) {
            // Primary row: icon + name + duration
            HStack {
                Image(systemName: workoutIcon(for: workout.workoutType))
                    .font(.subheadline)
                    .foregroundStyle(categoryColor)
                    .frame(width: 24)
                Text(workout.workoutName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                Spacer()
                Text(formatDuration(workout.duration))
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(Color.textSecondary)
            }

            // Secondary row: category + avg HR
            HStack {
                Text(categoryLabel)
                    .font(.caption)
                    .foregroundStyle(categoryColor)
                Text("•")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
                if let hr = workout.averageHeartRate {
                    Text("Avg HR: \(Int(hr)) bpm")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                } else {
                    Text("No HR data")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                }
                Spacer()
            }
        }
        .padding()
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: .radiusMd, style: .continuous))
    }

    private var categoryLabel: String {
        if isStrength { return "Strength" }
        guard let hr = workout.averageHeartRate else { return "Other" }
        // Estimate zone from average HR relative to a 185 bpm max (population average)
        let pct = hr / 185.0
        if pct >= 0.8 { return "Cardio Z4-5" }
        if pct >= 0.6 { return "Cardio Z1-3" }
        return "Other"
    }

    private var categoryColor: Color {
        if isStrength { return Color.textSecondary }
        guard let hr = workout.averageHeartRate else { return Color.textTertiary }
        let pct = hr / 185.0
        if pct >= 0.8 { return Color.statusWarning }
        if pct >= 0.6 { return Color.statusOptimal }
        return Color.textTertiary
    }

    private var isStrength: Bool {
        let type = workout.workoutType
        return type == .traditionalStrengthTraining
            || type == .functionalStrengthTraining
            || type == .coreTraining
            || type == .flexibility
            || type == .crossTraining
            || type == .highIntensityIntervalTraining
            || workout.workoutName.lowercased().contains("strength")
            || workout.workoutName.lowercased().contains("weight")
            || workout.workoutName.lowercased().contains("lift")
            || workout.workoutName.lowercased().contains("gym")
            || workout.workoutName.lowercased().contains("dumbbell")
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        let s = Int(seconds) % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    private func workoutIcon(for type: HKWorkoutActivityType) -> String {
        switch type {
        case .running:      return "figure.run"
        case .cycling:      return "bicycle"
        case .swimming:     return "figure.pool.swim"
        case .walking:      return "figure.walk"
        case .hiking:       return "figure.hiking"
        case .traditionalStrengthTraining, .functionalStrengthTraining:
                            return "dumbbell.fill"
        case .yoga:         return "figure.yoga"
        case .highIntensityIntervalTraining: return "bolt.fill"
        case .rowing:       return "figure.rowing"
        default:            return "figure.mixed.cardio"
        }
    }
}

#Preview {
    NavigationStack {
        WorkoutAuditView()
    }
}
