//
//  BalancedTrainingCard.swift
//  HealthAnalytics
//
//  Training balance visualization - endurance vs strength
//  Research-backed approach: Momma 2022 (BJSM) — doing both aerobic and strength work is
//  associated with lower all-cause mortality than doing neither (not "than either alone").
//

import SwiftUI
import Charts

struct BalancedTrainingCard: View {
    let balance: BalancedTrainingAnalyzer.TrainingBalance
    @State private var showRecommendations = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: .spacingMd) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: .spacingXs) {
                    HStack {
                        Text(balance.balance.emoji)
                            .font(.title3)
                        Text("Training Balance")
                            .font(.headline)
                    }
                    
                    HStack(spacing: 6) {
                        Text(balance.balance.label)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(balance.balance.color)
                        
                        Text(balance.trend.emoji)
                            .font(.caption)
                    }
                }
                
                Spacer()
                
                Button(action: { showRecommendations.toggle() }) {
                    Image(systemName: "lightbulb.fill")
                        .foregroundStyle(Color.statusMonitoring)
                }
            }
            
            // Donut chart showing balance
            HStack(spacing: 20) {
                // Chart
                ZStack {
                    // Background circle
                    Circle()
                        .stroke(Color.textTertiary.opacity(0.2), lineWidth: 20)
                        .frame(width: 120, height: 120)

                    // Endurance segment
                    Circle()
                        .trim(from: 0, to: balance.endurancePercentage / 100)
                        .stroke(Color.statusRest, style: StrokeStyle(lineWidth: 20, lineCap: .round))
                        .frame(width: 120, height: 120)
                        .rotationEffect(.degrees(-90))

                    // Strength segment
                    Circle()
                        .trim(from: 0, to: balance.strengthPercentage / 100)
                        .stroke(Color.statusWarning, style: StrokeStyle(lineWidth: 20, lineCap: .round))
                        .frame(width: 120, height: 120)
                        .rotationEffect(.degrees(-90 + (balance.endurancePercentage * 3.6)))

                    // Mobility segment (if present)
                    if balance.mobilityPercentage > 0 {
                        Circle()
                            .trim(from: 0, to: balance.mobilityPercentage / 100)
                            .stroke(Color.accent, style: StrokeStyle(lineWidth: 20, lineCap: .round))
                            .frame(width: 120, height: 120)
                            .rotationEffect(.degrees(-90 + ((balance.endurancePercentage + balance.strengthPercentage) * 3.6)))
                    }
                    
                    // Center text
                    VStack(spacing: 2) {
                        Text(String(format: "%.0f", balance.totalMinutes))
                            .font(.title2)
                            .fontWeight(.bold)
                        Text("min")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                // Legend
                VStack(alignment: .leading, spacing: 12) {
                    BalanceLegendItem(
                        color: .statusRest,
                        label: "Endurance",
                        minutes: balance.enduranceMinutes,
                        percentage: balance.endurancePercentage
                    )
                    
                    BalanceLegendItem(
                        color: .statusWarning,
                        label: "Strength",
                        minutes: balance.strengthMinutes,
                        percentage: balance.strengthPercentage
                    )
                    
                    if balance.mobilityMinutes > 0 {
                        BalanceLegendItem(
                            color: .accent,
                            label: "Mobility",
                            minutes: balance.mobilityMinutes,
                            percentage: balance.mobilityPercentage
                        )
                    }
                }
            }
            
            // Activity breakdown
            if !balance.activityBreakdown.topActivities.isEmpty {
                VStack(alignment: .leading, spacing: .spacingSm) {
                    Text("Top Activities (Last 14 Days)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    ForEach(balance.activityBreakdown.topActivities.prefix(3), id: \.name) { activity in
                        HStack {
                            Text(activity.name)
                                .font(.caption)
                            Spacer()
                            Text(String(format: "%.0f min", activity.minutes))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, .spacingSm)
            }
            
            // Recommendation
            HStack(alignment: .top, spacing: .spacingSm) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(Color.accent)
                    .font(.caption)
                
                Text(balance.recommendation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, .spacingSm)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: .radiusSm)
                    .fill(Color.statusRest.opacity(0.1))
            )

            // Research insight
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "book.fill")
                    .foregroundStyle(Color.statusOptimal)
                    .font(.caption2)
                
                Text(balance.researchInsight)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: .radiusMd)
                .fill(Color(uiColor: .systemBackground))
                .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
        )
        .sheet(isPresented: $showRecommendations) {
            RecommendedSplitSheet(balance: balance)
        }
    }
}

// MARK: - Balance Legend Item

struct BalanceLegendItem: View {
    let color: Color
    let label: String
    let minutes: Double
    let percentage: Double
    
    var body: some View {
        HStack(spacing: .spacingSm) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .fontWeight(.medium)
                
                HStack(spacing: .spacingXs) {
                    Text(String(format: "%.0f min", minutes))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    
                    Text("(\(String(format: "%.0f", percentage))%)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Recommended Split Sheet

struct RecommendedSplitSheet: View {
    let balance: BalancedTrainingAnalyzer.TrainingBalance
    @Environment(\.dismiss) var dismiss
    
    private var recommendedSplit: (endurance: String, strength: String, mobility: String) {
        BalancedTrainingAnalyzer().getRecommendedSplit(currentBalance: balance)
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: .spacingLg) {
                    // Current status
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "chart.pie.fill")
                                .font(.title2)
                                .foregroundStyle(balance.balance.color)
                            
                            Text("Current Balance")
                                .font(.title2)
                                .fontWeight(.bold)
                        }
                        
                        Text(balance.balance.label)
                            .font(.headline)
                            .foregroundStyle(balance.balance.color)
                        
                        Text(balance.recommendation)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(balance.balance.color.opacity(0.1))
                    )
                    
                    // Recommended split
                    VStack(alignment: .leading, spacing: .spacingMd) {
                        Text("Recommended Weekly Split")
                            .font(.headline)
                        
                        TrainingRecommendationRow(
                            icon: "figure.outdoor.cycle",
                            color: .statusRest,
                            category: "Endurance",
                            recommendation: recommendedSplit.endurance,
                            examples: "Cycling, running, swimming"
                        )
                        
                        TrainingRecommendationRow(
                            icon: "dumbbell.fill",
                            color: .statusWarning,
                            category: "Strength",
                            recommendation: recommendedSplit.strength,
                            examples: "Weight training, functional strength"
                        )
                        
                        TrainingRecommendationRow(
                            icon: "figure.yoga",
                            color: .accent,
                            category: "Mobility",
                            recommendation: recommendedSplit.mobility,
                            examples: "Yoga, stretching, foam rolling"
                        )
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.textTertiary.opacity(0.1))
                    )
                    
                    // Research context
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "doc.text.fill")
                                .font(.title2)
                                .foregroundStyle(Color.statusOptimal)
                            
                            Text("Why Balance Matters")
                                .font(.title2)
                                .fontWeight(.bold)
                        }
                        
                        VStack(alignment: .leading, spacing: 12) {
                            InsightBullet(
                                text: "Doing both aerobic AND muscle-strengthening work is linked to lower all-cause mortality than doing neither"
                            )
                            
                            InsightBullet(
                                text: "Cyclists often neglect strength work, limiting long-term performance and injury resilience"
                            )
                            
                            InsightBullet(
                                text: "Even 2 weekly strength sessions (30-45 min) provide significant health benefits"
                            )
                            
                            InsightBullet(
                                text: "Balanced training supports sustainable progression and reduces overuse injury risk"
                            )
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.statusOptimal.opacity(0.1))
                    )
                    
                    // Sample week
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Sample Balanced Week")
                            .font(.headline)
                        
                        VStack(alignment: .leading, spacing: .spacingSm) {
                            SampleDayRow(day: "Mon", activity: "Endurance ride", duration: "60-90 min")
                            SampleDayRow(day: "Tue", activity: "Strength training", duration: "45 min")
                            SampleDayRow(day: "Wed", activity: "Quality intervals", duration: "60 min")
                            SampleDayRow(day: "Thu", activity: "Easy recovery + mobility", duration: "30-45 min")
                            SampleDayRow(day: "Fri", activity: "Strength training", duration: "45 min")
                            SampleDayRow(day: "Sat", activity: "Long endurance ride", duration: "90-120 min")
                            SampleDayRow(day: "Sun", activity: "Active recovery or rest", duration: "Optional")
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.statusRest.opacity(0.1))
                    )
                }
                .padding()
            }
            .navigationTitle("Training Balance Guide")
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

struct TrainingRecommendationRow: View {
    let icon: String
    let color: Color
    let category: String
    let recommendation: String
    let examples: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: .spacingXs) {
                Text(category)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Text(recommendation)
                    .font(.body)
                    .foregroundStyle(color)
                
                Text(examples)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct InsightBullet: View {
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: .spacingSm) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.statusOptimal)
                .font(.caption)

            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct SampleDayRow: View {
    let day: String
    let activity: String
    let duration: String
    
    var body: some View {
        HStack {
            Text(day)
                .font(.caption)
                .fontWeight(.semibold)
                .frame(width: 35, alignment: .leading)
            
            Text(activity)
                .font(.caption)
            
            Spacer()
            
            Text(duration)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Previews

#Preview("Well-Balanced") {
    BalancedTrainingCard(
        balance: BalancedTrainingAnalyzer.TrainingBalance(
            enduranceMinutes: 420,
            strengthMinutes: 120,
            mobilityMinutes: 60,
            totalMinutes: 600,
            endurancePercentage: 70,
            strengthPercentage: 20,
            mobilityPercentage: 10,
            balance: .optimal,
            trend: .stable,
            recommendation: "Excellent endurance-strength balance. Consider adding 1-2 weekly mobility sessions.",
            researchInsight: "People who do both aerobic and muscle-strengthening work have lower all-cause mortality than people who do neither.",
            activityBreakdown: BalancedTrainingAnalyzer.ActivityBreakdown(
                cycling: 350,
                running: 70,
                swimming: 0,
                strengthTraining: 120,
                coreWork: 0,
                yoga: 60,
                other: 0
            )
        )
    )
    .padding()
}

#Preview("Endurance-Dominant") {
    BalancedTrainingCard(
        balance: BalancedTrainingAnalyzer.TrainingBalance(
            enduranceMinutes: 540,
            strengthMinutes: 0,
            mobilityMinutes: 0,
            totalMinutes: 540,
            endurancePercentage: 100,
            strengthPercentage: 0,
            mobilityPercentage: 0,
            balance: .missingStrength,
            trend: .unbalancing,
            recommendation: "No strength training in 18 days. Schedule 2-3 sessions this week to maintain muscle mass.",
            researchInsight: "People who do both aerobic and muscle-strengthening work have lower all-cause mortality than people who do neither.",
            activityBreakdown: BalancedTrainingAnalyzer.ActivityBreakdown(
                cycling: 480,
                running: 60,
                swimming: 0,
                strengthTraining: 0,
                coreWork: 0,
                yoga: 0,
                other: 0
            )
        )
    )
    .padding()
}
