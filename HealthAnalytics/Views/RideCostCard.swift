//
//  RideCostCard.swift
//  HealthAnalytics
//
//  Coach tab: a recent ride that cost more than its intensity should have. It describes the
//  ride and never guesses a cause. Spec: docs/superpowers/specs/2026-11-09-ride-cost-design.md
//

import SwiftUI

struct RideCostCard: View {
    let flag: RideCostFlag
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "heart.text.square")
                    .foregroundStyle(Color.statusWarning)
                Text("Ride cost more than usual")
                    .font(.headline)
            }
            Text(Self.subtitle(flag))
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
            ForEach(flag.lines, id: \.self) { line in
                Text(line)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Color.textPrimary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ? Color.surface : Color.white)
                .shadow(color: .black.opacity(0.05), radius: 10, y: 5)
        )
        .accessibilityElement(children: .combine)
    }

    /// "Today · Lunch Ride", "Yesterday · Ride", or the weekday.
    static func subtitle(_ flag: RideCostFlag, now: Date = Date(), calendar: Calendar = .current) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: flag.date),
                                           to: calendar.startOfDay(for: now)).day ?? 0
        let day: String
        switch days {
        case 0: day = "Today"
        case 1: day = "Yesterday"
        default: day = calendar.weekdaySymbols[calendar.component(.weekday, from: flag.date) - 1]
        }
        return "\(day) · \(flag.title ?? "Ride")"
    }
}
