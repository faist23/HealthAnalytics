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
                    Text("An estimate from stored daily scores. It replays recovery and how rides felt only: load, pattern and note limits aren't included, and stored scores already count that day's ride.")
                }
                Section {
                    Text(Self.feelSummary(result.feel))
                    if result.feel.changedDays > 0 {
                        LabeledContent("Same or one step off without it",
                                       value: percent(result.feel.withinOneWithout, of: result.daysChecked))
                        LabeledContent("Same level without it", value: percent(result.feel.exactWithout, of: result.daysChecked))
                    }
                } header: {
                    Text("How rides feel")
                } footer: {
                    Text("Each day uses only ratings given before it.")
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

    /// Whether how rides feel moved tomorrow's suggestion toward the real morning.
    static func feelSummary(_ feel: ForecastCheckResult.FeelEffect) -> String {
        guard feel.changedDays > 0 else { return "How rides feel hasn't changed a suggestion yet." }
        let days = feel.changedDays == 1 ? "1 day" : "\(feel.changedDays) days"
        return "Changed tomorrow's suggestion on \(days): closer to the real morning on \(feel.closer), further on \(feel.further), no different on \(feel.same)."
    }

    private func percent(_ part: Int, of whole: Int) -> String {
        "\(Int((Double(part) / Double(whole) * 100).rounded()))%"
    }
}
