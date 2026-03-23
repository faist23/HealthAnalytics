//
//  AgingAlphaCard.swift
//  HealthAnalytics
//
//  Premium card for displaying Biological Aging vs Chronological Age.
//

import SwiftUI

struct AgingAlphaCard: View {
    let assessment: BiologicalAgingService.AgingAssessment
    @State private var showDetails = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header with Premium Icon
            HStack {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [.yellow, .orange.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: "sparkles")
                        .font(.title3)
                        .foregroundStyle(.white)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Biological Aging")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    
                    Text("Aging Alpha Score")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Alpha Badge
                Text(String(format: "%+.1f", assessment.agingAlpha))
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(assessment.status.color.opacity(0.15))
                    .foregroundStyle(assessment.status.color)
                    .clipShape(Capsule())
            }
            
            // The Big Comparison
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Actual Age")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(assessment.chronologicalAge)")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                Image(systemName: "arrow.right")
                    .font(.title2)
                    .foregroundStyle(.secondary.opacity(0.5))
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Bio-Age")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.1f", assessment.biologicalAge))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(assessment.status.color)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.vertical, 10)
            
            // Status Indicator
            HStack {
                Image(systemName: assessment.status.icon)
                Text(assessment.status.rawValue)
                    .fontWeight(.semibold)
                Spacer()
            }
            .font(.subheadline)
            .padding()
            .background(assessment.status.color.opacity(0.1))
            .foregroundStyle(assessment.status.color)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            Divider()
            
            // Supporting Insights
            VStack(spacing: 12) {
                AgingMetricRow(
                    label: "HRV vs Peers",
                    value: "\(Int(assessment.hrvRetained))%",
                    description: assessment.hrvRetained >= 100 ? "Above average for age" : "Below average for age",
                    icon: "waveform.path.ecg",
                    color: .red
                )
                
                AgingMetricRow(
                    label: "Aging Velocity",
                    value: String(format: "%.1f ms/y", assessment.yearlyHRVDecline),
                    description: assessment.yearlyHRVDecline < assessment.averageHRVDecline ? "Slower than population avg" : "Faster than population avg",
                    icon: "chart.line.downtrend.xyaxis",
                    color: .blue
                )
                
                if assessment.rhrStability > 0 {
                    AgingMetricRow(
                        label: "Heart Efficiency",
                        value: String(format: "-%.0f bpm", assessment.rhrStability),
                        description: "Stable heart rate over 5 years",
                        icon: "heart.fill",
                        color: .green
                    )
                }
            }
            
            // Educational Footer
            Text("Calculated using 10-year HRV/RHR trends vs. standard human biological decay curves (1.5ms HRV drop/year).")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
        }
        .padding(20)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(white: colorScheme == .dark ? 0.15 : 0.98))
                
                // Subtle "Premium" Gold border for Aging Alpha
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [.yellow.opacity(0.5), .orange.opacity(0.3), .yellow.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
            }
        )
        .shadow(color: .black.opacity(0.05), radius: 10, y: 5)
    }
    
    @Environment(\.colorScheme) var colorScheme
}

private struct AgingMetricRow: View {
    let label: String
    let value: String
    let description: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(color)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .fontWeight(.medium)
                Text(description)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Text(value)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundStyle(.primary)
        }
    }
}

#Preview {
    VStack {
        AgingAlphaCard(assessment: BiologicalAgingService.AgingAssessment(
            chronologicalAge: 45,
            biologicalAge: 34.2,
            agingAlpha: 10.8,
            hrvRetained: 124,
            rhrStability: 4.0,
            yearlyHRVDecline: 0.4
        ))
        .padding()
        
        AgingAlphaCard(assessment: BiologicalAgingService.AgingAssessment(
            chronologicalAge: 45,
            biologicalAge: 48.5,
            agingAlpha: -3.5,
            hrvRetained: 88,
            rhrStability: -2.0,
            yearlyHRVDecline: 1.8
        ))
        .padding()
    }
    .background(Color(.systemGroupedBackground))
}
