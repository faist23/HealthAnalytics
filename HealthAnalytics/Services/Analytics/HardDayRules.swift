//
//  HardDayRules.swift
//  HealthAnalytics
//
//  Where every rider's 7-day plan starts on hard days, set by age: how many in any 7, and how
//  many days pass before the next. An older body absorbs less stress in a short time (men of
//  about 62 needed 5 days to recover peak power from one interval session, men of about 22
//  needed 3). The evidence compares riders in their 20s with riders around 55-62 and can't place
//  the change more finely than one line.
//  Spec: docs/superpowers/specs/2026-11-10-hard-days-cap-design.md (Part 1). Part 2 lets the
//  rider's own response move these numbers.
//

import Foundation

nonisolated struct HardDayRules: Equatable {
    /// The most Hard days, ridden or planned, in any 7.
    let hardDaysPerWeek: Int
    /// Days after a hard day that stay below Hard. A longer learned recovery time wins.
    let minimumRecoveryDays: Int

    static let seniorAge = 60
    /// Outside this an age from Apple Health is a placeholder or a typo, not an age.
    static let plausibleAges = 10...110
    static let under60 = HardDayRules(hardDaysPerWeek: 3, minimumRecoveryDays: 1)
    static let from60 = HardDayRules(hardDaysPerWeek: 2, minimumRecoveryDays: 2)
    static let lastKnownAgeKey = "forecastLastKnownAge"

    /// An unknown age gets the under-60 rules.
    static func forAge(_ age: Int?) -> HardDayRules {
        guard let age, age >= seniorAge else { return under60 }
        return from60
    }

    /// The age to plan with. A plausible read is remembered, so a later failed read (a locked
    /// device, Health unavailable) can't loosen the rules already in use. Nil only when no
    /// plausible age has ever been read.
    static func resolvedAge(read: Int?, defaults: UserDefaults) -> Int? {
        if let read, plausibleAges.contains(read) {
            defaults.set(read, forKey: lastKnownAgeKey)
            return read
        }
        return defaults.object(forKey: lastKnownAgeKey) as? Int
    }
}
