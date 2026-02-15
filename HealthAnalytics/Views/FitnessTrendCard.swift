//
//  FitnessTrendCard.swift
//  HealthAnalytics
//
//  Comprehensive VO2max and fitness trend visualization
//

import SwiftUI
import Charts

// MARK: - Main Fitness Trend Card

struct FitnessTrendCard: View {
    let analysis: FitnessTrendAnalyzer.FitnessAnalysis
    @State private var showInfo = false
    @State private var selectedSection: Section = .overview
    
    enum Section: String, CaseIterable {
        case overview = "Overview"
        case trends = "Trends"
        case projections = "Future"
        
        var icon: String {
            switch self {
            case .overview: return "heart.fill"
            case .trends: return "chart.line.uptrend.xyaxis"
            case .projections: return "chart.line.uptrend.xyaxis"
            }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                HStack(spacing: 4) {
                    Text("FITNESS TRENDS")
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
                
                Text("VO2max Analysis")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
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
            case .overview:
                overviewView
            case .trends:
                trendsView
            case .projections:
                projectionsView
            }
        }
        .padding(20)
        .sheet(isPresented: $showInfo) {
            FitnessTrendInfoSheet()
        }
    }
    
    // MARK: - Overview View
    
    private var overviewView: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Current VO2max
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Current VO2max")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(Int(analysis.vo2maxTrend.currentValue))")
                            .font(.system(size: 48, weight: .bold))
                        Text("ml/kg/min")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                // Trend indicator
                VStack(alignment: .trailing, spacing: 4) {
                    Image(systemName: trendIcon(analysis.vo2maxTrend.trend))
                        .font(.title)
                        .foregroundStyle(trendColor(analysis.vo2maxTrend.trend))
                    
                    Text(trendText(analysis.vo2maxTrend.trend))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Divider()
            
            // Fitness Age
            if let fitnessAge = analysis.fitnessAge {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Fitness Age")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("\(fitnessAge.fitnessAge)")
                                .font(.title)
                                .fontWeight(.bold)
                                .foregroundStyle(Color(fitnessAge.classification.color))
                            
                            if fitnessAge.fitnessAge < fitnessAge.chronologicalAge {
                                Text("\(fitnessAge.chronologicalAge - fitnessAge.fitnessAge) years younger")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            } else if fitnessAge.fitnessAge > fitnessAge.chronologicalAge {
                                Text("\(fitnessAge.fitnessAge - fitnessAge.chronologicalAge) years older")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            } else {
                                Text("matches age")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(fitnessAge.classification.description)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color(fitnessAge.classification.color))
                        
                        Text("Top \(Int(100 - fitnessAge.percentile))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .background(Color(fitnessAge.classification.color).opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            
            // Fitness Balance
            VStack(alignment: .leading, spacing: 8) {
                Text("Fitness Balance")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                HStack(spacing: 16) {
                    // Aerobic
                    VStack(spacing: 4) {
                        ZStack {
                            Circle()
                                .stroke(Color.blue.opacity(0.2), lineWidth: 8)
                            
                            Circle()
                                .trim(from: 0, to: analysis.fitnessBalance.aerobicFitness / 100)
                                .stroke(Color.blue, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                            
                            Text("\(Int(analysis.fitnessBalance.aerobicFitness))")
                                .font(.title3)
                                .fontWeight(.bold)
                        }
                        .frame(width: 80, height: 80)
                        
                        Text("Aerobic")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    // Anaerobic
                    VStack(spacing: 4) {
                        ZStack {
                            Circle()
                                .stroke(Color.red.opacity(0.2), lineWidth: 8)
                            
                            Circle()
                                .trim(from: 0, to: analysis.fitnessBalance.anaerobicFitness / 100)
                                .stroke(Color.red, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                            
                            Text("\(Int(analysis.fitnessBalance.anaerobicFitness))")
                                .font(.title3)
                                .fontWeight(.bold)
                        }
                        .frame(width: 80, height: 80)
                        
                        Text("Anaerobic")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Text(analysis.fitnessBalance.recommendation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .background(Color.blue.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }
    
    // MARK: - Trends View
    
    private var trendsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("VO2max Progress")
                .font(.subheadline)
                .fontWeight(.semibold)
            
            // Chart of recent measurements
            if !analysis.vo2maxTrend.recentMeasurements.isEmpty {
                Chart(analysis.vo2maxTrend.recentMeasurements) { measurement in
                    LineMark(
                        x: .value("Date", measurement.date),
                        y: .value("VO2max", measurement.value)
                    )
                    .foregroundStyle(.blue)
                    .interpolationMethod(.catmullRom)
                    
                    PointMark(
                        x: .value("Date", measurement.date),
                        y: .value("VO2max", measurement.value)
                    )
                    .foregroundStyle(.blue)
                }
                .chartYAxisLabel("ml/kg/min")
                .frame(height: 150)
            }
            
            // Change metrics
            VStack(spacing: 12) {
                ChangeRow(
                    period: "30 Days",
                    change: analysis.vo2maxTrend.thirtyDayChange,
                    icon: "calendar"
                )
                
                ChangeRow(
                    period: "90 Days",
                    change: analysis.vo2maxTrend.ninetyDayChange,
                    icon: "calendar.badge.clock"
                )
                
                if let yearChange = analysis.vo2maxTrend.yearOverYearChange {
                    ChangeRow(
                        period: "Year",
                        change: yearChange,
                        icon: "calendar.circle"
                    )
                }
            }
            
            // Confidence
            HStack(spacing: 8) {
                Image(systemName: confidenceIcon(analysis.vo2maxTrend.confidence))
                    .foregroundStyle(confidenceColor(analysis.vo2maxTrend.confidence))
                
                Text("Confidence: \(confidenceText(analysis.vo2maxTrend.confidence))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Text("(\(analysis.vo2maxTrend.recentMeasurements.count) measurements)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            // Training Effectiveness
            Divider()
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Training Effectiveness")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    Spacer()
                    
                    Text("\(Int(analysis.trainingEffectiveness.score))/100")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundStyle(effectivenessColor(analysis.trainingEffectiveness.score))
                }
                
                Text(analysis.trainingEffectiveness.interpretation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                ForEach(analysis.trainingEffectiveness.insights, id: \.self) { insight in
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.blue)
                        Text(insight)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
    
    // MARK: - Projections View
    
    private var projectionsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Fitness Projections")
                .font(.subheadline)
                .fontWeight(.semibold)
            
            // Current vs Ceiling
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Genetic Potential")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    Text("\(Int(analysis.projections.percentOfCeiling))% of ceiling")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Background
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 40)
                        
                        // Progress
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.purple)
                            .frame(
                                width: geometry.size.width * (analysis.projections.percentOfCeiling / 100),
                                height: 40
                            )
                    }
                }
                .frame(height: 40)
                
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Current")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("\(Int(analysis.vo2maxTrend.currentValue))")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Ceiling")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("\(Int(analysis.projections.estimatedCeiling))")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                }
            }
            
            Divider()
            
            // Future projections
            if let projected30 = analysis.projections.projectedVO2maxIn30Days,
               let projected90 = analysis.projections.projectedVO2maxIn90Days {
                VStack(spacing: 12) {
                    ProjectionRow(
                        timeframe: "In 30 Days",
                        value: projected30,
                        current: analysis.vo2maxTrend.currentValue
                    )
                    
                    ProjectionRow(
                        timeframe: "In 90 Days",
                        value: projected90,
                        current: analysis.vo2maxTrend.currentValue
                    )
                }
            } else {
                Text("Insufficient data for projections")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.orange.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            
            // Time to plateau
            if let timeToPlateau = analysis.projections.timeToPlateauEstimate {
                HStack(spacing: 8) {
                    Image(systemName: "clock.fill")
                        .foregroundStyle(.blue)
                    
                    Text("Estimated time to plateau: \(timeToPlateau)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(8)
                .background(Color.blue.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            
            Divider()
            
            // Recommendations
            VStack(alignment: .leading, spacing: 8) {
                Text("Recommendations")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                ForEach(analysis.recommendations, id: \.self) { recommendation in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: iconForRecommendation(recommendation))
                            .font(.caption)
                            .foregroundStyle(colorForRecommendation(recommendation))
                            .frame(width: 20)
                        
                        Text(recommendation)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
    
    // MARK: - Helper Views
    
    private func trendIcon(_ trend: FitnessTrendAnalyzer.VO2maxTrend.TrendDirection) -> String {
        switch trend {
        case .improving: return "arrow.up.circle.fill"
        case .stable: return "minus.circle.fill"
        case .declining: return "arrow.down.circle.fill"
        case .rapidDecline: return "exclamationmark.triangle.fill"
        }
    }
    
    private func trendColor(_ trend: FitnessTrendAnalyzer.VO2maxTrend.TrendDirection) -> Color {
        switch trend {
        case .improving: return .green
        case .stable: return .blue
        case .declining: return .orange
        case .rapidDecline: return .red
        }
    }
    
    private func trendText(_ trend: FitnessTrendAnalyzer.VO2maxTrend.TrendDirection) -> String {
        switch trend {
        case .improving: return "Improving"
        case .stable: return "Stable"
        case .declining: return "Declining"
        case .rapidDecline: return "Rapid Decline"
        }
    }
    
    private func confidenceIcon(_ confidence: FitnessTrendAnalyzer.VO2maxTrend.Confidence) -> String {
        switch confidence {
        case .high: return "checkmark.circle.fill"
        case .medium: return "checkmark.circle"
        case .low: return "exclamationmark.circle"
        case .insufficient: return "xmark.circle"
        }
    }
    
    private func confidenceColor(_ confidence: FitnessTrendAnalyzer.VO2maxTrend.Confidence) -> Color {
        switch confidence {
        case .high: return .green
        case .medium: return .blue
        case .low: return .orange
        case .insufficient: return .red
        }
    }
    
    private func confidenceText(_ confidence: FitnessTrendAnalyzer.VO2maxTrend.Confidence) -> String {
        switch confidence {
        case .high: return "High"
        case .medium: return "Medium"
        case .low: return "Low"
        case .insufficient: return "Insufficient"
        }
    }
    
    private func effectivenessColor(_ score: Double) -> Color {
        if score >= 70 {
            return .green
        } else if score >= 50 {
            return .blue
        } else if score >= 30 {
            return .orange
        } else {
            return .red
        }
    }
    
    private func iconForRecommendation(_ text: String) -> String {
        if text.contains("✅") { return "checkmark.circle.fill" }
        if text.contains("💡") { return "lightbulb.fill" }
        if text.contains("⚠️") { return "exclamationmark.triangle.fill" }
        if text.contains("🚨") { return "exclamationmark.octagon.fill" }
        return "info.circle.fill"
    }
    
    private func colorForRecommendation(_ text: String) -> Color {
        if text.contains("✅") { return .green }
        if text.contains("💡") { return .blue }
        if text.contains("⚠️") { return .orange }
        if text.contains("🚨") { return .red }
        return .blue
    }
}

// MARK: - Supporting Views

struct ChangeRow: View {
    let period: String
    let change: Double
    let icon: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 24)
            
            Text(period)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Spacer()
            
            HStack(spacing: 4) {
                Image(systemName: change >= 0 ? "arrow.up" : "arrow.down")
                    .font(.caption)
                    .foregroundStyle(change >= 0 ? .green : .red)
                
                Text(String(format: "%+.1f", change))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(change >= 0 ? .green : .red)
                
                Text("ml/kg/min")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct ProjectionRow: View {
    let timeframe: String
    let value: Double
    let current: Double
    
    var body: some View {
        HStack {
            Text(timeframe)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Spacer()
            
            HStack(spacing: 8) {
                Text("\(Int(value))")
                    .font(.caption)
                    .fontWeight(.semibold)
                
                HStack(spacing: 2) {
                    Image(systemName: value > current ? "arrow.up" : "arrow.down")
                        .font(.caption2)
                    Text(String(format: "%+.1f", value - current))
                        .font(.caption2)
                }
                .foregroundStyle(value > current ? .green : .orange)
            }
        }
        .padding(8)
        .background(Color.gray.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Info Sheet

struct FitnessTrendInfoSheet: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("What is VO2max?")) {
                    Text("VO2max is the maximum amount of oxygen your body can utilize during intense exercise. It's the gold standard measure of cardiorespiratory fitness and a strong predictor of endurance performance and longevity.")
                }
                
                Section(header: Text("Fitness Age")) {
                    Text("Your fitness age compares your VO2max to population norms. A fitness age younger than your chronological age indicates superior cardiovascular health.")
                    
                    Text("Based on data from the Cooper Institute and ACSM guidelines comparing thousands of athletes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Section(header: Text("Aerobic vs Anaerobic Balance")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("**Aerobic Fitness:** VO2max-based. Your ability to sustain moderate intensity for long durations.")
                        Text("**Anaerobic Fitness:** Based on high-intensity workout frequency. Your ability to produce power in short, hard efforts.")
                    }
                    .font(.caption)
                }
                
                Section(header: Text("Training Effectiveness")) {
                    Text("Measures how well your training load translates to fitness gains. High effectiveness means you're responding well to current training. Low effectiveness may indicate overtraining, undertraining, or need for stimulus change.")
                }
                
                Section(header: Text("Genetic Ceiling")) {
                    Text("An estimate of your maximum potential VO2max based on population data, age, and gender. Most athletes reach 85-95% of their ceiling with dedicated training.")
                    
                    Text("Elite endurance athletes typically have VO2max values of 70-85 ml/kg/min (male) or 60-75 ml/kg/min (female).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Section(header: Text("Data Source")) {
                    Text("VO2max measurements come from your Apple Watch, which estimates VO2max during outdoor walks, runs, and hikes using heart rate and GPS data.")
                        .font(.caption)
                }
            }
            .navigationTitle("Fitness Trends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("Done") { dismiss() }
            }
        }
        .presentationDetents([.large])
    }
}
