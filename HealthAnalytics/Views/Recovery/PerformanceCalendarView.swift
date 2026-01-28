import SwiftUI

struct PerformanceCalendarView: View {
    @StateObject private var viewModel = RecoveryViewModel()
    @State private var selectedDate: Date?
    @State private var showingDetail = false
    @State private var selectedMonth = Date()
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Month Selector
                MonthSelector(selectedMonth: $selectedMonth)
                
                // Calendar Heatmap
                CalendarHeatmap(
                    data: viewModel.recoveryData,
                    selectedMonth: selectedMonth,
                    selectedDate: $selectedDate
                )
                .onTapGesture {
                    // Handle tap
                }
                
                // Legend
                HeatmapLegend()
                
                // Selected day detail card
                if let date = selectedDate,
                   let dayData = viewModel.recoveryData.first(where: {
                       Calendar.current.isDate($0.date, inSameDayAs: date)
                   }) {
                    DayDetailCard(data: dayData)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Performance Calendar")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showingDetail) {
            if let date = selectedDate,
               let dayData = viewModel.recoveryData.first(where: {
                   Calendar.current.isDate($0.date, inSameDayAs: date)
               }) {
                DayDetailSheet(data: dayData)
            }
        }
        .task {
            // Load data for 90 days to show calendar
            viewModel.selectedPeriod = .quarter
            await viewModel.loadRecoveryData()
        }
    }
}

// MARK: - Month Selector

struct MonthSelector: View {
    @Binding var selectedMonth: Date
    
    var body: some View {
        HStack {
            Button {
                selectedMonth = Calendar.current.date(byAdding: .month, value: -1, to: selectedMonth) ?? selectedMonth
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3)
                    .foregroundStyle(.blue)
            }
            
            Spacer()
            
            Text(selectedMonth, format: .dateTime.month(.wide).year())
                .font(.title3)
                .fontWeight(.bold)
            
            Spacer()
            
            Button {
                selectedMonth = Calendar.current.date(byAdding: .month, value: 1, to: selectedMonth) ?? selectedMonth
            } label: {
                Image(systemName: "chevron.right")
                    .font(.title3)
                    .foregroundStyle(.blue)
            }
            .disabled(Calendar.current.isDate(selectedMonth, equalTo: Date(), toGranularity: .month))
        }
        .padding(.horizontal)
    }
}

// MARK: - Calendar Heatmap

struct CalendarHeatmap: View {
    let data: [DailyRecoveryData]
    let selectedMonth: Date
    @Binding var selectedDate: Date?
    
    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 7)
    
    var daysInMonth: [Date] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: selectedMonth),
              let monthFirstWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start) else {
            return []
        }
        
        var days: [Date] = []
        var date = monthFirstWeek.start
        
        while date < monthInterval.end {
            days.append(date)
            date = calendar.date(byAdding: .day, value: 1, to: date) ?? date
        }
        
        // Pad to full weeks
        while days.count % 7 != 0 {
            if let nextDay = calendar.date(byAdding: .day, value: 1, to: days.last!) {
                days.append(nextDay)
            }
        }
        
        return days
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // Weekday headers
            HStack(spacing: 8) {
                ForEach(calendar.shortWeekdaySymbols, id: \.self) { day in
                    Text(day)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            
            // Calendar grid
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(daysInMonth, id: \.self) { date in
                    DayCell(
                        date: date,
                        data: data.first { calendar.isDate($0.date, inSameDayAs: date) },
                        isSelected: selectedDate != nil && calendar.isDate(date, inSameDayAs: selectedDate!),
                        isInCurrentMonth: calendar.isDate(date, equalTo: selectedMonth, toGranularity: .month)
                    )
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedDate = date
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.05), radius: 15, y: 8)
        )
    }
}

struct DayCell: View {
    let date: Date
    let data: DailyRecoveryData?
    let isSelected: Bool
    let isInCurrentMonth: Bool
    
    var body: some View {
        VStack(spacing: 4) {
            Text(date, format: .dateTime.day())
                .font(.caption)
                .fontWeight(isSelected ? .bold : .regular)
            
            Circle()
                .fill(colorForScore(data?.readinessScore))
                .frame(width: 6, height: 6)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.blue.opacity(0.1) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isSelected ? Color.blue : Color.clear, lineWidth: 2)
        )
        .opacity(isInCurrentMonth ? 1.0 : 0.3)
    }
    
    private func colorForScore(_ score: Double?) -> Color {
        guard let score = score else { return .gray.opacity(0.2) }
        
        if score >= 85 {
            return .green
        } else if score >= 70 {
            return .blue
        } else if score >= 55 {
            return .orange
        } else {
            return .red
        }
    }
}

// MARK: - Heatmap Legend

struct HeatmapLegend: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Performance Level")
                .font(.subheadline)
                .fontWeight(.semibold)
            
            HStack(spacing: 16) {
                LegendItem(color: .green, label: "Excellent (85+)")
                LegendItem(color: .blue, label: "Good (70-84)")
                LegendItem(color: .orange, label: "Moderate (55-69)")
                LegendItem(color: .red, label: "Poor (<55)")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.05), radius: 10, y: 5)
        )
    }
}

struct LegendItem: View {
    let color: Color
    let label: String
    
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 12, height: 12)
            
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Day Detail Card

struct DayDetailCard: View {
    let data: DailyRecoveryData
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Date header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(data.date, format: .dateTime.month().day())
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text(data.date, format: .dateTime.weekday(.wide))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                if let score = data.readinessScore {
                    VStack(spacing: 4) {
                        Text("\(Int(score))")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(colorForScore(score))
                        
                        Text("Score")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Divider()
            
            // Metrics grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                if let hrv = data.hrv {
                    MetricRow(icon: "waveform.path.ecg", label: "HRV", value: "\(Int(hrv)) ms", color: .green)
                }
                
                if let rhr = data.restingHR {
                    MetricRow(icon: "heart.fill", label: "RHR", value: "\(Int(rhr)) bpm", color: .red)
                }
                
                if let sleep = data.sleepHours {
                    MetricRow(icon: "bed.double.fill", label: "Sleep", value: String(format: "%.1f hrs", sleep), color: .purple)
                }
                
                if let load = data.trainingLoad {
                    MetricRow(icon: "figure.run", label: "Load", value: String(format: "%.2f", load), color: .orange)
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.05), radius: 15, y: 8)
        )
    }
    
    private func colorForScore(_ score: Double) -> Color {
        if score >= 85 {
            return .green
        } else if score >= 70 {
            return .blue
        } else if score >= 55 {
            return .orange
        } else {
            return .red
        }
    }
}

struct MetricRow: View {
    let icon: String
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 28)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Text(value)
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Day Detail Sheet (Full Screen)

struct DayDetailSheet: View {
    let data: DailyRecoveryData
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Large readiness circle
                    if let score = data.readinessScore, let level = data.readinessLevel {
                        VStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .stroke(Color.gray.opacity(0.2), lineWidth: 15)
                                    .frame(width: 150, height: 150)
                                
                                Circle()
                                    .trim(from: 0, to: score / 100)
                                    .stroke(colorForScore(score).gradient, style: StrokeStyle(lineWidth: 15, lineCap: .round))
                                    .frame(width: 150, height: 150)
                                    .rotationEffect(.degrees(-90))
                                
                                VStack(spacing: 4) {
                                    Text("\(Int(score))")
                                        .font(.system(size: 48, weight: .bold, design: .rounded))
                                    
                                    Text(level.rawValue)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            
                            Text(level.description)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        .padding(.vertical)
                    }
                    
                    // All metrics
                    VStack(spacing: 16) {
                        if let hrv = data.hrv {
                            DetailMetricCard(icon: "waveform.path.ecg", title: "Heart Rate Variability", value: "\(Int(hrv))", unit: "ms", color: .green)
                        }
                        
                        if let rhr = data.restingHR {
                            DetailMetricCard(icon: "heart.fill", title: "Resting Heart Rate", value: "\(Int(rhr))", unit: "bpm", color: .red)
                        }
                        
                        if let sleep = data.sleepHours {
                            DetailMetricCard(icon: "bed.double.fill", title: "Sleep Duration", value: String(format: "%.1f", sleep), unit: "hours", color: .purple)
                        }
                        
                        if let load = data.trainingLoad {
                            DetailMetricCard(icon: "figure.run", title: "Training Load", value: String(format: "%.2f", load), unit: "ACR", color: .orange)
                        }
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(data.date, format: .dateTime.month().day().year())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func colorForScore(_ score: Double) -> Color {
        if score >= 85 { return .green }
        else if score >= 70 { return .blue }
        else if score >= 55 { return .orange }
        else { return .red }
    }
}

struct DetailMetricCard: View {
    let icon: String
    let title: String
    let value: String
    let unit: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.largeTitle)
                .foregroundStyle(color)
                .frame(width: 50)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    
                    Text(unit)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.05), radius: 10, y: 5)
        )
    }
}

#Preview {
    NavigationStack {
        PerformanceCalendarView()
    }
}
