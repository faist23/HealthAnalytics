//
//  NutritionView.swift
//  HealthAnalytics
//
//  Created for HealthAnalytics
//

import SwiftUI
import Charts

struct NutritionView: View {
    @StateObject private var viewModel = NutritionViewModel()
    
    var body: some View {
        NavigationStack {
            ZStack {
                ScrollView {
                    VStack(spacing: 20) {
                        
                        // MARK: - Time Range Picker
                        Picker("Time Range", selection: $viewModel.selectedTimeRange) {
                            ForEach(NutritionViewModel.TimeRange.allCases, id: \.self) { range in
                                Text(range.rawValue).tag(range)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)
                        .onChange(of: viewModel.selectedTimeRange) { _, newRange in
                            Task {
                                await viewModel.loadNutritionData()
                            }
                        }
                        
                        if viewModel.dailyNutrition.isEmpty && !viewModel.isLoading {
                        NutritionEmptyState()
                            .padding(.top, 40)
                    } else {
                        // MARK: - Summary Cards
                        NutritionSummaryGrid(viewModel: viewModel)
                            .padding(.horizontal)
                        
                        // MARK: - Calories Chart
                        ChartSection(title: "Calorie Intake") {
                            Chart(viewModel.dailyNutrition) { day in
                                BarMark(
                                    x: .value("Date", day.date, unit: .day),
                                    y: .value("Calories", day.totalCalories)
                                )
                                .foregroundStyle(Color.statusMonitoring.gradient)
                            }
                        }
                        
                        // MARK: - Macros Chart
                        ChartSection(title: "Macro Breakdown") {
                            MacroBreakdownChart(nutritionData: viewModel.dailyNutrition)
                        }
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Nutrition")
                .background(Color(uiColor: .systemGroupedBackground))
                .task {
                    // Ensure data is loaded when view appears
                    await viewModel.loadNutritionData()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("DataWindowChanged"))) { _ in
                    // Force reload when data window changes
                    Task {
                        await viewModel.loadNutritionData()
                    }
                }
                
                // Loading overlay
                if viewModel.isLoading {
                    LoadingOverlay(message: "Loading nutrition data...")
                }
            }
        }
    }
}

// MARK: - Subviews

struct NutritionSummaryGrid: View {
    @ObservedObject var viewModel: NutritionViewModel
    
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: .spacingMd) {
            SummaryCard(
                title: "Avg Calories",
                value: String(format: "%.0f", viewModel.averageCalories),
                unit: "kcal",
                color: .orange
            )
            SummaryCard(
                title: "Avg Protein",
                value: String(format: "%.0f", viewModel.averageProtein),
                unit: "g",
                color: .blue
            )
            SummaryCard(
                title: "Avg Carbs",
                value: String(format: "%.0f", viewModel.averageCarbs),
                unit: "g",
                color: .green
            )
            SummaryCard(
                title: "Avg Fat",
                value: String(format: "%.0f", viewModel.averageFat),
                unit: "g",
                color: .purple
            )
        }
    }
}

struct SummaryCard: View {
    let title: String
    let value: String
    let unit: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: .spacingSm) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
            
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.title2.bold())
                    .foregroundStyle(color)
                Text(unit)
                    .font(.caption.bold())
                    .foregroundStyle(color.opacity(0.8))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct ChartSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: .spacingMd) {
            Text(title)
                .font(.headline)
                .padding(.horizontal)
            
            content()
                .frame(height: 250)
                .padding(.horizontal)
        }
        .padding(.vertical)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: .radiusMd))
        .padding(.horizontal)
    }
}

struct MacroBreakdownChart: View {
    let nutritionData: [DailyNutrition]
    @State private var selectedDate: Date?

    var body: some View {
        Chart {
            ForEach(nutritionData) { day in
                BarMark(
                    x: .value("Date", day.date, unit: .day),
                    y: .value("Protein", day.totalProtein * 4)
                )
                .foregroundStyle(by: .value("Macro", "Protein"))
                
                BarMark(
                    x: .value("Date", day.date, unit: .day),
                    y: .value("Carbs", day.totalCarbs * 4)
                )
                .foregroundStyle(by: .value("Macro", "Carbs"))
                
                BarMark(
                    x: .value("Date", day.date, unit: .day),
                    y: .value("Fat", day.totalFat * 9)
                )
                .foregroundStyle(by: .value("Macro", "Fat"))
            }

            if let selectedDate {
                RuleMark(
                    x: .value("Selected Date", selectedDate, unit: .day)
                )
                .foregroundStyle(Color.textTertiary.opacity(0.3))
                .offset(yStart: -10)
                .zIndex(-1)
                .annotation(
                    position: .top,
                    spacing: 0,
                    overflowResolution: .init(
                        x: .fit(to: .chart),
                        y: .disabled
                    )
                ) {
                    if let day = nutritionData.first(where: { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) }) {
                        let pCals = day.totalProtein * 4
                        let cCals = day.totalCarbs * 4
                        let fCals = day.totalFat * 9
                        let totalCals = pCals + cCals + fCals
                        
                        if totalCals > 0 {
                            let pPct = Int((pCals / totalCals) * 100)
                            let cPct = Int((cCals / totalCals) * 100)
                            let fPct = Int((fCals / totalCals) * 100)
                            
                            VStack(alignment: .leading, spacing: .spacingXs) {
                                Text(day.date.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption.bold())
                                HStack(spacing: .spacingSm) {
                                    Text("\(pPct)% P").foregroundStyle(Color.accent)
                                    Text("\(cPct)% C").foregroundStyle(Color.statusOptimal)
                                    Text("\(fPct)% F").foregroundStyle(Color.statusRest)
                                }
                                .font(.caption2.bold())
                            }
                            .padding(.spacingSm)
                            .background(Color(uiColor: .systemBackground))
                            .cornerRadius(.radiusSm)
                            .shadow(radius: 3)
                        }
                    }
                }
            }
        }
        .chartForegroundStyleScale([
            "Protein": .blue,
            "Carbs": .green,
            "Fat": .purple
        ])
        .chartXSelection(value: $selectedDate)
    }
}

// OLD STUFF, DON'T KNOW IF WE NEED IT
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
                    .foregroundStyle(Color.textSecondary)
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
                .foregroundStyle(Color.textSecondary)

            HStack(alignment: .firstTextBaseline, spacing: .spacingXs) {
                Text(value)
                    .font(.title3.bold())
                    .foregroundStyle(color)

                Text(unit)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
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
                    LineMark(x: .value("Date", day.date), y: .value("Grams", day.totalProtein), series: .value("Macro", "Protein")).foregroundStyle(Color.statusWarning).symbol(.circle)
                    LineMark(x: .value("Date", day.date), y: .value("Grams", day.totalCarbs), series: .value("Macro", "Carbs")).foregroundStyle(Color.statusOptimal).symbol(.square)
                    LineMark(x: .value("Date", day.date), y: .value("Grams", day.totalFat), series: .value("Macro", "Fat")).foregroundStyle(Color.statusMonitoring).symbol(.triangle)
                }
            }
            .frame(height: 200)
            .chartYAxis { AxisMarks(position: .leading) }
            
            HStack(spacing: 20) {
                LegendItem(color: .statusWarning, label: "Protein")
                LegendItem(color: .statusOptimal, label: "Carbs")
                LegendItem(color: .statusMonitoring, label: "Fat")
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
        HStack(spacing: .spacingXs) {
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
                        .foregroundStyle(Color.statusMonitoring)
                        .padding(.horizontal, .spacingSm)
                        .padding(.vertical, .spacingXs)
                        .background(Color.statusMonitoring.opacity(0.15))
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
                .foregroundStyle(Color.textSecondary)
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
                .foregroundStyle(Color.textSecondary)
            
            Text("No Nutrition Data")
                .font(.title3)
                .fontWeight(.semibold)
            
            Text("Make sure you're logging meals in MyFitnessPal or LoseIt and syncing to Apple Health.")
                .font(.body)
                .foregroundStyle(Color.textSecondary)
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

