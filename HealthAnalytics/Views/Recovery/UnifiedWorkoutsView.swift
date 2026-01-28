import SwiftUI

struct UnifiedWorkoutsView: View {
    @StateObject private var viewModel = UnifiedWorkoutsViewModel()
    @State private var selectedFilter: WorkoutFilter = .all
    
    var body: some View {
        VStack(spacing: 0) {
            // Filter and sort controls
            VStack(spacing: 12) {
                // Filter chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(WorkoutFilter.allCases) { filter in
                            FilterChip(
                                filter: filter,
                                isSelected: selectedFilter == filter,
                                count: viewModel.workoutCount(for: filter)
                            ) {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    selectedFilter = filter
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                
                // Stats summary
                WorkoutStats(workouts: filteredWorkouts)
            }
            .padding(.vertical)
            .background(Color(.systemBackground))
            
            // Workout list
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(filteredWorkouts) { workout in
                        UnifiedWorkoutCard(workout: workout)
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
        }
        .navigationTitle("Workouts")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        await viewModel.loadWorkouts()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(viewModel.isLoading)
            }
        }
        .task {
            await viewModel.loadWorkouts()
        }
        .overlay {
            if viewModel.isLoading {
                LoadingOverlay()
            }
        }
    }
    
    private var filteredWorkouts: [UnifiedWorkout] {
        switch selectedFilter {
        case .all:
            return viewModel.workouts
        case .running:
            return viewModel.workouts.filter { $0.activityType == "Run" || $0.activityType == "Running" }
        case .cycling:
            return viewModel.workouts.filter { $0.activityType == "Ride" || $0.activityType == "Cycling" }
        case .swimming:
            return viewModel.workouts.filter { $0.activityType == "Swim" || $0.activityType == "Swimming" }
        case .strength:
            return viewModel.workouts.filter { $0.activityType.contains("Strength") || $0.activityType.contains("Weight") }
        case .other:
            let mainTypes = ["Run", "Running", "Ride", "Cycling", "Swim", "Swimming"]
            return viewModel.workouts.filter { workout in
                !mainTypes.contains(workout.activityType) && !workout.activityType.contains("Strength")
            }
        }
    }
}

// MARK: - Unified Workouts ViewModel

@MainActor
class UnifiedWorkoutsViewModel: ObservableObject {
    @Published var workouts: [UnifiedWorkout] = []
    @Published var isLoading = false
    
    private let healthKitManager = HealthKitManager.shared
    private let stravaManager = StravaManager.shared
    
    func loadWorkouts() async {
        isLoading = true
        
        let endDate = Date()
        let startDate = Calendar.current.date(byAdding: .month, value: -3, to: endDate) ?? endDate
        
        do {
            // Fetch from both sources
            async let hkWorkouts = healthKitManager.fetchWorkouts(startDate: startDate, endDate: endDate)
            let stravaActivities = try await stravaManager.fetchActivities(page: 1, perPage: 100)
            
            let healthKitWorkouts = try await hkWorkouts
            
            // Deduplicate
            let (hkOnly, stravaOnly, matched) = WorkoutMatcher.deduplicateWorkouts(
                healthKitWorkouts: healthKitWorkouts,
                stravaActivities: stravaActivities
            )
            
            var unified: [UnifiedWorkout] = []
            
            // Add HealthKit-only workouts
            for workout in hkOnly {
                unified.append(UnifiedWorkout(
                    source: .healthKit,
                    date: workout.startDate,
                    activityType: workout.workoutName,
                    duration: workout.duration,
                    distance: workout.totalDistance,
                    calories: workout.totalEnergyBurned,
                    averagePower: workout.averagePower,
                    averageHeartRate: nil
                ))
            }
            
            // Add Strava-only activities
            for activity in stravaOnly {
                guard let date = activity.startDateFormatted else { continue }
                unified.append(UnifiedWorkout(
                    source: .strava,
                    date: date,
                    activityType: activity.type,
                    duration: Double(activity.movingTime),
                    distance: activity.distance,
                    calories: nil,
                    averagePower: activity.averageWatts,
                    averageHeartRate: activity.averageHeartrate
                ))
            }
            
            // Add matched workouts (prefer Strava data)
            for (_, stravaActivity) in matched {
                guard let date = stravaActivity.startDateFormatted else { continue }
                unified.append(UnifiedWorkout(
                    source: .both,
                    date: date,
                    activityType: stravaActivity.type,
                    duration: Double(stravaActivity.movingTime),
                    distance: stravaActivity.distance,
                    calories: nil,
                    averagePower: stravaActivity.averageWatts,
                    averageHeartRate: stravaActivity.averageHeartrate
                ))
            }
            
            // Sort by date (most recent first)
            self.workouts = unified.sorted { $0.date > $1.date }
            
        } catch {
            print("Error loading workouts: \(error)")
        }
        
        isLoading = false
    }
    
    func workoutCount(for filter: WorkoutFilter) -> Int {
        switch filter {
        case .all:
            return workouts.count
        case .running:
            return workouts.filter { $0.activityType == "Run" || $0.activityType == "Running" }.count
        case .cycling:
            return workouts.filter { $0.activityType == "Ride" || $0.activityType == "Cycling" }.count
        case .swimming:
            return workouts.filter { $0.activityType == "Swim" || $0.activityType == "Swimming" }.count
        case .strength:
            return workouts.filter { $0.activityType.contains("Strength") || $0.activityType.contains("Weight") }.count
        case .other:
            let mainTypes = ["Run", "Running", "Ride", "Cycling", "Swim", "Swimming"]
            return workouts.filter { workout in
                !mainTypes.contains(workout.activityType) && !workout.activityType.contains("Strength")
            }.count
        }
    }
}

// MARK: - Models

struct UnifiedWorkout: Identifiable {
    let id = UUID()
    let source: WorkoutSource
    let date: Date
    let activityType: String
    let duration: TimeInterval
    let distance: Double?
    let calories: Double?
    let averagePower: Double?
    let averageHeartRate: Double?
    
    enum WorkoutSource {
        case healthKit
        case strava
        case both
        
        var icon: String {
            switch self {
            case .healthKit: return "heart.fill"
            case .strava: return "bicycle"
            case .both: return "arrow.triangle.2.circlepath"
            }
        }
        
        var color: Color {
            switch self {
            case .healthKit: return .red
            case .strava: return .orange
            case .both: return .blue
            }
        }
    }
    
    var formattedDuration: String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) / 60 % 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
    
    var formattedDistance: String? {
        guard let dist = distance, dist > 0 else { return nil }
        let miles = dist / 1609.34
        return String(format: "%.2f mi", miles)
    }
    
    var formattedCalories: String? {
        guard let cal = calories else { return nil }
        return "\(Int(cal)) cal"
    }
    
    var formattedPower: String? {
        guard let power = averagePower, power > 0 else { return nil }
        return "\(Int(power)) W"
    }
    
    var formattedHeartRate: String? {
        guard let hr = averageHeartRate else { return nil }
        return "\(Int(hr)) bpm"
    }
}

enum WorkoutFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case running = "Running"
    case cycling = "Cycling"
    case swimming = "Swimming"
    case strength = "Strength"
    case other = "Other"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .all: return "list.bullet"
        case .running: return "figure.run"
        case .cycling: return "bicycle"
        case .swimming: return "figure.pool.swim"
        case .strength: return "dumbbell.fill"
        case .other: return "ellipsis.circle"
        }
    }
}

// MARK: - Filter Chip

struct FilterChip: View {
    let filter: WorkoutFilter
    let isSelected: Bool
    let count: Int
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: filter.icon)
                    .font(.caption)
                
                Text(filter.rawValue)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                if count > 0 {
                    Text("\(count)")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(isSelected ? Color.white.opacity(0.3) : Color(.systemGray5))
                        )
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isSelected ? Color.blue : Color(.systemGray6))
            )
            .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Workout Stats

struct WorkoutStats: View {
    let workouts: [UnifiedWorkout]
    
    var totalDuration: TimeInterval {
        workouts.map { $0.duration }.reduce(0, +)
    }
    
    var totalDistance: Double {
        workouts.compactMap { $0.distance }.reduce(0, +)
    }
    
    var totalCalories: Double {
        workouts.compactMap { $0.calories }.reduce(0, +)
    }
    
    var body: some View {
        HStack(spacing: 20) {
            StatPill(
                icon: "clock.fill",
                value: formattedTotalDuration,
                label: "Time",
                color: .blue
            )
            
            if totalDistance > 0 {
                StatPill(
                    icon: "map.fill",
                    value: String(format: "%.1f", totalDistance / 1609.34),
                    label: "Miles",
                    color: .green
                )
            }
            
            if totalCalories > 0 {
                StatPill(
                    icon: "flame.fill",
                    value: "\(Int(totalCalories))",
                    label: "Cal",
                    color: .orange
                )
            }
        }
        .padding(.horizontal)
    }
    
    private var formattedTotalDuration: String {
        let hours = Int(totalDuration) / 3600
        let minutes = Int(totalDuration) / 60 % 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

struct StatPill: View {
    let icon: String
    let value: String
    let label: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
            
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.subheadline)
                    .fontWeight(.bold)
                
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(color.opacity(0.1))
        )
    }
}

// MARK: - Unified Workout Card

struct UnifiedWorkoutCard: View {
    let workout: UnifiedWorkout
    
    var body: some View {
        HStack(spacing: 16) {
            // Activity icon
            VStack(spacing: 6) {
                Image(systemName: activityIcon)
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 50)
                    .background(
                        Circle()
                            .fill(activityColor.gradient)
                    )
                
                // Source badge
                Image(systemName: workout.source.icon)
                    .font(.caption2)
                    .foregroundStyle(workout.source.color)
            }
            
            // Workout details
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(workout.activityType)
                        .font(.headline)
                    
                    Spacer()
                    
                    Text(workout.date, format: .dateTime.month(.abbreviated).day())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Text(workout.date, format: .dateTime.hour().minute())
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                
                // Metrics row
                HStack(spacing: 12) {
                    Label(workout.formattedDuration, systemImage: "clock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    if let distance = workout.formattedDistance {
                        Label(distance, systemImage: "map")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    if let power = workout.formattedPower {
                        HStack(spacing: 4) {
                            Image(systemName: "bolt.fill")
                            Text(power)
                        }
                        .font(.caption)
                        .foregroundStyle(.orange)
                    }
                    
                    if let hr = workout.formattedHeartRate {
                        Label(hr, systemImage: "heart.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.05), radius: 10, y: 5)
        )
    }
    
    private var activityIcon: String {
        switch workout.activityType.lowercased() {
        case let type where type.contains("run"):
            return "figure.run"
        case let type where type.contains("ride") || type.contains("cycl"):
            return "bicycle"
        case let type where type.contains("swim"):
            return "figure.pool.swim"
        case let type where type.contains("walk"):
            return "figure.walk"
        case let type where type.contains("hik"):
            return "figure.hiking"
        case let type where type.contains("strength") || type.contains("weight"):
            return "dumbbell.fill"
        case let type where type.contains("yoga"):
            return "figure.yoga"
        default:
            return "figure.mixed.cardio"
        }
    }
    
    private var activityColor: Color {
        switch workout.activityType.lowercased() {
        case let type where type.contains("run"):
            return .blue
        case let type where type.contains("ride") || type.contains("cycl"):
            return .orange
        case let type where type.contains("swim"):
            return .cyan
        case let type where type.contains("strength") || type.contains("weight"):
            return .purple
        default:
            return .green
        }
    }
}

#Preview {
    NavigationStack {
        UnifiedWorkoutsView()
    }
}
