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

    private let nutritionAccent = Color.teal

    var body: some View {
        ZStack {
            TabBackgroundColor.nutrition(for: colorScheme)
                 .ignoresSafeArea()

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
                        // SUMMARY
                         NutritionSummaryCard(data: viewModel.nutritionData)
                            .cardStyle(for: .nutrition)

                         // CHART
                         MacroChartCard(data: viewModel.nutritionData)
                            .cardStyle(for: .nutrition)

                         // LIST
                         DailyNutritionList(data: viewModel.nutritionData)
                            .cardStyle(for: .nutrition)
                    }
                    
                    Spacer()
                }
                .padding()
            }
            // Ensures the scroll view doesn't bring its own background "box"
            .scrollContentBackground(.hidden)
        }
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

// MARK: - Original Components (Preserved with Modern Styling)

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
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 15) {
                MacroBox(label: "Calories", value: "\(Int(avgCalories))", unit: "kcal", color: .blue)
                MacroBox(label: "Protein", value: "\(Int(avgProtein))", unit: "g", color: .red)
                MacroBox(label: "Carbs", value: "\(Int(avgCarbs))", unit: "g", color: .green)
                MacroBox(label: "Fat", value: "\(Int(avgFat))", unit: "g", color: .orange)
            }
        }
        .padding(20)
    }
}

struct MacroBox: View {
    let label: String
    let value: String
    let unit: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.title3.bold())
                    .foregroundStyle(color)

                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(color.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(color.opacity(0.25), lineWidth: 1)
        )
    }
}

struct MacroChartCard: View {
    let data: [DailyNutrition]
    
    var recentData: [DailyNutrition] {
        Array(data.suffix(14))
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Macro Trends (14 Days)")
                .font(.headline)

            Chart {
                ForEach(recentData) { day in
                    LineMark(x: .value("Date", day.date), y: .value("Grams", day.totalProtein), series: .value("Macro", "Protein")).foregroundStyle(.red).symbol(.circle)
                    LineMark(x: .value("Date", day.date), y: .value("Grams", day.totalCarbs), series: .value("Macro", "Carbs")).foregroundStyle(.green).symbol(.square)
                    LineMark(x: .value("Date", day.date), y: .value("Grams", day.totalFat), series: .value("Macro", "Fat")).foregroundStyle(.orange).symbol(.triangle)
                }
            }
            .frame(height: 200)
            .chartYAxis { AxisMarks(position: .leading) }
            
            HStack(spacing: 20) {
                LegendItem(color: .red, label: "Protein")
                LegendItem(color: .green, label: "Carbs")
                LegendItem(color: .orange, label: "Fat")
            }
            .font(.caption)
        }
        .padding(20)
    }
}

struct LegendItem: View {
    let color: Color
    let label: String
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
        }
    }
}

struct DailyNutritionList: View {
    let data: [DailyNutrition]
    
    var recentData: [DailyNutrition] {
        Array(data.suffix(7).reversed())
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Days")
                .font(.headline)
            
            ForEach(recentData) { day in
                DailyNutritionRow(nutrition: day)
            }
        }
        .padding(20)
    }
}

struct DailyNutritionRow: View {
    let nutrition: DailyNutrition

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(nutrition.date, style: .date)
                    .font(.subheadline.weight(.semibold))

                Spacer()

                if !nutrition.isComplete {
                    Text("Incomplete")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.15))
                        .clipShape(Capsule())
                }
            }

            HStack(spacing: 14) {
                MacroLabel(value: Int(nutrition.totalCalories), unit: "cal", color: .blue)
                MacroLabel(value: Int(nutrition.totalProtein), unit: "g P", color: .red)
                MacroLabel(value: Int(nutrition.totalCarbs), unit: "g C", color: .green)
                MacroLabel(value: Int(nutrition.totalFat), unit: "g F", color: .orange)
            }
            .font(.caption.weight(.medium))

            Text(nutrition.formattedMacros)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(uiColor: .tertiarySystemBackground))
        )
    }
}

struct MacroLabel: View {
    let value: Int
    let unit: String
    let color: Color
    var body: some View {
        Text("\(value) \(unit)").foregroundStyle(color)
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

struct NutritionCardStyle: ViewModifier {
    let tint: Color

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                tint.opacity(0.95),
                                tint.opacity(0.80)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(.white.opacity(0.08))
                    )
                    .shadow(color: .black.opacity(0.45), radius: 16, y: 6)
            }
    }
}

/*extension View {
    func nutritionCard(tint: Color) -> some View {
        modifier(NutritionCardStyle(tint: tint))
    }
}*/

