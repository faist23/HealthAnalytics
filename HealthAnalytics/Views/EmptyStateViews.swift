//
//  EmptyStateViews.swift
//  HealthAnalytics
//
//  Empty state components for when no data is available
//

import SwiftUI

// MARK: - Generic Empty State

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?
    
    init(
        icon: String,
        title: String,
        message: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: icon)
                .resizable()
                .scaledToFit()
                .frame(width: 60, height: 60)
                .foregroundStyle(.secondary.opacity(0.5))
            
            VStack(spacing: 8) {
                Text(title)
                    .font(.title3)
                    .fontWeight(.semibold)
                
                Text(message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            if let actionTitle = actionTitle, let action = action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.blue)
                        .cornerRadius(12)
                }
                .padding(.top, 8)
            }
        }
        .padding(40)
    }
}

// MARK: - Dashboard Empty State

struct DashboardEmptyState: View {
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .resizable()
                .scaledToFit()
                .frame(width: 80, height: 80)
                .foregroundStyle(.blue.opacity(0.5))
            
            VStack(spacing: 12) {
                Text("No Health Data Yet")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Start recording workouts and health metrics to see your dashboard come to life")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            
            VStack(spacing: 16) {
                QuickTipRow(
                    icon: "figure.run",
                    text: "Record a workout in the Health app"
                )
                QuickTipRow(
                    icon: "applewatch",
                    text: "Wear your Apple Watch during activities"
                )
                QuickTipRow(
                    icon: "moon.zzz.fill",
                    text: "Track your sleep with your device"
                )
            }
            .padding(.horizontal, 40)
            .padding(.top, 8)
        }
        .padding(.vertical, 60)
    }
}

// MARK: - Workouts Empty State

struct WorkoutsEmptyState: View {
    var body: some View {
        EmptyStateView(
            icon: "figure.run.circle",
            title: "No Workouts Yet",
            message: "Record your first workout in the Health app or connect Strava to see your activities here"
        )
    }
}

// MARK: - Nutrition Empty State

struct NutritionEmptyState: View {
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "fork.knife.circle")
                .resizable()
                .scaledToFit()
                .frame(width: 80, height: 80)
                .foregroundStyle(.green.opacity(0.5))
            
            VStack(spacing: 12) {
                Text("No Nutrition Data")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Log your meals in a nutrition tracking app to see how diet affects your performance")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Compatible apps:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                HStack(spacing: 16) {
                    Text("MyFitnessPal")
                    Text("•")
                        .foregroundStyle(.secondary)
                    Text("Lose It!")
                    Text("•")
                        .foregroundStyle(.secondary)
                    Text("Cronometer")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.top, 8)
        }
        .padding(.vertical, 40)
    }
}

// MARK: - Readiness Empty State

struct ReadinessEmptyState: View {
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "bolt.heart.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 80, height: 80)
                .foregroundStyle(.orange.opacity(0.5))
            
            VStack(spacing: 12) {
                Text("Building Your Profile")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("We need a few days of data to calculate your personalized readiness score")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            
            VStack(spacing: 16) {
                DataRequirementRow(
                    icon: "heart.fill",
                    title: "Heart Rate Variability",
                    status: .needed
                )
                DataRequirementRow(
                    icon: "bed.double.fill",
                    title: "Sleep Data",
                    status: .needed
                )
                DataRequirementRow(
                    icon: "figure.run",
                    title: "Recent Workouts",
                    status: .needed
                )
            }
            .padding(.horizontal, 40)
            .padding(.top, 8)
            
            Text("Keep recording your health data and check back soon")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 12)
        }
        .padding(.vertical, 40)
    }
}

// MARK: - Insights Empty State

struct InsightsEmptyState: View {
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "lightbulb.circle")
                .resizable()
                .scaledToFit()
                .frame(width: 80, height: 80)
                .foregroundStyle(.yellow.opacity(0.5))
            
            VStack(spacing: 12) {
                Text("Not Enough Data for Insights")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("We need more data to discover meaningful patterns and correlations")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            
            VStack(spacing: 12) {
                ProgressRequirementRow(
                    title: "Days of data",
                    current: 2,
                    required: 14
                )
                ProgressRequirementRow(
                    title: "Workouts logged",
                    current: 1,
                    required: 5
                )
            }
            .padding(.horizontal, 40)
            .padding(.top, 8)
        }
        .padding(.vertical, 40)
    }
}

// MARK: - Strava Not Connected State

struct StravaNotConnectedState: View {
    let onConnect: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "bicycle.circle")
                .resizable()
                .scaledToFit()
                .frame(width: 80, height: 80)
                .foregroundStyle(.orange.opacity(0.5))
            
            VStack(spacing: 12) {
                Text("Strava Not Connected")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Connect Strava to sync your activities with detailed metrics like power, pace, and routes")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            
            Button(action: onConnect) {
                HStack {
                    Image(systemName: "bicycle")
                    Text("Connect Strava")
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.orange)
                .cornerRadius(12)
            }
            .padding(.top, 8)
        }
        .padding(.vertical, 40)
    }
}

// MARK: - Supporting Views

struct QuickTipRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(.blue)
                .frame(width: 24)
            
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

enum DataStatus {
    case available
    case needed
    case partial
    
    var icon: String {
        switch self {
        case .available: return "checkmark.circle.fill"
        case .needed: return "circle"
        case .partial: return "circle.lefthalf.filled"
        }
    }
    
    var color: Color {
        switch self {
        case .available: return .green
        case .needed: return .secondary
        case .partial: return .orange
        }
    }
}

struct DataRequirementRow: View {
    let icon: String
    let title: String
    let status: DataStatus
    
    var body: some View {
        HStack {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(.blue)
                    .frame(width: 24)
                
                Text(title)
                    .font(.subheadline)
            }
            
            Spacer()
            
            Image(systemName: status.icon)
                .foregroundStyle(status.color)
        }
        .padding(.vertical, 4)
    }
}

struct ProgressRequirementRow: View {
    let title: String
    let current: Int
    let required: Int
    
    var progress: Double {
        min(Double(current) / Double(required), 1.0)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline)
                
                Spacer()
                
                Text("\(current)/\(required)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            ProgressView(value: progress)
                .tint(progress >= 1.0 ? .green : .blue)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

#Preview("Dashboard Empty") {
    DashboardEmptyState()
}

#Preview("Workouts Empty") {
    WorkoutsEmptyState()
}

#Preview("Nutrition Empty") {
    NutritionEmptyState()
}

#Preview("Readiness Empty") {
    ReadinessEmptyState()
}

#Preview("Insights Empty") {
    InsightsEmptyState()
}
