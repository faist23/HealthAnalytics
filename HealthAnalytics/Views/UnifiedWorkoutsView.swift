//
//  UnifiedWorkoutsView.swift
//  HealthAnalytics
//
//  Created by Craig Faist.
//

import SwiftUI
import SwiftData

struct UnifiedWorkoutsView: View {
    // Fetch ALL workouts from SwiftData, sorted by newest first
    @Query(sort: \StoredWorkout.startDate, order: .reverse) private var workouts: [StoredWorkout]
    
    var body: some View {
        List {
            ForEach(workouts) { workout in
                // 🟢 RENAMED: Use UnifiedWorkoutRow to avoid conflict
                UnifiedWorkoutRow(workout: workout)
            }
        }
        .listStyle(.plain)
        .navigationTitle("All Workouts")
    }
}

// 🟢 RENAMED STRUCT: Accepts StoredWorkout
struct UnifiedWorkoutRow: View {
    let workout: StoredWorkout
    
    var body: some View {
        HStack {
            Image(systemName: workout.source == "Strava" ? "bicycle" : "figure.run")
                .foregroundColor(workout.source == "Strava" ? .orange : .green)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(workout.workoutType.name)
                    .font(.headline)
                
                Text(workout.startDate.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text(formatDuration(workout.duration))
                    .font(.subheadline)
                    .bold()
                
                if let energy = workout.totalEnergyBurned, energy > 0 {
                    Text("\(Int(energy)) \(workout.source == "Strava" ? "kJ" : "kcal")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: duration) ?? ""
    }
}
