//
//  IllnessEvent.swift
//  HealthAnalytics
//
//  A sick spell the user logged by hand (Phase 2b). The HRV precursor pattern needs
//  illness onsets to look back from; the step-count proxy misses illness on days the
//  user still walks, and a logged onset is ground truth.
//

import Foundation
import SwiftData

@Model
final class IllnessEvent {
    /// Plain UUID, not `@Attribute(.unique)`, to keep schema changes lightweight.
    var id: UUID = UUID()
    /// Start of the first sick day.
    var startDate: Date = Date()
    /// Start of the last sick day; nil while the user is still sick.
    var endDate: Date?
    var createdAt: Date = Date()

    init(startDate: Date, endDate: Date? = nil, calendar: Calendar = .current) {
        self.id = UUID()
        self.startDate = calendar.startOfDay(for: startDate)
        self.endDate = endDate.map { calendar.startOfDay(for: $0) }
        self.createdAt = Date()
    }

    var isOngoing: Bool { endDate == nil }

    /// Spells with no last day yet. Shared by the Coach tab's Sick chip (CoachCheckInView) and its store test.
    static let ongoing = #Predicate<IllnessEvent> { $0.endDate == nil }
}

enum IllnessLog {
    /// After the log changes: the illness state is part of the Coach cache key, so this
    /// re-runs the paragraph now instead of at the next sync.
    @MainActor static func refreshCoach(_ modelContext: ModelContext) {
        Task { await ReadinessRepository.shared.refreshIfNecessary(modelContext: modelContext) }
    }

    /// The Coach tab's Sick chip: ends the open illness(es); otherwise reopens one whose last
    /// sick day was today or yesterday (a mis-tapped "I'm better", or the same illness back),
    /// otherwise starts one today. Reads the whole log (a handful of rows, no predicate). The
    /// caller refreshes Coach afterwards (`refreshCoach`).
    @MainActor static func toggleToday(in modelContext: ModelContext, now: Date = Date(), calendar: Calendar = .current) {
        let all = (try? modelContext.fetch(FetchDescriptor<IllnessEvent>())) ?? []
        let ongoing = all.filter(\.isOngoing)
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        if !ongoing.isEmpty {
            for event in ongoing { event.endDate = lastSickDay(start: event.startDate, betterOn: now) }
        } else if let recent = all.filter({ ($0.endDate ?? .distantPast) >= yesterday }).max(by: { $0.startDate < $1.startDate }) {
            recent.endDate = nil
        } else {
            modelContext.insert(IllnessEvent(startDate: now))
        }
        try? modelContext.save()
    }

    /// Feeling better today means yesterday was the last sick day, unless the illness only
    /// started today.
    static func lastSickDay(start: Date, betterOn now: Date, calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        return max(calendar.startOfDay(for: start), yesterday)
    }

    /// Onsets the HRV precursor looks back from: every logged illness that started inside
    /// `[from, to)`, plus each step-proxy window that isn't the same illness. Logged spells that
    /// overlap or touch (the next starts by the day after the last ends) are one illness. A
    /// proxy window is the same illness when it starts within a day before a logged illness and
    /// its end (the last sick day, or `to` while ongoing). Sorted, one per illness.
    static func sickWindowStarts(proxy: [Date], logged: [(start: Date, end: Date?)],
                                 from: Date, to: Date, calendar: Calendar = .current) -> [Date] {
        var spells: [(start: Date, end: Date)] = []
        for spell in logged
            .map({ (start: calendar.startOfDay(for: $0.start), end: $0.end.map { calendar.startOfDay(for: $0) } ?? to) })
            .filter({ $0.start >= from && $0.start < to })
            .sorted(by: { $0.start < $1.start }) {
            if let last = spells.last,
               spell.start <= (calendar.date(byAdding: .day, value: 1, to: last.end) ?? last.end) {
                spells[spells.count - 1].end = max(last.end, spell.end)
            } else {
                spells.append(spell)
            }
        }
        let unlogged = proxy.filter { day in
            !spells.contains { spell in
                let lead = calendar.date(byAdding: .day, value: -1, to: spell.start) ?? spell.start
                return day >= lead && day <= spell.end
            }
        }
        return (spells.map(\.start) + unlogged).sorted()
    }
}
