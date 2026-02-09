//
//  ReadinessViewModel.swift (FIXED - Access Control)
//  HealthAnalytics
//
//  Properly integrates with SwiftData with correct access levels
//

import Foundation
import SwiftData
import Combine
import SwiftUI

@MainActor
class ReadinessViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var readinessScore: ReadinessAnalyzer.ReadinessScore?
    @Published var formIndicator: ReadinessAnalyzer.FormIndicator?
    @Published var performanceWindows: [PerformancePatternAnalyzer.PerformanceWindow] = []
    @Published var optimalTimings: [PerformancePatternAnalyzer.OptimalTiming] = []
    @Published var workoutSequences: [PerformancePatternAnalyzer.WorkoutSequence] = []
    @Published var dailyInstruction: DailyInstruction?
    @Published var mlPrediction: PerformancePredictor.Prediction?
    @Published var mlFeatureWeights: PerformancePredictor.FeatureWeights?
    @Published var mlError: String?
    
    // ✅ FIXED: Made internal so ReadinessView can check it
    var modelContainer: ModelContainer?
    
    private let readinessAnalyzer = ReadinessAnalyzer()
    private let patternAnalyzer = PerformancePatternAnalyzer()
    private var trainedModels: [PerformancePredictor.TrainedModel] = []
    
    struct DailyInstruction {
        let headline: String
        let subline: String
        let targetAction: String?
        let primaryInsight: String?
        let status: Status
        
        enum Status {
            case prime, ready, moderate, recovery, rest
            
            var color: Color {
                switch self {
                case .prime: return .purple
                case .ready: return .green
                case .moderate: return .blue
                case .recovery: return .orange
                case .rest: return .red
                }
            }
        }
    }
    
    func configure(container: ModelContainer) {
        self.modelContainer = container
    }
    
    func analyze() async {
        guard let container = modelContainer else {
            errorMessage = "SwiftData not configured"
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        do {
            let context = ModelContext(container)
            
            // Fetch all data from SwiftData
            let data = try await fetchAllData(context: context)
            
            print("📊 ReadinessViewModel: Fetched data")
            print("   Workouts: \(data.workouts.count)")
            print("   Sleep: \(data.sleep.count)")
            print("   RHR: \(data.rhr.count)")
            print("   HRV: \(data.hrv.count)")
            print("   Nutrition: \(data.nutrition.count)")
            
            // Check minimum requirements
            guard data.sleep.count >= 7,
                  (data.rhr.count >= 7 || data.hrv.count >= 7),
                  data.workouts.count >= 5 else {
                errorMessage = "Need more data for analysis"
                isLoading = false
                return
            }
            
            // 1. Run readiness analysis
            if let readiness = readinessAnalyzer.analyzeReadiness(
                restingHR: data.rhr,
                hrv: data.hrv,
                sleep: data.sleep,
                workouts: data.workouts,
                stravaActivities: [],
                nutrition: data.nutrition
            ) {
                self.readinessScore = readiness
                
                // Generate daily instruction
                self.dailyInstruction = generateDailyInstruction(from: readiness)
            }
            
            // 2. Discover performance patterns
            self.performanceWindows = patternAnalyzer.discoverPerformanceWindows(
                workouts: data.workouts,
                activities: [],
                sleep: data.sleep,
                nutrition: data.nutrition
            )
            
            self.optimalTimings = patternAnalyzer.discoverOptimalTiming(
                workouts: data.workouts,
                activities: []
            )
            
            self.workoutSequences = patternAnalyzer.discoverWorkoutSequences(
                workouts: data.workouts,
                activities: []
            )
            
            // 3. Train ML model and make prediction
            await trainAndPredict(data: data, context: context)
            
            isLoading = false
            
        } catch {
            errorMessage = "Analysis failed: \(error.localizedDescription)"
            isLoading = false
            print("❌ ReadinessViewModel error: \(error)")
        }
    }
    
    // MARK: - Data Fetching
    
    private struct AnalysisData {
        let workouts: [WorkoutData]
        let sleep: [HealthDataPoint]
        let rhr: [HealthDataPoint]
        let hrv: [HealthDataPoint]
        let nutrition: [DailyNutrition]
    }
    
    private func fetchAllData(context: ModelContext) async throws -> AnalysisData {
        // Fetch workouts
        let workoutDescriptor = FetchDescriptor<StoredWorkout>(
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        let storedWorkouts = try context.fetch(workoutDescriptor)
        let workouts = storedWorkouts.map { convertToWorkoutData($0) }
        
        // Fetch health metrics
        let sleepData = try fetchHealthMetrics(type: "Sleep", context: context)
        let rhrData = try fetchHealthMetrics(type: "RHR", context: context)
        let hrvData = try fetchHealthMetrics(type: "HRV", context: context)
        
        // Fetch nutrition
        let nutritionDescriptor = FetchDescriptor<StoredNutrition>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        let storedNutrition = try context.fetch(nutritionDescriptor)
        let nutrition = storedNutrition.map { convertToDailyNutrition($0) }
        
        return AnalysisData(
            workouts: workouts,
            sleep: sleepData,
            rhr: rhrData,
            hrv: hrvData,
            nutrition: nutrition
        )
    }
    
    private func fetchHealthMetrics(type: String, context: ModelContext) throws -> [HealthDataPoint] {
        // ✅ Map new names to possible old names for backward compatibility
        let possibleTypes: [String]
        switch type {
        case "Sleep":
            possibleTypes = ["Sleep", "sleep"]
        case "HRV":
            possibleTypes = ["HRV", "hrv"]
        case "RHR":
            possibleTypes = ["RHR", "restingHR"]
        default:
            possibleTypes = [type]
        }
        
        // Fetch metrics matching any of the possible type names
        var allMetrics: [StoredHealthMetric] = []
        for possibleType in possibleTypes {
            let descriptor = FetchDescriptor<StoredHealthMetric>(
                predicate: #Predicate { $0.type == possibleType },
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
            
            if let stored = try? context.fetch(descriptor) {
                allMetrics.append(contentsOf: stored)
            }
        }
        
        // Remove duplicates by date (in case both old and new exist)
        var seen = Set<Date>()
        let uniqueMetrics = allMetrics.filter { metric in
            let dayStart = Calendar.current.startOfDay(for: metric.date)
            if seen.contains(dayStart) {
                return false
            }
            seen.insert(dayStart)
            return true
        }
        
        return uniqueMetrics.map { HealthDataPoint(date: $0.date, value: $0.value) }
    }
    
    // MARK: - ML Training & Prediction
    
    private func trainAndPredict(data: AnalysisData, context: ModelContext) async {
        do {
            // Create a readiness service for ACWR calculation
            let readinessService = PredictiveReadinessService()
            
            print("🤖 Training ML models...")
            
            // Train the models
            trainedModels = try await PerformancePredictor.train(
                sleepData: data.sleep,
                hrvData: data.hrv,
                restingHRData: data.rhr,
                healthKitWorkouts: data.workouts,
                stravaActivities: [],
                nutritionData: data.nutrition,
                readinessService: readinessService
            )
            
            print("✅ Trained \(trainedModels.count) ML models")
            
            // Make a prediction for tomorrow
            if let runModel = trainedModels.first(where: { $0.activityType == "Run" }) {
                mlFeatureWeights = runModel.featureWeights
                
                // Get most recent values for prediction
                let latestSleep = data.sleep.first?.value ?? 7.5
                let latestHRV = data.hrv.first?.value ?? 50
                let latestRHR = data.rhr.first?.value ?? 60
                
                // Calculate ACWR from readiness service
                let assessment = readinessService.calculateReadiness(
                    stravaActivities: [],
                    healthKitWorkouts: data.workouts
                )
                
                // Get recent carbs average
                let recentCarbs = data.nutrition.prefix(7).map(\.totalCarbs).reduce(0, +) / Double(min(7, data.nutrition.count))
                
                mlPrediction = try PerformancePredictor.predict(
                    models: trainedModels,
                    activityType: "Run",
                    sleepHours: latestSleep,
                    hrvMs: latestHRV,
                    restingHR: latestRHR,
                    acwr: assessment.acwr,
                    carbs: recentCarbs
                )
                
                print("✅ ML Prediction: \(mlPrediction?.predictedPerformance ?? 0) \(mlPrediction?.unit ?? "")")
            }
            
            mlError = nil
            
        } catch {
            mlError = error.localizedDescription
            print("❌ ML Training failed: \(error)")
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
    
    // MARK: - Daily Instruction Generator
    
    private func generateDailyInstruction(from readiness: ReadinessAnalyzer.ReadinessScore) -> DailyInstruction {
        let score = readiness.score
        
        if score >= 80 && readiness.trend == .peaking {
            return DailyInstruction(
                headline: "🚀 Peak Performance Window",
                subline: "Your body is primed for a breakthrough session",
                targetAction: "Go after that PR or race hard",
                primaryInsight: "Recovery markers are optimal",
                status: .prime
            )
        } else if score >= 75 {
            return DailyInstruction(
                headline: "💪 Ready for Quality Work",
                subline: "Great day for intervals or tempo",
                targetAction: "High-intensity or long endurance session",
                primaryInsight: "Strong recovery response",
                status: .ready
            )
        } else if score >= 55 {
            return DailyInstruction(
                headline: "🔄 Moderate Training Day",
                subline: "Stick to moderate efforts",
                targetAction: "Zone 2 aerobic or easy strength",
                primaryInsight: "Body is still adapting",
                status: .moderate
            )
        } else if score >= 40 {
            return DailyInstruction(
                headline: "😴 Active Recovery Focus",
                subline: "Your body needs lighter work",
                targetAction: "Easy aerobic only, or rest",
                primaryInsight: "Recovery not keeping pace",
                status: .recovery
            )
        } else {
            return DailyInstruction(
                headline: "🛑 Rest Day Recommended",
                subline: "Complete rest or very light activity",
                targetAction: "Full rest day",
                primaryInsight: "High fatigue, poor recovery",
                status: .rest
            )
        }
    }
}
