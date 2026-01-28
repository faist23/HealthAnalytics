import SwiftUI
import Charts

struct TimelineView: View {
    @StateObject private var viewModel = TimelineViewModel()
    
    var body: some View {
        VStack(spacing: 0) {
            // Date range picker
            DateRangePicker(
                startDate: $viewModel.startDate,
                endDate: $viewModel.endDate,
                onApply: {
                    Task {
                        await viewModel.loadTimelineData()
                    }
                }
            )
            .padding()
            .background(Color(.systemBackground))
            
            ScrollView {
                VStack(spacing: 24) {
                    // Metric toggles
                    MetricToggles(selectedMetrics: $viewModel.selectedMetrics)
                    
                    // Main timeline chart
                    if !viewModel.timelineData.isEmpty {
                        TimelineChart(
                            data: viewModel.timelineData,
                            selectedMetrics: viewModel.selectedMetrics,
                            workouts: viewModel.workouts
                        )
                    }
                    
                    // Workout markers timeline
                    if !viewModel.workouts.isEmpty {
                        WorkoutTimeline(workouts: viewModel.workouts)
                    }
                    
                    // Stats summary
                    TimelineStats(
                        data: viewModel.timelineData,
                        selectedMetrics: viewModel.selectedMetrics
                    )
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
        }
        .navigationTitle("Timeline")
        .navigationBarTitleDisplayMode(.large)
        .task {
            await viewModel.loadTimelineData()
        }
        .overlay {
            if viewModel.isLoading {
                LoadingOverlay()
            }
        }
    }
}

// MARK: - Timeline ViewModel

@MainActor
class TimelineViewModel: ObservableObject {
    @Published var timelineData: [TimelineDataPoint] = []
    @Published var workouts: [WorkoutData] = []
    @Published var selectedMetrics: Set<TimelineMetric> = [.rhr, .hrv, .sleep]
    @Published var startDate = Calendar.current.date(byAdding: .month, value: -3, to: Date()) ?? Date()
    @Published var endDate = Date()
    @Published var isLoading = false
    
    private let healthKitManager = HealthKitManager.shared
    
    func loadTimelineData() async {
        isLoading = true
        
        do {
            // Fetch all metrics
            async let rhrData = healthKitManager.fetchRestingHeartRate(startDate: startDate, endDate: endDate)
            async let hrvData = healthKitManager.fetchHeartRateVariability(startDate: startDate, endDate: endDate)
            async let sleepData = healthKitManager.fetchSleepDuration(startDate: startDate, endDate: endDate)
            async let stepData = healthKitManager.fetchStepCount(startDate: startDate, endDate: endDate)
            async let workoutData = healthKitManager.fetchWorkouts(startDate: startDate, endDate: endDate)
            
            let rhr = try await rhrData
            let hrv = try await hrvData
            let sleep = try await sleepData
            let steps = try await stepData
            self.workouts = try await workoutData
            
            // Combine into timeline data points
            self.timelineData = combineMetrics(rhr: rhr, hrv: hrv, sleep: sleep, steps: steps)
            
        } catch {
            print("Error loading timeline data: \(error)")
        }
        
        isLoading = false
    }
    
    private func combineMetrics(
        rhr: [HealthDataPoint],
        hrv: [HealthDataPoint],
        sleep: [HealthDataPoint],
        steps: [HealthDataPoint]
    ) -> [TimelineDataPoint] {
        var dataByDate: [Date: TimelineDataPoint] = [:]
        let calendar = Calendar.current
        
        for point in rhr {
            let day = calendar.startOfDay(for: point.date)
            if dataByDate[day] == nil {
                dataByDate[day] = TimelineDataPoint(date: day)
            }
            dataByDate[day]?.restingHR = point.value
        }
        
        for point in hrv {
            let day = calendar.startOfDay(for: point.date)
            if dataByDate[day] == nil {
                dataByDate[day] = TimelineDataPoint(date: day)
            }
            dataByDate[day]?.hrv = point.value
        }
        
        for point in sleep {
            let day = calendar.startOfDay(for: point.date)
            if dataByDate[day] == nil {
                dataByDate[day] = TimelineDataPoint(date: day)
            }
            dataByDate[day]?.sleepHours = point.value
        }
        
        for point in steps {
            let day = calendar.startOfDay(for: point.date)
            if dataByDate[day] == nil {
                dataByDate[day] = TimelineDataPoint(date: day)
            }
            dataByDate[day]?.steps = point.value
        }
        
        return dataByDate.values.sorted { $0.date < $1.date }
    }
}

struct TimelineDataPoint: Identifiable {
    let id = UUID()
    var date: Date
    var restingHR: Double?
    var hrv: Double?
    var sleepHours: Double?
    var steps: Double?
    var weight: Double?
}

enum TimelineMetric: String, CaseIterable, Identifiable {
    case rhr = "RHR"
    case hrv = "HRV"
    case sleep = "Sleep"
    case steps = "Steps"
    case weight = "Weight"
    
    var id: String { rawValue }
    
    var color: Color {
        switch self {
        case .rhr: return .red
        case .hrv: return .green
        case .sleep: return .purple
        case .steps: return .orange
        case .weight: return .blue
        }
    }
    
    var icon: String {
        switch self {
        case .rhr: return "heart.fill"
        case .hrv: return "waveform.path.ecg"
        case .sleep: return "bed.double.fill"
        case .steps: return "figure.walk"
        case .weight: return "scalemass.fill"
        }
    }
    
    var unit: String {
        switch self {
        case .rhr: return "bpm"
        case .hrv: return "ms"
        case .sleep: return "hrs"
        case .steps: return "steps"
        case .weight: return "lbs"
        }
    }
}

// MARK: - Date Range Picker

struct DateRangePicker: View {
    @Binding var startDate: Date
    @Binding var endDate: Date
    let onApply: () -> Void
    
    @State private var showingCustomRange = false
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Date Range")
                    .font(.headline)
                
                Spacer()
                
                Button {
                    showingCustomRange.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Text(formattedRange)
                            .font(.subheadline)
                        Image(systemName: "calendar")
                            .font(.caption)
                    }
                    .foregroundStyle(.blue)
                }
            }
            
            if showingCustomRange {
                VStack(spacing: 12) {
                    DatePicker("Start", selection: $startDate, displayedComponents: .date)
                    DatePicker("End", selection: $endDate, displayedComponents: .date)
                    
                    Button("Apply") {
                        showingCustomRange = false
                        onApply()
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.systemGray6))
                )
            }
            
            // Quick range buttons
            if !showingCustomRange {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        QuickRangeButton(title: "7D") {
                            startDate = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
                            endDate = Date()
                            onApply()
                        }
                        
                        QuickRangeButton(title: "30D") {
                            startDate = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
                            endDate = Date()
                            onApply()
                        }
                        
                        QuickRangeButton(title: "90D") {
                            startDate = Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date()
                            endDate = Date()
                            onApply()
                        }
                        
                        QuickRangeButton(title: "6M") {
                            startDate = Calendar.current.date(byAdding: .month, value: -6, to: Date()) ?? Date()
                            endDate = Date()
                            onApply()
                        }
                        
                        QuickRangeButton(title: "1Y") {
                            startDate = Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date()
                            endDate = Date()
                            onApply()
                        }
                    }
                }
            }
        }
    }
    
    private var formattedRange: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return "\(formatter.string(from: startDate)) - \(formatter.string(from: endDate))"
    }
}

struct QuickRangeButton: View {
    let title: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(Color(.systemGray6))
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Metric Toggles

struct MetricToggles: View {
    @Binding var selectedMetrics: Set<TimelineMetric>
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Metrics")
                .font(.headline)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(TimelineMetric.allCases) { metric in
                        TimelineMetricToggle(
                            metric: metric,
                            isSelected: selectedMetrics.contains(metric)
                        ) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                if selectedMetrics.contains(metric) {
                                    selectedMetrics.remove(metric)
                                } else {
                                    selectedMetrics.insert(metric)
                                }
                            }
                        }
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
}

struct TimelineMetricToggle: View {
    let metric: TimelineMetric
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: metric.icon)
                    .font(.title3)
                    .foregroundStyle(isSelected ? metric.color : .secondary)
                
                Text(metric.rawValue)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(isSelected ? metric.color : .secondary)
            }
            .frame(width: 70, height: 70)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? metric.color.opacity(0.15) : Color(.systemGray6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(metric.color.opacity(isSelected ? 0.5 : 0), lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Timeline Chart

struct TimelineChart: View {
    let data: [TimelineDataPoint]
    let selectedMetrics: Set<TimelineMetric>
    let workouts: [WorkoutData]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Metrics Over Time")
                .font(.headline)
            
            Chart {
                ForEach(data) { point in
                    // RHR
                    if selectedMetrics.contains(.rhr), let rhr = point.restingHR {
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("RHR", normalizeRHR(rhr)),
                            series: .value("Metric", "RHR")
                        )
                        .foregroundStyle(TimelineMetric.rhr.color.gradient)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    }
                    
                    // HRV
                    if selectedMetrics.contains(.hrv), let hrv = point.hrv {
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("HRV", normalizeHRV(hrv)),
                            series: .value("Metric", "HRV")
                        )
                        .foregroundStyle(TimelineMetric.hrv.color.gradient)
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 5]))
                    }
                    
                    // Sleep
                    if selectedMetrics.contains(.sleep), let sleep = point.sleepHours {
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Sleep", normalizeSleep(sleep)),
                            series: .value("Metric", "Sleep")
                        )
                        .foregroundStyle(TimelineMetric.sleep.color.gradient)
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [2, 4]))
                    }
                    
                    // Steps
                    if selectedMetrics.contains(.steps), let steps = point.steps {
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Steps", normalizeSteps(steps)),
                            series: .value("Metric", "Steps")
                        )
                        .foregroundStyle(TimelineMetric.steps.color.gradient)
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [8, 2]))
                    }
                }
                
                // Workout markers
                ForEach(workouts) { workout in
                    PointMark(
                        x: .value("Date", Calendar.current.startOfDay(for: workout.startDate)),
                        y: .value("Value", 50)
                    )
                    .foregroundStyle(.orange)
                    .symbol(.circle)
                    .symbolSize(60)
                }
            }
            .frame(height: 300)
            .chartYScale(domain: 0...100)
            .chartYAxis {
                AxisMarks(position: .leading, values: [0, 50, 100])
            }
            .chartXAxis {
                AxisMarks { value in
                    if let date = value.as(Date.self) {
                        AxisValueLabel {
                            Text(date, format: .dateTime.month(.abbreviated).day())
                                .font(.caption2)
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
    
    private func normalizeRHR(_ rhr: Double) -> Double {
        // Normalize RHR: 40-80 bpm -> 0-100 (inverted)
        let normalized = (80 - rhr) / 40 * 100
        return min(max(normalized, 0), 100)
    }
    
    private func normalizeHRV(_ hrv: Double) -> Double {
        // Normalize HRV: 0-100 ms -> 0-100
        return min(max(hrv, 0), 100)
    }
    
    private func normalizeSleep(_ sleep: Double) -> Double {
        // Normalize Sleep: 0-10 hours -> 0-100
        return min(max((sleep / 10) * 100, 0), 100)
    }
    
    private func normalizeSteps(_ steps: Double) -> Double {
        // Normalize Steps: 0-20000 -> 0-100
        return min(max((steps / 20000) * 100, 0), 100)
    }
}

// MARK: - Workout Timeline

struct WorkoutTimeline: View {
    let workouts: [WorkoutData]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Workouts")
                .font(.headline)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(workouts) { workout in
                        WorkoutMarker(workout: workout)
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.05), radius: 10, y: 5)
        )
    }
}

struct WorkoutMarker: View {
    let workout: WorkoutData
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: workout.iconName)
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 50, height: 50)
                .background(
                    Circle()
                        .fill(.orange.gradient)
                )
            
            VStack(spacing: 2) {
                Text(workout.startDate, format: .dateTime.month().day())
                    .font(.caption2)
                    .fontWeight(.medium)
                
                Text(workout.formattedDuration)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Timeline Stats

struct TimelineStats: View {
    let data: [TimelineDataPoint]
    let selectedMetrics: Set<TimelineMetric>
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Period Summary")
                .font(.headline)
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                if selectedMetrics.contains(.rhr) {
                    StatCard(
                        icon: "heart.fill",
                        title: "Avg RHR",
                        value: "\(Int(avgRHR))",
                        unit: "bpm",
                        color: .red
                    )
                }
                
                if selectedMetrics.contains(.hrv) {
                    StatCard(
                        icon: "waveform.path.ecg",
                        title: "Avg HRV",
                        value: "\(Int(avgHRV))",
                        unit: "ms",
                        color: .green
                    )
                }
                
                if selectedMetrics.contains(.sleep) {
                    StatCard(
                        icon: "bed.double.fill",
                        title: "Avg Sleep",
                        value: String(format: "%.1f", avgSleep),
                        unit: "hrs",
                        color: .purple
                    )
                }
                
                if selectedMetrics.contains(.steps) {
                    StatCard(
                        icon: "figure.walk",
                        title: "Avg Steps",
                        value: "\(Int(avgSteps).formatted())",
                        unit: "",
                        color: .orange
                    )
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
    
    private var avgRHR: Double {
        let values = data.compactMap { $0.restingHR }
        return values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }
    
    private var avgHRV: Double {
        let values = data.compactMap { $0.hrv }
        return values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }
    
    private var avgSleep: Double {
        let values = data.compactMap { $0.sleepHours }
        return values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }
    
    private var avgSteps: Double {
        let values = data.compactMap { $0.steps }
        return values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }
}

struct StatCard: View {
    let icon: String
    let title: String
    let value: String
    let unit: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.title3)
                    .fontWeight(.bold)
                
                if !unit.isEmpty {
                    Text(unit)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(color.opacity(0.1))
        )
    }
}

#Preview {
    NavigationStack {
        TimelineView()
    }
}
