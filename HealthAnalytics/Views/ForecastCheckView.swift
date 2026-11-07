//
//  ForecastCheckView.swift
//  HealthAnalytics
//
//  Debug screen: how the 7-day plan's "tomorrow" would have done on the last 60 days.
//  Replayed from stored data, so it can be judged on the rider's own history.
//

import SwiftUI
import SwiftData

struct ForecastCheckView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var result: ForecastCheckResult?
    @State private var hasLoaded = false

    var body: some View {
        List {
            if let result, result.daysChecked > 0 {
                Section {
                    LabeledContent("Same or one step off", value: percent(result.withinOne, of: result.daysChecked))
                    LabeledContent("Same level", value: percent(result.exact, of: result.daysChecked))
                    LabeledContent("Days checked", value: "\(result.daysChecked)")
                } header: {
                    Text("Tomorrow's suggestion vs. the real morning")
                } footer: {
                    Text("An estimate from stored daily scores. It replays recovery only: load, pattern and note limits aren't included, and stored scores already count that day's ride.")
                }
                Section("What it has learned") {
                    LabeledContent("Recovery time", value: result.recoveryDays == 1 ? "1 day" : "\(result.recoveryDays) days")
                    LabeledContent("Hard days measured", value: "\(result.episodeCount)")
                }
                if !result.recentMisses.isEmpty {
                    Section("Recent misses") {
                        ForEach(result.recentMisses, id: \.date) { miss in
                            LabeledContent(miss.date.formatted(date: .abbreviated, time: .omitted),
                                           value: "Said \(miss.suggested.word), was \(miss.actual.word)")
                        }
                    }
                }
            } else if hasLoaded {
                Text(result == nil ? "Couldn't read your history." : "Needs about 15 days of recovery scores.")
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .foregroundStyle(Color.textPrimary)
        .navigationTitle("Forecast Check")
        .task {
            result = ReadinessRepository.shared.forecastCheck(modelContext: modelContext)
            hasLoaded = true
        }
    }

    private func percent(_ part: Int, of whole: Int) -> String {
        "\(Int((Double(part) / Double(whole) * 100).rounded()))%"
    }
}
