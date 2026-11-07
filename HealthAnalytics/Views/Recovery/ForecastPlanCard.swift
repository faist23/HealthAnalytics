//
//  ForecastPlanCard.swift
//  HealthAnalytics
//
//  The 7-day plan: Today plus six days, each a light, one word and, when the day isn't
//  obvious, one short reason. Data from ReadinessRepository.forecast. No score, no chart.
//

import SwiftUI

extension ReadinessRepository.ForecastEffort {
    /// The one word the card shows. `label` is the longer text the Coach reads.
    var word: String {
        switch self {
        case .rest: return "Rest"
        case .easy: return "Easy"
        case .moderate: return "Moderate"
        case .hard: return "Hard"
        }
    }

    var light: Color {
        switch self {
        case .rest: return Color.statusWarning
        case .easy: return Color.statusMonitoring
        case .moderate, .hard: return Color.statusOptimal
        }
    }
}

struct ForecastPlanCard: View {
    @ObservedObject private var repo = ReadinessRepository.shared

    var body: some View {
        ForecastPlanCardContent(days: repo.forecast ?? [])
    }

    /// "Today" only when it really is: the app can be left open past midnight.
    static func rowTitle(for date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        calendar.isDate(date, inSameDayAs: now) ? "Today" : date.formatted(.dateTime.weekday(.wide))
    }

    /// The color isn't the only signal, so VoiceOver reads the row as one sentence.
    static func accessibilityLabel(for day: ReadinessRepository.ReadinessForecastDay, now: Date = Date(),
                                   calendar: Calendar = .current) -> String {
        [rowTitle(for: day.date, now: now, calendar: calendar), day.effort.word, day.reason]
            .compactMap { $0 }
            .joined(separator: ", ")
    }
}

/// The card itself, separate from the repository so a preview can hand it fixture days.
struct ForecastPlanCardContent: View {
    let days: [ReadinessRepository.ReadinessForecastDay]

    /// Fits "Wednesday" in the coach font, so the lights line up down the card.
    private static let dayColumnWidth: CGFloat = 88

    var body: some View {
        VStack(alignment: .leading, spacing: .spacingSm) {
            headerRow
            if days.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    ForEach(days) { day in
                        row(day)
                        if day.id != days.last?.id {
                            Divider().overlay(Color.surfaceRaised)
                        }
                    }
                }
            }
        }
        .padding(.spacingMd)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: .radiusMd))
        .overlay(
            RoundedRectangle(cornerRadius: .radiusMd)
                .stroke(Color.accentBorder, lineWidth: 1)
        )
    }

    private var headerRow: some View {
        HStack(spacing: .spacingSm) {
            Image(systemName: "calendar")
                .font(.system(size: 18))
                .foregroundStyle(Color.accent)
            Text("7-Day Forecast")
                .font(.cardTitle)
                .foregroundStyle(Color.textPrimary)
            Spacer()
        }
    }

    private var emptyState: some View {
        Text("Forecast available after 14 days of syncing")
            .font(.coachGuidance)
            .foregroundStyle(Color.textSecondary)
            .padding(.vertical, .spacingSm)
    }

    private func row(_ day: ReadinessRepository.ReadinessForecastDay) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: .spacingSm) {
            Text(ForecastPlanCard.rowTitle(for: day.date))
                .font(.coachGuidance)
                .foregroundStyle(Color.textSecondary)
                .frame(width: Self.dayColumnWidth, alignment: .leading)
            Circle()
                .fill(day.effort.light)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(day.effort.word)
                    .font(.coachGuidance.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                if let reason = day.reason {
                    Text(reason)
                        .font(.labelCaption)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, .spacingSm)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ForecastPlanCard.accessibilityLabel(for: day))
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    let start = Calendar.current.startOfDay(for: Date())
    let week: [(ReadinessRepository.ForecastEffort, String?)] = [
        (.rest, "Rode hard today"), (.easy, "Still recovering from Saturday"), (.moderate, "Bouncing back after rest"),
        (.hard, nil), (.moderate, "Load ramping fast"), (.hard, nil), (.easy, nil)
    ]
    let days = week.enumerated().map { offset, entry in
        ReadinessRepository.ReadinessForecastDay(
            date: Calendar.current.date(byAdding: .day, value: offset, to: start)!,
            effort: entry.0,
            reason: entry.1
        )
    }
    return ScrollView {
        ForecastPlanCardContent(days: days)
            .padding()
    }
    .background(Color.background)
}
#endif
