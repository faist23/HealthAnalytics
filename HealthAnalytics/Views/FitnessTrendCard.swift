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
        VStack(alignment: .leading, spacing: .spacingMd) {
            // Header
            HStack {
                HStack(spacing: .spacingXs) {
                    Text("FITNESS TRENDS")
                        .font(.headline)
                    
                    Button {
                        showInfo = true
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.caption)
                            .foregroundStyle(Color.accent)
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
        VStack(alignment: .leading, spacing: .spacingMd) {
            // Current VO2max
            HStack {
                VStack(alignment: .leading, spacing: .spacingXs) {
                    Text("Current VO2max")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    HStack(alignment: .firstTextBaseline, spacing: .spacingXs) {
                        Text("\(Int(analysis.vo2maxTrend.currentValue))")
                            .font(.system(size: 48, weight: .bold))
                        Text("ml/kg/min")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                // Trend indicator
                VStack(alignment: .trailing, spacing: .spacingXs) {
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
                    VStack(alignment: .leading, spacing: .spacingXs) {
                        Text("Fitness Age")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        HStack(alignment: .firstTextBaseline, spacing: .spacingSm) {
                            Text("\(fitnessAge.fitnessAge)")
                                .font(.title)
                                .fontWeight(.bold)
                                .foregroundStyle(Color(fitnessAge.classification.color))
                            
                            if fitnessAge.fitnessAge < fitnessAge.chronologicalAge {
                                Text("\(fitnessAge.chronologicalAge - fitnessAge.fitnessAge) years younger")
                                    .font(.caption)
                                    .foregroundStyle(Color.statusOptimal)
                            } else if fitnessAge.fitnessAge > fitnessAge.chronologicalAge {
                                Text("\(fitnessAge.fitnessAge - fitnessAge.chronologicalAge) years older")
                                    .font(.caption)
                                    .foregroundStyle(Color.statusWarning)
                            } else {
                                Text("matches age")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: .spacingXs) {
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
                .clipShape(RoundedRectangle(cornerRadius: .radiusSm))
            }
            
            // Fitness Balance
            VStack(alignment: .leading, spacing: .spacingSm) {
                Text("Fitness Balance")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                HStack(spacing: .spacingMd) {
                    // Aerobic
                    VStack(spacing: .spacingXs) {
                        ZStack {
                            Circle()
                                .stroke(Color.statusRest.opacity(0.2), lineWidth: 8)

                            Circle()
                                .trim(from: 0, to: analysis.fitnessBalance.aerobicFitness / 100)
                                .stroke(Color.statusRest, style: StrokeStyle(lineWidth: 8, lineCap: .round))
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
                    VStack(spacing: .spacingXs) {
                        ZStack {
                            Circle()
                                .stroke(Color.statusWarning.opacity(0.2), lineWidth: 8)

                            Circle()
                                .trim(from: 0, to: analysis.fitnessBalance.anaerobicFitness / 100)
                                .stroke(Color.statusWarning, style: StrokeStyle(lineWidth: 8, lineCap: .round))
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
                    .padding(.spacingSm)
                    .background(Color.statusRest.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }
    
    // MARK: - Trends View
    
    private var trendsView: some View {
        VStack(alignment: .leading, spacing: .spacingMd) {
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
                    .foregroundStyle(Color.statusRest)
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("Date", measurement.date),
                        y: .value("VO2max", measurement.value)
                    )
                    .foregroundStyle(Color.statusRest)
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
            HStack(spacing: .spacingSm) {
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
            
            VStack(alignment: .leading, spacing: .spacingSm) {
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
                    HStack(spacing: .spacingSm) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(Color.statusOptimal)
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
        VStack(alignment: .leading, spacing: .spacingMd) {
            Text("Fitness Projections")
                .font(.subheadline)
                .fontWeight(.semibold)
            
            // Current vs Ceiling
            VStack(alignment: .leading, spacing: .spacingSm) {
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
                        RoundedRectangle(cornerRadius: .radiusSm)
                            .fill(Color.textTertiary.opacity(0.2))
                            .frame(height: 40)

                        // Progress
                        RoundedRectangle(cornerRadius: .radiusSm)
                            .fill(Color.accent)
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
                    .background(Color.statusWarning.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: .radiusSm))
            }
            
            // Time to plateau
            if let timeToPlateau = analysis.projections.timeToPlateauEstimate {
                HStack(spacing: .spacingSm) {
                    Image(systemName: "clock.fill")
                        .foregroundStyle(Color.statusRest)

                    Text("Estimated time to plateau: \(timeToPlateau)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.spacingSm)
                .background(Color.statusRest.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            
            Divider()
            
            // Recommendations
            VStack(alignment: .leading, spacing: .spacingSm) {
                Text("Recommendations")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                ForEach(analysis.recommendations, id: \.self) { recommendation in
                    HStack(alignment: .top, spacing: .spacingSm) {
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
        case .improving: return .statusOptimal
        case .stable: return .statusRest
        case .declining: return .statusWarning
        case .rapidDecline: return .statusWarning
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
        case .high: return .statusOptimal
        case .medium: return .statusRest
        case .low: return .statusWarning
        case .insufficient: return .statusWarning
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
            return .statusOptimal
        } else if score >= 50 {
            return .statusRest
        } else if score >= 30 {
            return .statusWarning
        } else {
            return .statusWarning
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
        if text.contains("✅") { return .statusOptimal }
        if text.contains("💡") { return .statusRest }
        if text.contains("⚠️") { return .statusWarning }
        if text.contains("🚨") { return .statusWarning }
        return .statusRest
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
            
            HStack(spacing: .spacingXs) {
                Image(systemName: change >= 0 ? "arrow.up" : "arrow.down")
                    .font(.caption)
                    .foregroundStyle(change >= 0 ? Color.statusOptimal : Color.statusWarning)

                Text(String(format: "%+.1f", change))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(change >= 0 ? Color.statusOptimal : Color.statusWarning)
                
                Text("ml/kg/min")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, .spacingXs)
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
            
            HStack(spacing: .spacingSm) {
                Text("\(Int(value))")
                    .font(.caption)
                    .fontWeight(.semibold)
                
                HStack(spacing: 2) {
                    Image(systemName: value > current ? "arrow.up" : "arrow.down")
                        .font(.caption2)
                    Text(String(format: "%+.1f", value - current))
                        .font(.caption2)
                }
                .foregroundStyle(value > current ? Color.statusOptimal : Color.statusWarning)
            }
        }
        .padding(.spacingSm)
        .background(Color.textTertiary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Info Sheet

struct FitnessTrendInfoSheet: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            List {
                // IMPORTANT: Research-based context about VO2 max limitations
                Section(header: Text("⚠️ Important Context")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("This app shows VO2max data from Apple Watch, but it's important to understand its limitations:")
                            .fontWeight(.semibold)
                        
                        VStack(alignment: .leading, spacing: .spacingSm) {
                            HStack(alignment: .top, spacing: .spacingSm) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(Color.statusWarning)
                                    .font(.caption)
                                
                                Text("Smartwatch VO2max has a mean error of 7-16% and consistently underestimates in fit individuals")
                                    .font(.caption)
                            }
                            
                            HStack(alignment: .top, spacing: .spacingSm) {
                                Image(systemName: "chart.bar.fill")
                                    .foregroundStyle(Color.statusRest)
                                    .font(.caption)
                                
                                Text("99% of longevity research uses METs (metabolic equivalents), not VO2max measurements")
                                    .font(.caption)
                            }
                            
                            HStack(alignment: .top, spacing: .spacingSm) {
                                Image(systemName: "heart.fill")
                                    .foregroundStyle(Color.statusWarning)
                                    .font(.caption)
                                
                                Text("This app emphasizes multiple metrics (HRV, training load, recovery, METs) rather than fixating on VO2max alone")
                                    .font(.caption)
                            }
                        }
                    }
                }
                .listRowBackground(Color.statusWarning.opacity(0.1))
                
                Section(header: Text("What is VO2max?")) {
                    Text("VO2max is the maximum amount of oxygen your body can utilize during intense exercise. While historically considered the gold standard for cardiorespiratory fitness, it's one of many important health metrics.")
                }
                
                Section(header: Text("Apple Watch Measurement")) {
                    Text("Your Apple Watch estimates VO2max during outdoor walks, runs, and hikes using heart rate and GPS data. This is an algorithmic estimation, not a direct gas exchange measurement.")
                    
                    Text("Research shows smartwatch estimates have 7-16% error rates and tend to underestimate in fit individuals while overestimating in less fit individuals.")
                        .font(.caption)
                        .foregroundStyle(Color.statusWarning)
                        .fontWeight(.semibold)
                }
                
                Section(header: Text("Why We Show Multiple Metrics")) {
                    VStack(alignment: .leading, spacing: .spacingSm) {
                        Text("**MET-minutes:** Based on 750,000+ participant studies. Each MET increase = 14-15% mortality reduction.")
                        
                        Text("**Training Balance:** People who do both aerobic and strength training have lower all-cause mortality than people who do neither.")
                        
                        Text("**HRV & Recovery:** Real-time markers of your body's recovery state and adaptation.")
                        
                        Text("**Training Load (ACWR):** Proven injury risk predictor.")
                    }
                    .font(.caption)
                }
                
                Section(header: Text("Fitness Age")) {
                    Text("Your fitness age compares your VO2max to population norms. A fitness age younger than your chronological age indicates superior cardiovascular health.")
                    
                    Text("Based on data from the Cooper Institute and ACSM guidelines. Remember: This is one data point among many.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Section(header: Text("Aerobic vs Anaerobic Balance")) {
                    VStack(alignment: .leading, spacing: .spacingSm) {
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
                
                Section(header: Text("Bottom Line")) {
                    Text("VO2max is a useful metric but not the complete picture. This app uses a multi-factorial approach based on current research, emphasizing the combination of multiple health markers for a more complete view of your fitness and recovery.")
                        .fontWeight(.semibold)
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
