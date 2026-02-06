//
//  StravaActivitiesView.swift
//  HealthAnalytics
//
//  Created by Craig Faist on 1/25/26.
//


import SwiftUI

struct StravaActivitiesView: View {
    @StateObject private var stravaManager = StravaManager.shared
    @State private var activities: [StravaActivity] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    var body: some View {
        List {
            if isLoading {
                ProgressView("Loading activities...")
            } else if let error = errorMessage {
                Text(error)
                    .foregroundStyle(.red)
            } else if activities.isEmpty {
                Text("No activities found")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(activities) { activity in
                    StravaActivityRow(activity: activity)
                }
            }
        }
        .navigationTitle("Strava Activities")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        await loadActivities()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(isLoading)
            }
        }
        .task {
            if activities.isEmpty {
                await loadActivities()
            }
        }
    }
    
    private func loadActivities() async {
        isLoading = true
        errorMessage = nil
        
        do {
            activities = try await stravaManager.fetchActivities(page: 1, perPage: 30)
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
}

struct StravaActivityRow: View {
    let activity: StravaActivity
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(activity.name)
                    .font(.headline)
                
                Spacer()
                
                Text(activity.type)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.2))
                    .foregroundStyle(.orange)
                    .cornerRadius(4)
            }
            
            // 2. Stats Row: Time, Dist, Power, HR, and NOW Kilojoules
            HStack(spacing: 12) { // Slightly tighter spacing to fit more data
                Label(activity.durationFormatted, systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Label(String(format: "%.1f mi", activity.distanceMiles), systemImage: "map")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                // Existing Power
                if let avgWatts = activity.averageWatts, avgWatts > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "bolt.fill")
                        Text("\(Int(avgWatts))W")
                    }
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
                
                // 🟢 ADDED: Calories / Kilojoules
                // Uses 1:1 KJ to Calorie approximation standard in cycling
                if let kj = activity.kilojoules, kj > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "flame.fill")
                        Text("\(Int(kj))")
                    }
                    .font(.caption)
                    .foregroundStyle(.red)
                }
                
                // Existing Heart Rate
                if let avgHR = activity.averageHeartrate {
                    Label("\(Int(avgHR)) bpm", systemImage: "heart.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            // 3. Date Footer
            if let date = activity.startDateFormatted {
                Text(date, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        StravaActivitiesView()
    }
}
