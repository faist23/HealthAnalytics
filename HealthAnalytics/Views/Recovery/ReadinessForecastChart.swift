//
//  ReadinessForecastChart.swift
//  HealthAnalytics
//
//  Phase 3 — 7-Day Readiness Forecast
//  Shows a linemark + confidence band for the next 7 days.
//  Data from ReadinessRepository.forecast (@Published, set at end of performFullAnalysis).
//

import SwiftUI

struct ReadinessForecastChart: View {
    @ObservedObject private var repo = ReadinessRepository.shared

    private var days: [ReadinessRepository.ReadinessForecastDay] {
        repo.forecast ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: .spacingSm) {
            headerRow
            if days.isEmpty {
                emptyState
            } else {
                coachingRow
            }
        }
        .padding(.spacingMd)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: .radiusMd))
        .overlay(
            RoundedRectangle(cornerRadius: .radiusMd)
                .stroke(Color.accentBorder, lineWidth: 1)
        )
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: .spacingSm) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 18))
                .foregroundStyle(Color.accent)
            Text("7-Day Forecast")
                .font(.cardTitle)
                .foregroundStyle(Color.textPrimary)
            Spacer()
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        Text("Forecast available after 14 days of syncing")
            .font(.coachGuidance)
            .foregroundStyle(Color.textSecondary)
            .padding(.vertical, .spacingSm)
    }

    // MARK: - Coaching Labels

    private var coachingRow: some View {
        HStack(spacing: 0) {
            ForEach(days) { day in
                VStack(spacing: 2) {
                    Text(dayAbbrev(day.date))
                        .font(.dataAxis)
                        .foregroundStyle(Color.textTertiary)
                    Text(coachingAbbrev(day.coaching))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(coachingColor(day.coaching))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, .spacingXs)
    }

    // MARK: - Helpers

    private func dayAbbrev(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated))
    }

    private func coachingAbbrev(_ coaching: String) -> String {
        switch coaching {
        case "Hard effort OK":    return "Hard"
        case "Moderate training": return "Mod"
        case "Easy only":         return "Easy"
        default:                  return "Rest"
        }
    }

    private func coachingColor(_ coaching: String) -> Color {
        switch coaching {
        case "Hard effort OK":    return Color.statusOptimal
        case "Moderate training": return Color.accent
        case "Easy only":         return Color.statusMonitoring
        default:                  return Color.statusRest
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    ScrollView {
        ReadinessForecastChart()
            .padding()
    }
    .background(Color.background)
}
#endif
