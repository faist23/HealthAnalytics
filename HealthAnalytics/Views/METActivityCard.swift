//
//  METActivityCard.swift
//  HealthAnalytics
//
//  MET-based activity display - evidence-based fitness metric
//  Shows weekly MET-minutes with intensity breakdown
//

import SwiftUI
import Charts

struct METActivityCard: View {
    let summary: METAnalyzer.METSummary
    @State private var showResearch = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with info button
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "flame.fill")
                            .foregroundStyle(summary.status.color)
                        Text("MET Activity")
                            .font(.headline)
                    }
                    
                    HStack(spacing: 6) {
                        Text(summary.status.emoji)
                        Text(summary.status.label)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(summary.status.color)
                        
                        Text(summary.trend.emoji)
                            .font(.caption)
                    }
                }
                
                Spacer()
                
                Button(action: { showResearch.toggle() }) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(Color.accent)
                }
            }
            
            // Weekly MET-minutes display
            VStack(spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(String(format: "%.0f", summary.weeklyMETMinutes))
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundStyle(summary.status.color)
                    
                    Text("MET-min")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Text("Weekly Activity Level")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            
            // WHO Guidelines Reference
            VStack(alignment: .leading, spacing: 4) {
                Text("WHO Guideline: 600-1500 MET-min/week")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                // Visual guide bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Background bar
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.textTertiary.opacity(0.15))
                        
                        // WHO minimum marker
                        Rectangle()
                            .fill(Color.statusMonitoring.opacity(0.3))
                            .frame(width: geometry.size.width * (600 / 3000))

                        // WHO target marker
                        Rectangle()
                            .fill(Color.statusOptimal.opacity(0.3))
                            .frame(width: geometry.size.width * (1500 / 3000))
                        
                        // Current level
                        RoundedRectangle(cornerRadius: 4)
                            .fill(summary.status.color)
                            .frame(width: min(geometry.size.width, geometry.size.width * (summary.weeklyMETMinutes / 3000)))
                    }
                }
                .frame(height: 8)
            }
            
            // Intensity breakdown
            VStack(alignment: .leading, spacing: 8) {
                Text("Intensity Breakdown")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                IntensityRow(
                    label: "Vigorous",
                    minutes: summary.vigorousActivityMinutes,
                    total: summary.dailyAverageMETs * 7,
                    color: .statusWarning,
                    description: "≥6.0 METs (Running, cycling)"
                )

                IntensityRow(
                    label: "Moderate",
                    minutes: summary.moderateActivityMinutes,
                    total: summary.dailyAverageMETs * 7,
                    color: .statusMonitoring,
                    description: "3.0-5.9 METs (Brisk walking)"
                )

                IntensityRow(
                    label: "Light",
                    minutes: summary.lightActivityMinutes,
                    total: summary.dailyAverageMETs * 7,
                    color: .statusRest,
                    description: "<3.0 METs (Slow walking)"
                )
            }
            
            // Recommendation
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "lightbulb.fill")
                    .foregroundStyle(Color.statusMonitoring)
                    .font(.caption)

                Text(summary.recommendation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: .radiusSm)
                    .fill(Color.statusMonitoring.opacity(0.1))
            )
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: .radiusMd)
                .fill(Color(uiColor: .systemBackground))
                .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
        )
        .sheet(isPresented: $showResearch) {
            ResearchContextSheet(summary: summary)
        }
    }
}

// MARK: - Intensity Row

struct IntensityRow: View {
    let label: String
    let minutes: Double
    let total: Double
    let color: Color
    let description: String
    
    private var percentage: Double {
        guard total > 0 else { return 0 }
        return (minutes / total) * 100
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Text(String(format: "%.0f min", minutes))
                    .font(.caption)
                    .fontWeight(.semibold)
                
                Text("(\(String(format: "%.0f", percentage))%)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.textTertiary.opacity(0.15))
                    
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color)
                        .frame(width: geometry.size.width * (percentage / 100))
                }
            }
            .frame(height: 6)
            
            Text(description)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Research Context Sheet

struct ResearchContextSheet: View {
    let summary: METAnalyzer.METSummary
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Research insight
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "doc.text.magnifyingglass")
                                .font(.title2)
                                .foregroundStyle(Color.accent)

                            Text("Why METs Matter")
                                .font(.title2)
                                .fontWeight(.bold)
                        }

                        Text(summary.researchContext)
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.accent.opacity(0.1))
                    )
                    
                    // Why not VO2 max?
                    VStack(alignment: .leading, spacing: 12) {
                        Text("The VO2 Max Problem")
                            .font(.headline)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            BulletPoint(text: "Smartwatch VO2 max has 7-16% error rate")
                            BulletPoint(text: "Consistently underestimates in fit individuals")
                            BulletPoint(text: "99% of longevity research uses METs, not VO2 max")
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.statusWarning.opacity(0.1))
                    )
                    
                    // MET advantages
                    VStack(alignment: .leading, spacing: 12) {
                        Text("MET Advantages")
                            .font(.headline)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            BulletPoint(text: "Based on real-world activity data", color: .statusOptimal)
                            BulletPoint(text: "Validated across 750,000+ participants", color: .statusOptimal)
                            BulletPoint(text: "Each MET increase = 14-15% mortality reduction", color: .statusOptimal)
                            BulletPoint(text: "Free to calculate from existing data", color: .statusOptimal)
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.statusOptimal.opacity(0.1))
                    )
                    
                    // Guidelines
                    VStack(alignment: .leading, spacing: 12) {
                        Text("WHO Physical Activity Guidelines")
                            .font(.headline)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            GuidelineRow(level: "Minimum", value: "600 MET-min/week", color: .statusMonitoring)
                            GuidelineRow(level: "Target", value: "1,500 MET-min/week", color: .statusOptimal)
                            GuidelineRow(level: "Excellent", value: "3,000+ MET-min/week", color: .statusRest)
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.textTertiary.opacity(0.1))
                    )
                }
                .padding()
            }
            .navigationTitle("MET Research")
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
}

// MARK: - Helper Views

struct BulletPoint: View {
    let text: String
    var color: Color = .statusOptimal
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(color)
                .font(.caption)
            
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct GuidelineRow: View {
    let level: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            
            Text(level)
                .font(.subheadline)
                .fontWeight(.medium)
            
            Spacer()
            
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Previews

#Preview("Excellent Status") {
    METActivityCard(
        summary: METAnalyzer.METSummary(
            weeklyMETMinutes: 3200,
            dailyAverageMETs: 457,
            lightActivityMinutes: 0,
            moderateActivityMinutes: 400,
            vigorousActivityMinutes: 2800,
            trend: .improving,
            status: .excellent,
            recommendation: "Outstanding activity level! Maintain balance between intensity and recovery.",
            researchContext: "Based on 750,000+ participant studies: Each MET increase = 14-15% mortality reduction"
        )
    )
    .padding()
}

#Preview("Moderate Status") {
    METActivityCard(
        summary: METAnalyzer.METSummary(
            weeklyMETMinutes: 850,
            dailyAverageMETs: 121,
            lightActivityMinutes: 200,
            moderateActivityMinutes: 350,
            vigorousActivityMinutes: 300,
            trend: .stable,
            status: .moderate,
            recommendation: "Meeting minimum WHO guidelines. Consider adding 1-2 more vigorous sessions weekly.",
            researchContext: "Based on 750,000+ participant studies: Each MET increase = 14-15% mortality reduction"
        )
    )
    .padding()
}
