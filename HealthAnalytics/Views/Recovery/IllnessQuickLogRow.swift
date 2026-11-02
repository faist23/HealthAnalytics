//
//  IllnessQuickLogRow.swift
//  HealthAnalytics
//
//  One tap on the Recovery tab to log a sick day, and one to say you're better
//  (Phase 2b). Past illnesses are added and edited in Settings → Illness Log.
//

import SwiftUI
import SwiftData

struct IllnessQuickLogRow: View {
    @Query(filter: IllnessEvent.ongoing, sort: \IllnessEvent.startDate, order: .reverse)
    private var ongoing: [IllnessEvent]
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        HStack(spacing: .spacingSm) {
            Image(systemName: ongoing.isEmpty ? "cross.case" : "cross.case.fill")
                .foregroundStyle(ongoing.isEmpty ? Color.textSecondary : Color.statusWarning)
            VStack(alignment: .leading, spacing: 2) {
                Text(ongoing.isEmpty ? "Feeling sick?" : "Sick")
                    .font(.subheadline)
                    .foregroundStyle(Color.textPrimary)
                Text(ongoing.first.map { IllnessFormat.span(start: $0.startDate, end: nil) } ?? "Logging it helps spot early warnings in your HRV")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer()
            Button(ongoing.isEmpty ? "Log sick day" : "I'm better") {
                if ongoing.isEmpty {
                    modelContext.insert(IllnessEvent(startDate: Date()))
                } else {
                    let today = Calendar.current.startOfDay(for: Date())
                    // Better today means yesterday was the last sick day, unless it started today.
                    for event in ongoing {
                        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today) ?? today
                        event.endDate = max(event.startDate, yesterday)
                    }
                }
                try? modelContext.save()
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.accent)
        }
        .padding(.spacingMd)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: .radiusMd))
        .padding(.horizontal)
    }
}
