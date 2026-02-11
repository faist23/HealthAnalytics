//
//  ACWRTrendCard.swift (FIXED)
//  HealthAnalytics
//
//  Compatible with existing PredictiveReadinessService
//

import SwiftUI
import Charts

// Simple model for ACWR data points
struct ACWRDataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
}

struct ACWRTrendCard: View {
    let trend: [ACWRDataPoint]
    let currentAssessment: PredictiveReadinessService.ReadinessAssessment
    let primaryActivity: String
    
    @State private var showInfoSheet = false
    
    private var hasValidTrend: Bool {
        // Only show if there's meaningful variation (not flat line)
        let values = trend.map { $0.value }
        guard let min = values.min(), let max = values.max() else { return false }
        return (max - min) > 0.05 // At least 5% variation
    }
    
    private var interpretation: String {
        let latest = currentAssessment.acwr
        if latest < 0.8 {
            return "You're well-rested. This is a good time to increase training volume or intensity on your \(primaryActivity.lowercased())s."
        } else if latest <= 1.3 {
            return "You're in the sweet spot for building fitness. Your training load is sustainable."
        } else if latest <= 1.5 {
            return "Training load is high. Monitor how you feel and consider adding more recovery."
        } else {
            return "Your body needs rest. High risk of overtraining or injury."
        }
    }
    
    private var stateLabel: String {
        switch currentAssessment.trend {
        case .building: return "Building"
        case .optimal: return "Optimal"
        case .detraining: return "Detraining"
        }
    }
    
    private var stateColor: Color {
        switch currentAssessment.trend {
        case .building: return .orange
        case .optimal: return .green
        case .detraining: return .blue
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with info button
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("TRAINING LOAD BALANCE")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 8) {
                        Text(stateLabel)
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(stateColor)
                        
                        Button {
                            showInfoSheet = true
                        } label: {
                            Image(systemName: "info.circle")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }
                }
                
                Spacer()
                
                // Current ratio - big and prominent
                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "%.2f", currentAssessment.acwr))
                        .font(.system(size: 32, weight: .black, design: .monospaced))
                        .foregroundColor(stateColor)
                    Text("ratio")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            // Interpretation
            Text(interpretation)
                .font(.subheadline)
                .foregroundColor(.primary)
                .padding(.vertical, 8)
            
            // Chart - only show if there's actual variation
            if hasValidTrend {
                Chart {
                    // Sweet spot zone (0.8 - 1.3)
                    RectangleMark(
                        xStart: .value("Start", trend.first?.date ?? Date()),
                        xEnd: .value("End", trend.last?.date ?? Date()),
                        yStart: .value("Low", 0.8),
                        yEnd: .value("High", 1.3)
                    )
                    .foregroundStyle(.green.opacity(0.15))
                    .annotation(position: .overlay, alignment: .topTrailing) {
                        Text("Sweet Spot")
                            .font(.caption2)
                            .foregroundColor(.green.opacity(0.6))
                            .padding(.trailing, 4)
                            .padding(.top, 4)
                    }
                    
                    // Baseline at 1.0
                    RuleMark(y: .value("Baseline", 1.0))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5]))
                        .foregroundStyle(.gray.opacity(0.5))
                    
                    // Actual trend line
                    ForEach(trend) { day in
                        LineMark(
                            x: .value("Date", day.date, unit: .day),
                            y: .value("Ratio", day.value)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(stateColor)
                        .lineStyle(StrokeStyle(lineWidth: 3))
                        
                        PointMark(
                            x: .value("Date", day.date, unit: .day),
                            y: .value("Ratio", day.value)
                        )
                        .foregroundStyle(stateColor)
                    }
                }
                .frame(height: 140)
                .chartYScale(domain: 0.5...2.0)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                            .font(.caption2)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text(String(format: "%.1f", v))
                                    .font(.caption2)
                            }
                        }
                        AxisGridLine()
                    }
                }
            } else {
                // Flat line explanation
                VStack(spacing: 8) {
                    Image(systemName: "chart.line.flattrend.xyaxis")
                        .font(.title)
                        .foregroundColor(.secondary)
                    
                    Text("Consistent Training Load")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Text("Your training load has been very consistent over the past week. This is good - it means you're training predictably!")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            }
            
            // What this means section
            VStack(alignment: .leading, spacing: 8) {
                Text("What This Means")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .textCase(.uppercase)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Acute Load")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(String(format: "%.0f", currentAssessment.acuteLoad))
                            .font(.callout)
                            .fontWeight(.semibold)
                        Text("last 7 days")
                            .font(.caption2)
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                    
                    Image(systemName: "arrow.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Chronic Load")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(String(format: "%.0f", currentAssessment.chronicLoad))
                            .font(.callout)
                            .fontWeight(.semibold)
                        Text("last 28 days")
                            .font(.caption2)
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                }
            }
            .padding(.top, 8)
        }
        .padding()
        .sheet(isPresented: $showInfoSheet) {
            ACWRExplainerSheet()
        }
    }
}

// Rename to avoid conflict with existing ACWRInfoSheet
struct ACWRExplainerSheet: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    
                    Group {
                        Text("Understanding Your Training Load")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("The Acute:Chronic Workload Ratio (ACWR) helps you train hard while staying healthy.")
                            .foregroundColor(.secondary)
                    }
                    
                    Divider()
                    
                    Group {
                        Text("How It Works")
                            .font(.headline)
                        
                        Text("We compare your recent training (last 7 days) to your normal training (last 28 days):")
                            .foregroundColor(.secondary)
                        
                        VStack(alignment: .leading, spacing: 12) {
                            bulletPoint(
                                icon: "7.circle.fill",
                                color: .blue,
                                title: "Acute Load",
                                description: "Your training from the past week"
                            )
                            
                            bulletPoint(
                                icon: "28.circle.fill",
                                color: .green,
                                title: "Chronic Load",
                                description: "Your average training over the past month"
                            )
                            
                            bulletPoint(
                                icon: "divide.circle.fill",
                                color: .purple,
                                title: "The Ratio",
                                description: "Acute ÷ Chronic = How much harder you're training than normal"
                            )
                        }
                    }
                    
                    Divider()
                    
                    Group {
                        Text("What The Numbers Mean")
                            .font(.headline)
                        
                        VStack(alignment: .leading, spacing: 12) {
                            rangeCard(
                                range: "< 0.8",
                                label: "Fresh",
                                color: .blue,
                                description: "You're training less than usual. Good time to push harder or you risk losing fitness."
                            )
                            
                            rangeCard(
                                range: "0.8 - 1.3",
                                label: "Sweet Spot",
                                color: .green,
                                description: "Perfect balance. You're building fitness safely without overloading your body."
                            )
                            
                            rangeCard(
                                range: "1.3 - 1.5",
                                label: "Overreaching",
                                color: .orange,
                                description: "Training load is high. Monitor how you feel and be ready to dial it back if needed."
                            )
                            
                            rangeCard(
                                range: "> 1.5",
                                label: "Danger Zone",
                                color: .red,
                                description: "High injury risk. You're training significantly harder than your body is prepared for."
                            )
                        }
                    }
                    
                    Divider()
                    
                    Group {
                        Text("Example")
                            .font(.headline)
                        
                        Text("If your ACWR is 1.4:")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Text("You're training 40% harder than your recent average. This might be intentional (race week, training camp), but if it's not planned, consider adding recovery.")
                            .foregroundColor(.secondary)
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                    }
                }
                .padding()
            }
            .navigationTitle("Training Load Guide")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func bulletPoint(icon: String, color: Color, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func rangeCard(range: String, label: String, color: Color, description: String) -> some View {
        HStack(spacing: 12) {
            Text(range)
                .font(.system(.callout, design: .monospaced))
                .fontWeight(.bold)
                .foregroundColor(color)
                .frame(width: 60, alignment: .leading)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 8)
    }
}

#Preview {
    ACWRTrendCard(
        trend: [
            ACWRDataPoint(date: Date().addingTimeInterval(-6*86400), value: 1.1),
            ACWRDataPoint(date: Date().addingTimeInterval(-5*86400), value: 1.15),
            ACWRDataPoint(date: Date().addingTimeInterval(-4*86400), value: 1.2),
            ACWRDataPoint(date: Date().addingTimeInterval(-3*86400), value: 1.25),
            ACWRDataPoint(date: Date().addingTimeInterval(-2*86400), value: 1.1),
            ACWRDataPoint(date: Date().addingTimeInterval(-1*86400), value: 1.0),
            ACWRDataPoint(date: Date(), value: 0.95)
        ],
        currentAssessment: .init(
            acwr: 0.95,
            chronicLoad: 100,
            acuteLoad: 95,
            trend: .optimal
        ),
        primaryActivity: "Ride"
    )
    .cardStyle(for: .recovery)
    .padding()
}
