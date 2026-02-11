//
//  DataAccessService.swift (FIXED)
//  HealthAnalytics
//
//  CRITICAL FIX: Use mainContext instead of creating new contexts
//

import Foundation
import SwiftData

@MainActor
class DataAccessService {
    private let modelContainer: ModelContainer
    
    // ✅ ADD: Computed property for main context
    private var context: ModelContext {
        modelContainer.mainContext
    }
    
    init(container: ModelContainer) {
        self.modelContainer = container
    }
    
    // MARK: - Workout Queries
    
    /// Fetch all workouts within a date range
    func fetchWorkouts(from startDate: Date, to endDate: Date) throws -> [WorkoutData] {
        // ✅ CHANGED: Use mainContext instead of creating new one
        let descriptor = FetchDescriptor<StoredWorkout>(
            predicate: #Predicate { workout in
                workout.startDate >= startDate && workout.startDate <= endDate
            },
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        
        let stored = try context.fetch(descriptor)
        return stored.map { convertToWorkoutData($0) }
    }
    
    /// Fetch all workouts (for ML training)
    func fetchAllWorkouts() throws -> [WorkoutData] {
        let descriptor = FetchDescriptor<StoredWorkout>(
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        
        let stored = try context.fetch(descriptor)
        return stored.map { convertToWorkoutData($0) }
    }
    
    /// Fetch workouts of a specific type
    func fetchWorkouts(ofType typeInt: Int) throws -> [WorkoutData] {
        let descriptor = FetchDescriptor<StoredWorkout>(
            predicate: #Predicate { $0.workoutTypeInt == typeInt },
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        
        let stored = try context.fetch(descriptor)
        return stored.map { convertToWorkoutData($0) }
    }
    
    // MARK: - Health Metrics Queries
    
    /// Fetch health metrics of a specific type
    func fetchHealthMetrics(type: String, from startDate: Date? = nil, to endDate: Date? = nil) throws -> [HealthDataPoint] {
        var descriptor: FetchDescriptor<StoredHealthMetric>
        
        if let start = startDate, let end = endDate {
            descriptor = FetchDescriptor<StoredHealthMetric>(
                predicate: #Predicate { metric in
                    metric.type == type && metric.date >= start && metric.date <= end
                },
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
        } else {
            descriptor = FetchDescriptor<StoredHealthMetric>(
                predicate: #Predicate { $0.type == type },
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
        }
        
        let stored = try context.fetch(descriptor)
        return stored.map { HealthDataPoint(date: $0.date, value: $0.value) }
    }
    
    /// Get most recent value for a metric type
    func getLatestMetricValue(type: String) throws -> Double? {
        let points = try fetchHealthMetrics(type: type)
        return points.first?.value
    }
    
    // MARK: - Nutrition Queries
    
    /// Fetch nutrition data for a date range
    func fetchNutrition(from startDate: Date, to endDate: Date) throws -> [DailyNutrition] {
        let descriptor = FetchDescriptor<StoredNutrition>(
            predicate: #Predicate { nutrition in
                nutrition.date >= startDate && nutrition.date <= endDate
            },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        
        let stored = try context.fetch(descriptor)
        return stored.map { convertToDailyNutrition($0) }
    }
    
    /// Fetch all nutrition data
    func fetchAllNutrition() throws -> [DailyNutrition] {
        let descriptor = FetchDescriptor<StoredNutrition>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        
        let stored = try context.fetch(descriptor)
        return stored.map { convertToDailyNutrition($0) }
    }
    
    /// Get nutrition for a specific date
    func getNutrition(for date: Date) throws -> DailyNutrition? {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current  // ✅ ADDED: Explicit timezone
        let dateString = formatter.string(from: dayStart)
        
        let descriptor = FetchDescriptor<StoredNutrition>(
            predicate: #Predicate { $0.dateString == dateString }
        )
        
        guard let stored = try context.fetch(descriptor).first else {
            return nil
        }
        
        return convertToDailyNutrition(stored)
    }
    
    // MARK: - Statistics
    
    /// Get data availability summary
    func getDataSummary() throws -> DataSummary {
        let workoutCount = try context.fetchCount(FetchDescriptor<StoredWorkout>())
        
        // ✅ CHANGED: Use capitalized type names to match what SyncManager saves
        let sleepCount = try context.fetchCount(FetchDescriptor<StoredHealthMetric>(
            predicate: #Predicate { $0.type == "Sleep" }  // Was "sleep"
        ))
        let hrvCount = try context.fetchCount(FetchDescriptor<StoredHealthMetric>(
            predicate: #Predicate { $0.type == "HRV" }  // Was "hrv"
        ))
        let rhrCount = try context.fetchCount(FetchDescriptor<StoredHealthMetric>(
            predicate: #Predicate { $0.type == "RHR" }  // Was "restingHR"
        ))
        let nutritionCount = try context.fetchCount(FetchDescriptor<StoredNutrition>())
        
        // Get date ranges
        let workouts = try fetchAllWorkouts()
        let oldestWorkout = workouts.map(\.startDate).min()
        let newestWorkout = workouts.map(\.startDate).max()
        
        return DataSummary(
            workoutCount: workoutCount,
            sleepDays: sleepCount,
            hrvDays: hrvCount,
            rhrDays: rhrCount,
            nutritionDays: nutritionCount,
            oldestDataPoint: oldestWorkout,
            newestDataPoint: newestWorkout
        )
    }
    
    struct DataSummary {
        let workoutCount: Int
        let sleepDays: Int
        let hrvDays: Int
        let rhrDays: Int
        let nutritionDays: Int
        let oldestDataPoint: Date?
        let newestDataPoint: Date?
        
        var hasMinimumData: Bool {
            sleepDays >= 7 &&
            (hrvDays >= 7 || rhrDays >= 7) &&
            workoutCount >= 5
        }
        
        var dataSpanYears: Int? {
            guard let oldest = oldestDataPoint,
                  let newest = newestDataPoint else {
                return nil
            }
            
            return Calendar.current.dateComponents([.year], from: oldest, to: newest).year
        }
    }
    
    // MARK: - Converters
    
    private func convertToWorkoutData(_ stored: StoredWorkout) -> WorkoutData {
        WorkoutData(
            id: UUID(uuidString: stored.id) ?? UUID(),
            title: stored.title,
            workoutType: stored.workoutType,
            startDate: stored.startDate,
            endDate: stored.startDate.addingTimeInterval(stored.duration),
            duration: stored.duration,
            totalEnergyBurned: stored.totalEnergyBurned,
            totalDistance: stored.distance,
            averagePower: stored.averagePower,
            averageHeartRate: stored.averageHeartRate,
            source: WorkoutSource(rawValue: stored.source) ?? .other
        )
    }
    
    private func convertToDailyNutrition(_ stored: StoredNutrition) -> DailyNutrition {
        DailyNutrition(
            date: stored.date,
            totalCalories: stored.calories,
            totalProtein: stored.protein,
            totalCarbs: stored.carbs,
            totalFat: stored.fat,
            totalFiber: nil,
            totalSugar: nil,
            totalWater: nil,
            breakfast: nil,
            lunch: nil,
            dinner: nil,
            snacks: nil
        )
    }
}
