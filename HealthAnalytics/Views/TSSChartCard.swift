//
//  TSSChartCard.swift
//  HealthAnalytics
//
//  TSS (Training Stress Score) chart similar to TrainingPeaks
//

import SwiftUI
import Charts

struct TSSChartCard: View {
    let dailyTSS: [DailyTSSData]
    let period: TimePeriod
    
    @State private var selectedDate: Date?
    
    private var selectedWeek: WeeklyTSSData? {
        guard let date = selectedDate else { return nil }
        return weeklyData.first { Calendar.current.isDate($0.weekStart, equalTo: date, toGranularity: .weekOfYear) }
    }
    
    // X-axis stride for weeks based on period
    private var weeksStride: Int {
        switch period {
        case .week: return 1
        case .month: return 1
        case .quarter: return 2
        case .sixMonths: return 4
        case .year: return 8
        case .all: return 12
        }
    }
    
    // Group daily data into weekly totals
    private var weeklyData: [WeeklyTSSData] {
        let calendar = Calendar.current
        var weeklyDict: [Date: Double] = [:]
        var weeklyDayCounts: [Date: Int] = [:] // Track actual days with data
        
        for day in dailyTSS {
            // Get the start of the week for this date
            let weekStart = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: day.date)
            guard let weekDate = calendar.date(from: weekStart) else { continue }
            
            weeklyDict[weekDate, default: 0] += day.tss
            weeklyDayCounts[weekDate, default: 0] += 1
        }
        
        let sortedWeeks = weeklyDict.sorted { $0.key < $1.key }
        
        // Calculate 6-week rolling average for each week
        return sortedWeeks.enumerated().map { (index, entry) in
            let (weekDate, weeklyTSS) = entry
            
            // Get previous 5 weeks for 6-week average
            let startIndex = max(0, index - 5)
            let endIndex = index
            let recentWeeks = sortedWeeks[startIndex...endIndex]
            let sixWeekAvg = recentWeeks.map { $0.value }.reduce(0, +) / Double(recentWeeks.count)
            
            let daysInWeek = weeklyDayCounts[weekDate] ?? 7
            
            return WeeklyTSSData(
                weekStart: weekDate,
                weeklyTSS: weeklyTSS,
                sixWeekAvg: sixWeekAvg,
                daysInWeek: daysInWeek
            )
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Text("TRAINING STRESS")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if let latest = weeklyData.last {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Current Week")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text("\(Int(latest.weeklyTSS / Double(latest.daysInWeek))) TSS/day")
                            .font(.callout)
                            .fontWeight(.semibold)
                    }
                }
            }
            
            // Scrub Info Display
            if let selected = selectedWeek {
                VStack(spacing: 4) {
                    Text("Week of \(formatWeekOf(selected.weekStart))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("TSS")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text("\(Int(selected.weeklyTSS))")
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(.green)
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("6-Wk Avg")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text("\(Int(selected.sixWeekAvg))")
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(.orange)
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("6-Wk Daily Avg")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text("\(Int(selected.sixWeekAvg / 7))")
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            
            // Chart
            if !weeklyData.isEmpty {
                Chart {
                    // Weekly TSS bars (green for workouts)
                    ForEach(weeklyData) { data in
                        BarMark(
                            x: .value("Week", data.weekStart, unit: .weekOfYear),
                            y: .value("TSS", data.weeklyTSS)
                        )
                        .foregroundStyle(data.weeklyTSS > 0 ? Color.green : Color.clear)
                        .opacity(0.8)
                    }
                    
                    // 6-week rolling average TSS line
                    ForEach(weeklyData) { data in
                        LineMark(
                            x: .value("Week", data.weekStart, unit: .weekOfYear),
                            y: .value("6-Week Avg", data.sixWeekAvg)
                        )
                        .foregroundStyle(Color.orange)
                        .lineStyle(StrokeStyle(lineWidth: 3))
                        .interpolationMethod(.catmullRom)
                    }
                    
                    // Selection rule mark
                    if let date = selectedDate {
                        RuleMark(x: .value("Week", date, unit: .weekOfYear))
                            .foregroundStyle(.gray.opacity(0.3))
                            .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 5]))
                    }
                }
                .chartXSelection(value: $selectedDate)
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                        AxisValueLabel()
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .weekOfYear, count: weeksStride)) { value in
                        if let date = value.as(Date.self) {
                            AxisValueLabel {
                                Text(formatWeekLabel(date))
                                    .font(.caption2)
                            }
                        }
                        AxisGridLine()
                    }
                }
                .frame(height: 180)
                
                // Date range
                if let first = weeklyData.first, let last = weeklyData.last {
                    Text("\(formatFullDate(first.weekStart)) - \(formatFullDate(last.weekStart))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // Legend
                HStack(spacing: 20) {
                    HStack(spacing: 4) {
                        Rectangle()
                            .fill(Color.green)
                            .frame(width: 12, height: 12)
                        Text("Weekly TSS")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack(spacing: 4) {
                        Rectangle()
                            .fill(Color.orange)
                            .frame(width: 20, height: 3)
                        Text("6-Week Avg")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.top, 8)
                
            } else {
                Text("No training data available")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 40)
            }
        }
        .padding()
    }
    
    private func formatWeekLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        switch period {
        case .week, .month:
            formatter.dateFormat = "MMM d"
        case .quarter, .sixMonths:
            formatter.dateFormat = "MMM d"
        case .year, .all:
            formatter.dateFormat = "MMM"
        }
        return formatter.string(from: date)
    }
    
    private func formatFullDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
    
    private func formatWeekOf(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }
}

struct DailyTSSData: Identifiable {
    let id = UUID()
    let date: Date
    let tss: Double
    let ctl: Double  // Chronic Training Load (42-day exponential average)
    let atl: Double  // Acute Training Load (7-day exponential average)
}

struct WeeklyTSSData: Identifiable {
    let id = UUID()
    let weekStart: Date
    let weeklyTSS: Double
    let sixWeekAvg: Double
    let daysInWeek: Int
}

#Preview {
    let calendar = Calendar.current
    let today = Date()
    let sampleData = (0..<90).compactMap { dayOffset -> DailyTSSData? in
        guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: today) else {
            return nil
        }
        // Simulate varying TSS with some rest days
        let tss = dayOffset % 7 == 0 ? 0 : Double.random(in: 30...120)
        let ctl = 50 + Double(dayOffset) * 0.3 // Gradually increasing fitness
        let atl = tss > 0 ? 60 + Double.random(in: -10...10) : 40
        return DailyTSSData(date: date, tss: tss, ctl: ctl, atl: atl)
    }.reversed() as [DailyTSSData]
    
    TSSChartCard(dailyTSS: sampleData, period: .quarter)
        .cardStyle(for: .workouts)
        .padding()
}
