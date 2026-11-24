//
//  TrainingWeek.swift
//  HealthAnalytics
//
//  The rider's training week. The phone's locale picks the first day of a calendar week
//  (Sunday in the US), but most athletes and training platforms start the week on Monday,
//  so weekly totals follow the rider's setting instead.
//

import Foundation

nonisolated enum TrainingWeek {
    /// `Calendar.firstWeekday` value: 1 = Sunday, 2 = Monday.
    static let startDayKey = "trainingWeekStartDay"
    static let sunday = 1
    static let monday = 2
    /// Monday unless the rider picks Sunday.
    static let defaultStartDay = monday

    /// The stored setting; anything other than Sunday or Monday reads as the default.
    static var startDay: Int { validated(UserDefaults.standard.integer(forKey: startDayKey)) }

    static func validated(_ day: Int) -> Int {
        day == sunday || day == monday ? day : defaultStartDay
    }

    /// A calendar whose weeks start on `startDay`, with everything else from `base`.
    static func calendar(startDay: Int = startDay, base: Calendar = .current) -> Calendar {
        var calendar = base
        calendar.firstWeekday = validated(startDay)
        return calendar
    }

    /// Midnight at the start of the training week holding `date`.
    static func weekStart(of date: Date, calendar: Calendar) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }
}
