//
//  NutritionView.swift
//  HealthAnalytics
//
//  Created by Craig Faist on 1/26/26.
//


import SwiftUI
import Charts

struct NutritionView: View {
    @StateObject private var viewModel = NutritionViewModel()
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                
                if viewModel.isLoading {
                    ProgressView("Loading nutrition data...")
                        .padding()
                } else if let error = viewModel.errorMessage {
                    ErrorView(message: error)
                } else if viewModel.nutritionData.isEmpty {
                    EmptyNutritionView()
                } else {
                    // Summary Card
                    NutritionSummaryCard(data: viewModel.nutritionData)
                    
                    // Macro Breakdown Chart
                    MacroChartCard(data: viewModel.nutritionData)
                    
                    // Daily List
                    DailyNutritionList(data: viewModel.nutritionData)
                }
                
                Spacer()
            }
            .padding()
        }
        .background(TabBackgroundColor.nutrition(for: colorScheme))
        .navigationTitle("Nutrition")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        await viewModel.loadNutrition()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(viewModel.isLoading)
            }
        }
        .task {
            await viewModel.loadNutrition()
        }
    }
}

struct NutritionSummaryCard: View {
    let data: [DailyNutrition]
    
    var avgCalories: Double {
        let complete = data.filter { $0.isComplete }
        guard !complete.isEmpty else { return 0 }
        return complete.map { $0.totalCalories }.reduce(0, +) / Double(complete.count)
    }
    
    var avgProtein: Double {
        let complete = data.filter { $0.isComplete }
        guard !complete.isEmpty else { return 0 }
        return complete.map { $0.totalProtein }.reduce(0, +) / Double(complete.count)
    }
    
    var avgCarbs: Double {
        let complete = data.filter { $0.isComplete }
        guard !complete.isEmpty else { return 0 }
        return complete.map { $0.totalCarbs }.reduce(0, +) / Double(complete.count)
    }
    
    var avgFat: Double {
        let complete = data.filter { $0.isComplete }
        guard !complete.isEmpty else { return 0 }
        return complete.map { $0.totalFat }.reduce(0, +) / Double(complete.count)
    }
    
    var completeDays: Int {
        data.filter { $0.isComplete }.count
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text("30-Day Average")
                    .font(.headline)
                
                Spacer()
                
                Text("\(completeDays)/\(data.count) days logged")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            // Macros Grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 15) {
                MacroBox(
                    label: "Calories",
                    value: "\(Int(avgCalories))",
                    unit: "kcal",
                    color: .blue
                )
                
                MacroBox(
                    label: "Protein",
                    value: "\(Int(avgProtein))",
                    unit: "g",
                    color: .red
                )
                
                MacroBox(
                    label: "Carbs",
                    value: "\(Int(avgCarbs))",
                    unit: "g",
                    color: .green
                )
                
                MacroBox(
                    label: "Fat",
                    value: "\(Int(avgFat))",
                    unit: "g",
                    color: .orange
                )
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct MacroBox: View {
    let label: String
    let value: String
    let unit: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(color)
                
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
}

struct MacroChartCard: View {
    let data: [DailyNutrition]
    
    var recentData: [DailyNutrition] {
        Array(data.suffix(14)) // Last 2 weeks
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Macro Trends (14 Days)")
                .font(.headline)
            
            Chart {
                ForEach(recentData) { day in
                    // Protein line
                    LineMark(
                        x: .value("Date", day.date),
                        y: .value("Grams", day.totalProtein),
                        series: .value("Macro", "Protein")
                    )
                    .foregroundStyle(.red)
                    .symbol(.circle)
                    
                    // Carbs line
                    LineMark(
                        x: .value("Date", day.date),
                        y: .value("Grams", day.totalCarbs),
                        series: .value("Macro", "Carbs")
                    )
                    .foregroundStyle(.green)
                    .symbol(.square)
                    
                    // Fat line
                    LineMark(
                        x: .value("Date", day.date),
                        y: .value("Grams", day.totalFat),
                        series: .value("Macro", "Fat")
                    )
                    .foregroundStyle(.orange)
                    .symbol(.triangle)
                }
            }
            .frame(height: 200)
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            
            // Legend
            HStack(spacing: 20) {
                LegendItem(color: .red, label: "Protein")
                LegendItem(color: .green, label: "Carbs")
                LegendItem(color: .orange, label: "Fat")
            }
            .font(.caption)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct LegendItem: View {
    let color: Color
    let label: String
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
        }
    }
}

struct DailyNutritionList: View {
    let data: [DailyNutrition]
    
    var recentData: [DailyNutrition] {
        Array(data.suffix(7).reversed()) // Last 7 days, most recent first
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Days")
                .font(.headline)
            
            ForEach(recentData) { day in
                DailyNutritionRow(nutrition: day)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct DailyNutritionRow: View {
    let nutrition: DailyNutrition
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(nutrition.date, style: .date)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
                
                if !nutrition.isComplete {
                    Text("Incomplete")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.2))
                        .cornerRadius(4)
                }
            }
            
            HStack(spacing: 12) {
                MacroLabel(value: Int(nutrition.totalCalories), unit: "cal", color: .blue)
                MacroLabel(value: Int(nutrition.totalProtein), unit: "g P", color: .red)
                MacroLabel(value: Int(nutrition.totalCarbs), unit: "g C", color: .green)
                MacroLabel(value: Int(nutrition.totalFat), unit: "g F", color: .orange)
            }
            .font(.caption)
            
            Text(nutrition.formattedMacros)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(8)
    }
}

struct MacroLabel: View {
    let value: Int
    let unit: String
    let color: Color
    
    var body: some View {
        Text("\(value) \(unit)")
            .foregroundStyle(color)
    }
}

struct EmptyNutritionView: View {
    var body: some View {
        VStack(spacing: 15) {
            Image(systemName: "fork.knife")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            
            Text("No Nutrition Data")
                .font(.title3)
                .fontWeight(.semibold)
            
            Text("Make sure you're logging meals in MyFitnessPal or LoseIt and syncing to Apple Health.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
    }
}

#Preview {
    NavigationStack {
        NutritionView()
    }
}
