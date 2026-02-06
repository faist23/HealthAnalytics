//
//  UnifiedWorkoutsView.swift
//  HealthAnalytics
//
//  Created by Craig Faist.
//

import SwiftUI
import SwiftData

struct UnifiedWorkoutsView: View {
    @Query(sort: \StoredWorkout.startDate, order: .reverse) private var workouts: [StoredWorkout]
    
    var body: some View {
        List {
            if workouts.isEmpty {
                ContentUnavailableView("No Workouts", systemImage: "figure.run", description: Text("Complete a workout or sync with Strava/HealthKit."))
            } else {
                ForEach(workouts) { workout in
                    UnifiedWorkoutRow(workout: workout)
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("All Workouts")
    }
}

struct UnifiedWorkoutRow: View {
    let workout: StoredWorkout
    
    var isStrava: Bool {
        workout.source == "Strava"
    }
    
    // Use the custom title if available (Strava), otherwise generic type (Apple)
    var displayName: String {
        workout.title ?? workout.workoutType.name
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 1. Header: Name and Source Badge
            HStack {
                Text(displayName)
                    .font(.headline)
                    .lineLimit(1)
                
                Spacer()
                
                // Source Badge
                HStack(spacing: 4) {
                    Image(systemName: isStrava ? "bicycle" : "apple.logo") // Custom icons
                        .font(.caption2)
                    Text(workout.source)
                        .font(.caption2)
                        .fontWeight(.bold)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(isStrava ? Color.orange.opacity(0.15) : Color.pink.opacity(0.15))
                .foregroundStyle(isStrava ? Color.orange : Color.pink)
                .cornerRadius(6)
            }
            
            // 2. Stats Row
            HStack(spacing: 16) {
                // Duration
                Label(formatDuration(workout.duration), systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                // Distance
                if let distance = workout.distance, distance > 0 {
                    Label(String(format: "%.1f mi", distance / 1609.34), systemImage: "map")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                // Power (Orange)
                if let power = workout.averagePower, power > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "bolt.fill")
                        Text("\(Int(power))W")
                    }
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
                
                // Calories/KJ (Red)
                if let energy = workout.totalEnergyBurned, energy > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "flame.fill")
                        Text("\(Int(energy))")
                    }
                    .font(.caption)
                    .foregroundStyle(.red)
                }
                
                Spacer()
            }
            
            // 3. Date Footer
            Text(workout.startDate.formatted(date: .abbreviated, time: .shortened))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: duration) ?? ""
    }
}
