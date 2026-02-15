//
//  TrainingZoneCard.swift
//  HealthAnalytics
//
//  Comprehensive training zone analysis visualization
//

import SwiftUI
import Charts

// MARK: - Main Training Zone Card

struct TrainingZoneCard: View {
    let analysis: TrainingZoneAnalyzer.ZoneAnalysis
    @State private var showInfo = false
    @State private var selectedSection: Section = .zones
    
    enum Section: String, CaseIterable {
        case zones = "Zones"
        case polarized = "Balance"
        case efficiency = "Efficiency"
        
        var icon: String {
            switch self {
            case .zones: return "chart.bar.fill"
            case .polarized: return "chart.pie.fill"
            case .efficiency: return "arrow.up.right"
            }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                HStack(spacing: 4) {
                    Text("TRAINING ZONES")
                        .font(.headline)
                    
                    Button {
                        showInfo = true
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
                
                Spacer()
                
                Text(analysis.activityType)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
            }
            
            // Threshold Display
            if let threshold = analysis.functionalThreshold {
                thresholdDisplay(threshold: threshold)
            }
            
            // Section Picker
            Picker("View", selection: $selectedSection) {
                ForEach(Section.allCases, id: \.self) { section in
                    Label(section.rawValue, systemImage: section.icon)
                        .tag(section)
                }
            }
            .pickerStyle(.segmented)
            
            // Content based on selected section
            switch selectedSection {
            case .zones:
                zoneDistributionView
            case .polarized:
                polarizedBalanceView
            case .efficiency:
                efficiencyView
            }
            
            // Confidence indicator
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(confidenceColor)
                
                Text(analysis.confidence.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .sheet(isPresented: $showInfo) {
            TrainingZoneInfoSheet()
        }
    }
    
    // MARK: - Threshold Display
    
    @ViewBuilder
    private func thresholdDisplay(threshold: Double) -> some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Functional Threshold")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    if let power = analysis.criticalPower {
                        Text("\(Int(threshold))")
                            .font(.title2)
                            .fontWeight(.bold)
                        Text("watts")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if let _ = analysis.criticalPace {
                        Text(formatPace(threshold))
                            .font(.title2)
                            .fontWeight(.bold)
                        Text("/km")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                // Detection method
                Text(analysis.thresholdMethod)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            
            Spacer()
            
            if let cp = analysis.criticalPower {
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Critical Power")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(Int(cp))")
                            .font(.title3)
                            .fontWeight(.semibold)
                        Text("w")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    // MARK: - Zone Distribution View
    
    private var zoneDistributionView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Time in Each Zone (Last 30 Days)")
                .font(.subheadline)
                .fontWeight(.semibold)
            
            // Bar chart of zones
            Chart(analysis.zones.filter { $0.timeInZone > 0 }) { zone in
                BarMark(
                    x: .value("Time", zone.timeInZone / 3600), // Convert to hours
                    y: .value("Zone", "Z\(zone.number)")
                )
                .foregroundStyle(by: .value("Zone", "Z\(zone.number)"))
                .annotation(position: .trailing) {
                    Text("\(Int(zone.percentOfTotal))%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .chartXAxisLabel("Hours")
            .chartLegend(.hidden)
            .frame(height: 200)
            
            // Zone legend with details
            ForEach(analysis.zones.prefix(5)) { zone in
                ZoneRow(zone: zone)
            }
        }
    }
    
    // MARK: - Training Balance View
    
    private var polarizedBalanceView: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Training model header
            HStack {
                Text(analysis.trainingBalance.model.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Text(analysis.confidence.description)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            // Model description
            Text(analysis.trainingBalance.model.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)
            
            // Visual representation of training distribution
            VStack(spacing: 12) {
                // Target vs Actual
                HStack(spacing: 16) {
                    BalanceColumn(
                        title: "Target",
                        easy: analysis.trainingBalance.targetEasy,
                        moderate: analysis.trainingBalance.targetModerate,
                        hard: analysis.trainingBalance.targetHard,
                        isTarget: true
                    )
                    
                    BalanceColumn(
                        title: "Actual",
                        easy: analysis.trainingBalance.easyPercentage,
                        moderate: analysis.trainingBalance.moderatePercentage,
                        hard: analysis.trainingBalance.hardPercentage,
                        isTarget: false
                    )
                }
                .frame(height: 150)
                
                // Status
                HStack(spacing: 8) {
                    Image(systemName: analysis.trainingBalance.matchesModel ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(analysis.trainingBalance.matchesModel ? .green : .orange)
                    
                    Text(analysis.trainingBalance.matchesModel ? "Matches \(analysis.trainingBalance.model.name)" : "Needs Adjustment")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                
                // Recommendation
                Text(analysis.trainingBalance.recommendation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }
    
    // MARK: - Efficiency View
    
    private var efficiencyView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Efficiency Factor Trend")
                .font(.subheadline)
                .fontWeight(.semibold)
            
            // Current EF
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Current EF")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Text(String(format: "%.2f", analysis.efficiencyTrend.current))
                        .font(.title)
                        .fontWeight(.bold)
                }
                
                Spacer()
                
                // Trend indicator
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: trendIcon(analysis.efficiencyTrend.trend))
                            .foregroundStyle(trendColor(analysis.efficiencyTrend.trend))
                        
                        Text("\(analysis.efficiencyTrend.thirtyDayChange > 0 ? "+" : "")\(String(format: "%.1f", analysis.efficiencyTrend.thirtyDayChange))%")
                            .fontWeight(.semibold)
                            .foregroundStyle(trendColor(analysis.efficiencyTrend.trend))
                    }
                    
                    Text("30-day change")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            // Interpretation
            Text(analysis.efficiencyTrend.interpretation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding()
                .background(trendColor(analysis.efficiencyTrend.trend).opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            
            // Decoupling events if any
            if !analysis.recentDecoupling.isEmpty {
                Divider()
                
                Text("Recent Decoupling Events")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                ForEach(analysis.recentDecoupling.prefix(3)) { event in
                    DecouplingRow(event: event)
                }
            }
        }
    }
    
    // MARK: - Helper Views
    
    private var confidenceColor: Color {
        switch analysis.confidence {
        case .high: return .green
        case .medium: return .blue
        case .low: return .orange
        case .building: return .gray
        }
    }
    
    private func trendIcon(_ trend: TrainingZoneAnalyzer.EfficiencyTrend.Trend) -> String {
        switch trend {
        case .improving: return "arrow.up.right.circle.fill"
        case .stable: return "arrow.right.circle.fill"
        case .declining: return "arrow.down.right.circle.fill"
        }
    }
    
    private func trendColor(_ trend: TrainingZoneAnalyzer.EfficiencyTrend.Trend) -> Color {
        switch trend {
        case .improving: return .green
        case .stable: return .blue
        case .declining: return .orange
        }
    }
    
    private func formatPace(_ secondsPerKm: Double) -> String {
        let minutes = Int(secondsPerKm)
        let seconds = Int((secondsPerKm - Double(minutes)) * 60)
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Supporting Views

struct ZoneRow: View {
    let zone: TrainingZoneAnalyzer.TrainingZone
    
    var body: some View {
        HStack(spacing: 12) {
            // Zone number
            Text("Z\(zone.number)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(zoneColor(zone.number))
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 2) {
                Text(zone.name)
                    .font(.caption)
                    .fontWeight(.semibold)
                
                Text(zone.description)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            if zone.timeInZone > 0 {
                Text(formatDuration(zone.timeInZone))
                    .font(.caption)
                    .fontWeight(.medium)
            }
        }
        .padding(.vertical, 4)
    }
    
    private func zoneColor(_ number: Int) -> Color {
        switch number {
        case 1: return .gray
        case 2: return .blue
        case 3: return .green
        case 4: return .yellow
        case 5: return .orange
        case 6: return .red
        case 7: return .purple
        default: return .gray
        }
    }
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

struct BalanceColumn: View {
    let title: String
    let easy: Double
    let moderate: Double
    let hard: Double
    let isTarget: Bool
    
    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    // Easy zone
                    Rectangle()
                        .fill(.green)
                        .frame(height: geometry.size.height * (easy / 100))
                    
                    // Moderate zone
                    if moderate > 0 {
                        Rectangle()
                            .fill(.yellow)
                            .frame(height: geometry.size.height * (moderate / 100))
                    }
                    
                    // Hard zone
                    Rectangle()
                        .fill(.red)
                        .frame(height: geometry.size.height * (hard / 100))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isTarget ? Color.secondary : Color.clear, lineWidth: 2)
                    .opacity(0.3)
            )
            
            // Percentages
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Circle().fill(.green).frame(width: 8, height: 8)
                    Text("\(Int(easy))% easy")
                        .font(.caption2)
                }
                if moderate > 0 {
                    HStack {
                        Circle().fill(.yellow).frame(width: 8, height: 8)
                        Text("\(Int(moderate))% mod")
                            .font(.caption2)
                    }
                }
                HStack {
                    Circle().fill(.red).frame(width: 8, height: 8)
                    Text("\(Int(hard))% hard")
                        .font(.caption2)
                }
            }
            .foregroundStyle(.secondary)
        }
    }
}

struct DecouplingRow: View {
    let event: TrainingZoneAnalyzer.DecouplingEvent
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(severityColor)
                .font(.caption)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(event.activityType)
                        .font(.caption)
                        .fontWeight(.semibold)
                    
                    Text("•")
                        .foregroundStyle(.secondary)
                    
                    Text(event.date, style: .date)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                
                Text(event.cause)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding(8)
        .background(severityColor.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    private var severityColor: Color {
        switch event.severity {
        case .mild: return .yellow
        case .moderate: return .orange
        case .significant: return .red
        }
    }
}

// MARK: - Info Sheet

struct TrainingZoneInfoSheet: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("What Are Training Zones?")) {
                    Text("Training zones are intensity ranges based on your functional threshold (FTP for cycling, threshold pace for running). Each zone targets different physiological adaptations.")
                }
                
                Section(header: Text("Auto-Detected Thresholds")) {
                    VStack(alignment: .leading, spacing: 12) {
                        ZoneInfoRow(
                            title: "Critical Power/Pace",
                            description: "Average of your top sustained efforts (15-60 min) from the last 120 days.",
                            icon: "bolt.fill",
                            color: .orange
                        )
                        
                        Divider()
                        
                        ZoneInfoRow(
                            title: "Functional Threshold",
                            description: "95% of critical power/pace. Based on last 120 days of training.",
                            icon: "chart.line.uptrend.xyaxis",
                            color: .blue
                        )
                    }
                }
                
                Section(header: Text("The 7 Training Zones")) {
                    TrainingZoneRow(number: 1, name: "Recovery", range: "0-55% FTP", purpose: "Active recovery", color: .gray)
                    TrainingZoneRow(number: 2, name: "Endurance", range: "56-75% FTP", purpose: "Build aerobic base", color: .blue)
                    TrainingZoneRow(number: 3, name: "Tempo", range: "76-90% FTP", purpose: "Increase endurance", color: .green)
                    TrainingZoneRow(number: 4, name: "Threshold", range: "91-105% FTP", purpose: "Raise threshold", color: .yellow)
                    TrainingZoneRow(number: 5, name: "VO2max", range: "106-120% FTP", purpose: "Max aerobic capacity", color: .orange)
                    TrainingZoneRow(number: 6, name: "Anaerobic", range: "121-150% FTP", purpose: "Anaerobic power", color: .red)
                    TrainingZoneRow(number: 7, name: "Sprint", range: ">150% FTP", purpose: "Neuromuscular", color: .purple)
                }
                
                Section(header: Text("Training Distribution Models")) {
                    Text("Different training philosophies work for different athletes and schedules. The app auto-detects which model fits your current training.")
                    
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Polarized (80/20)")
                                .fontWeight(.semibold)
                            Text("80% easy, minimal moderate, 20% hard. Maximizes fitness with limited time. Good for time-crunched athletes.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Divider()
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Pyramidal")
                                .fontWeight(.semibold)
                            Text("80% easy, 15% moderate, 5% hard. Classic endurance model. Most sustainable long-term.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Divider()
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Threshold-Based")
                                .fontWeight(.semibold)
                            Text("70% easy, 20% threshold/tempo, 10% hard. Builds race-specific fitness efficiently.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                Section(header: Text("Efficiency Factor")) {
                    Text("Power or pace per heart beat. Improving EF means you're producing more output for the same cardiovascular cost - a key indicator of improving aerobic fitness.")
                }
                
                Section(header: Text("Decoupling")) {
                    Text("When heart rate stays elevated but power/pace drops during long efforts. Usually indicates glycogen depletion or dehydration. Helps you dial in fueling strategy.")
                }
            }
            .navigationTitle("Training Zones")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("Done") { dismiss() }
            }
        }
        .presentationDetents([.large])
    }
}

struct ZoneInfoRow: View {
    let title: String
    let description: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .fontWeight(.semibold)
                
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct TrainingZoneRow: View {
    let number: Int
    let name: String
    let range: String
    let purpose: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            Text("Z\(number)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(color)
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(name)
                        .fontWeight(.semibold)
                    
                    Spacer()
                    
                    Text(range)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Text(purpose)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// Make TrainingZone conform to Identifiable
extension TrainingZoneAnalyzer.TrainingZone: Identifiable {
    var id: Int { number }
}
