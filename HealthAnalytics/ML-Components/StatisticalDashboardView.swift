//
//  StatisticalDashboardView.swift
//  HealthAnalytics
//
//  Overview of data quality and statistical confidence across all metrics
//

import SwiftUI
import SwiftData

struct StatisticalDashboardView: View {
    @Query private var workouts: [StoredWorkout]
    @Query private var healthMetrics: [StoredHealthMetric]
    @Query private var intentLabels: [StoredIntentLabel]
    @Query private var nutrition: [StoredNutrition]
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("Data Quality Dashboard")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("Statistical confidence in your insights")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                
                // Overall Quality Score
                OverallQualityCard(summary: dataQualitySummary)
                    .padding(.horizontal)
                
                // Individual Metrics
                VStack(spacing: 16) {
                    Text("Metric Breakdown")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                    
                    MetricQualityRow(
                        name: "Sleep Data",
                        icon: "bed.double.fill",
                        count: sleepCount,
                        validation: SampleSizeValidator.validate(
                            sampleSize: sleepCount,
                            analysisType: .correlation
                        ),
                        color: .purple
                    )
                    
                    MetricQualityRow(
                        name: "HRV Data",
                        icon: "waveform.path.ecg",
                        count: hrvCount,
                        validation: SampleSizeValidator.validate(
                            sampleSize: hrvCount,
                            analysisType: .correlation
                        ),
                        color: .green
                    )
                    
                    MetricQualityRow(
                        name: "Resting HR",
                        icon: "heart.fill",
                        count: rhrCount,
                        validation: SampleSizeValidator.validate(
                            sampleSize: rhrCount,
                            analysisType: .correlation
                        ),
                        color: .red
                    )
                    
                    MetricQualityRow(
                        name: "Workouts",
                        icon: "figure.run",
                        count: workouts.count,
                        validation: SampleSizeValidator.validate(
                            sampleSize: workouts.count,
                            analysisType: .mlTraining
                        ),
                        color: .blue
                    )
                    
                    MetricQualityRow(
                        name: "Intent Labels",
                        icon: "tag.fill",
                        count: intentLabels.count,
                        validation: SampleSizeValidator.validate(
                            sampleSize: intentLabels.count,
                            analysisType: .intentClassification
                        ),
                        color: .orange
                    )
                    
                    MetricQualityRow(
                        name: "Nutrition Data",
                        icon: "fork.knife",
                        count: nutrition.count,
                        validation: SampleSizeValidator.validate(
                            sampleSize: nutrition.count,
                            analysisType: .correlation
                        ),
                        color: .yellow
                    )
                }
                
                // Statistical Power Info
                StatisticalPowerCard(
                    workoutCount: workouts.count,
                    labelCount: intentLabels.count
                )
                .padding(.horizontal)
                
                // Recommendations
                if !recommendations.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Recommendations")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        ForEach(recommendations, id: \.self) { recommendation in
                            RecommendationRow(text: recommendation)
                        }
                    }
                }
            }
            .padding(.vertical)
        }
        .navigationTitle("Data Quality")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    // MARK: - Computed Properties
    
    private var sleepCount: Int {
        healthMetrics.filter { $0.type == "Sleep" }.count
    }
    
    private var hrvCount: Int {
        healthMetrics.filter { $0.type == "HRV" }.count
    }
    
    private var rhrCount: Int {
        healthMetrics.filter { $0.type == "RHR" }.count
    }
    
    private var dataQualitySummary: DataQualitySummary {
        let metrics = [sleepCount, hrvCount, rhrCount, workouts.count]
        let avgCount = Double(metrics.reduce(0, +)) / Double(metrics.count)
        
        let quality: DataQualitySummary.OverallQuality
        if avgCount >= 30 {
            quality = .excellent
        } else if avgCount >= 15 {
            quality = .good
        } else if avgCount >= 7 {
            quality = .fair
        } else {
            quality = .poor
        }
        
        return DataQualitySummary(
            quality: quality,
            averageDataPoints: Int(avgCount),
            metricsWithHighConfidence: metrics.filter { $0 >= 30 }.count
        )
    }
    
    private var recommendations: [String] {
        var recs: [String] = []
        
        if sleepCount < 30 {
            recs.append("Track \(30 - sleepCount) more nights of sleep for high confidence")
        }
        
        if hrvCount < 30 {
            recs.append("Track \(30 - hrvCount) more days of HRV for reliable patterns")
        }
        
        if intentLabels.count < 50 {
            recs.append("Label \(50 - intentLabels.count) more workouts for better intent classification")
        }
        
        if workouts.count < 100 {
            recs.append("Track \(100 - workouts.count) more workouts for robust ML predictions")
        }
        
        return recs
    }
    
    struct DataQualitySummary {
        let quality: OverallQuality
        let averageDataPoints: Int
        let metricsWithHighConfidence: Int
        
        enum OverallQuality {
            case excellent, good, fair, poor
            
            var color: Color {
                switch self {
                case .excellent: return .green
                case .good: return .blue
                case .fair: return .orange
                case .poor: return .red
                }
            }
            
            var emoji: String {
                switch self {
                case .excellent: return "✅"
                case .good: return "👍"
                case .fair: return "⚠️"
                case .poor: return "❌"
                }
            }
            
            var title: String {
                switch self {
                case .excellent: return "Excellent Data Quality"
                case .good: return "Good Data Quality"
                case .fair: return "Fair Data Quality"
                case .poor: return "Limited Data"
                }
            }
            
            var description: String {
                switch self {
                case .excellent: return "Your insights have high statistical confidence"
                case .good: return "Your insights are reliable with room to improve"
                case .fair: return "Your insights have moderate confidence"
                case .poor: return "More data needed for reliable insights"
                }
            }
        }
    }
}

// MARK: - Overall Quality Card

struct OverallQualityCard: View {
    let summary: StatisticalDashboardView.DataQualitySummary
    
    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                Text(summary.quality.emoji)
                    .font(.system(size: 48))
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.quality.title)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundStyle(summary.quality.color)
                    
                    Text(summary.quality.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Divider()
            
            HStack {
                VStack(alignment: .leading) {
                    Text("\(summary.averageDataPoints)")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Avg Data Points")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing) {
                    Text("\(summary.metricsWithHighConfidence)/6")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("High Confidence")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Metric Quality Row

struct MetricQualityRow: View {
    let name: String
    let icon: String
    let count: Int
    let validation: SampleSizeValidator.ValidationResult
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text("\(count) data points")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text(validation.confidence.emoji)
                    .font(.title3)
                
                Text(String(describing: validation.confidence))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal)
    }
}

// MARK: - Statistical Power Card

struct StatisticalPowerCard: View {
    let workoutCount: Int
    let labelCount: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Statistical Power", systemImage: "chart.line.uptrend.xyaxis")
                .font(.headline)
            
            Text("Probability of detecting real patterns")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Divider()
            
            // ACWR Analysis
            PowerRow(
                analysis: "ACWR Confidence",
                power: calculatePower(sampleSize: workoutCount, expectedEffect: 0.3),
                description: "Detecting 30% load changes"
            )
            
            // Intent Classification
            PowerRow(
                analysis: "Intent Classification",
                power: calculatePower(sampleSize: labelCount, expectedEffect: 0.5),
                description: "Distinguishing workout types"
            )
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private func calculatePower(sampleSize: Int, expectedEffect: Double) -> Double {
        SampleSizeValidator.calculatePower(
            sampleSize: sampleSize,
            expectedEffectSize: expectedEffect
        )
    }
}

struct PowerRow: View {
    let analysis: String
    let power: Double
    let description: String
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(analysis)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing) {
                Text("\(Int(power * 100))%")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(powerColor(power))
                
                Text(powerLabel(power))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    private func powerColor(_ power: Double) -> Color {
        if power >= 0.8 { return .green }
        if power >= 0.6 { return .orange }
        return .red
    }
    
    private func powerLabel(_ power: Double) -> String {
        if power >= 0.8 { return "Good" }
        if power >= 0.6 { return "Fair" }
        return "Low"
    }
}

// MARK: - Recommendation Row

struct RecommendationRow: View {
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "lightbulb.fill")
                .foregroundStyle(.yellow)
            
            Text(text)
                .font(.caption)
                .foregroundStyle(.primary)
            
            Spacer()
        }
        .padding()
        .background(.yellow.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal)
    }
}

#Preview {
    NavigationStack {
        StatisticalDashboardView()
            .modelContainer(for: [StoredWorkout.self, StoredHealthMetric.self, StoredIntentLabel.self, StoredNutrition.self])
    }
}
