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

    /// Spells with no last day yet. Shared by the Recovery tab's quick log and its store test.
    static let ongoing = #Predicate<IllnessEvent> { $0.endDate == nil }
}

enum IllnessLog {
    /// Onsets the HRV precursor looks back from: every logged illness that started inside
    /// `[from, to)`, plus each step-proxy window that isn't the same illness. A proxy window
    /// is the same illness when it starts within a day before a logged illness and its end
    /// (the last sick day, or `to` while ongoing). Sorted, one per illness.
    static func sickWindowStarts(proxy: [Date], logged: [(start: Date, end: Date?)],
                                 from: Date, to: Date, calendar: Calendar = .current) -> [Date] {
        let spells = logged
            .map { (start: calendar.startOfDay(for: $0.start), end: $0.end.map { calendar.startOfDay(for: $0) } ?? to) }
            .filter { $0.start >= from && $0.start < to }
        let unlogged = proxy.filter { day in
            !spells.contains { spell in
                let lead = calendar.date(byAdding: .day, value: -1, to: spell.start) ?? spell.start
                return day >= lead && day <= spell.end
            }
        }
        return (spells.map(\.start) + unlogged).sorted()
    }
}
