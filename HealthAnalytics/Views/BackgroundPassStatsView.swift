//
//  BackgroundPassStatsView.swift
//  HealthAnalytics
//
//  Debug counters for the background pattern pass: how often HealthKit delivery and
//  app refresh wake the app, how each pass ends, and the latest alert latency.
//

import SwiftUI

struct BackgroundPassStatsView: View {
    private let log = BackgroundPassLog.standard

    var body: some View {
        List {
            Section("Wakes") {
                ForEach(BackgroundPassWake.allCases, id: \.self) { wake in
                    // Not-active wakes are the delivery evidence; wakes while the app is
                    // open (iOS fires each observer once at registration) count apart.
                    LabeledContent(
                        wake.rawValue,
                        value: "\(log.count(wake)) (+\(log.count(wake, whileActive: true)) while open)"
                    )
                }
            }
            Section("Outcomes") {
                ForEach(BackgroundPassOutcome.allCases, id: \.self) { outcome in
                    LabeledContent(outcome.rawValue, value: "\(log.count(outcome))")
                }
            }
            Section("Last pass") {
                LabeledContent("Outcome", value: log.lastOutcome?.rawValue ?? "none")
                LabeledContent("At", value: log.lastOutcomeAt?.formatted(date: .abbreviated, time: .shortened) ?? "never")
                LabeledContent("HRV → commit", value: log.lastLatency.map { "\(Int($0 / 60)) min" } ?? "n/a")
            }
        }
        .foregroundStyle(Color.textPrimary)
        .navigationTitle("Background Pass")
    }
}
