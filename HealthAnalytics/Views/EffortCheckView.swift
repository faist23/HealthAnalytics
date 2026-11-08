//
//  EffortCheckView.swift
//  HealthAnalytics
//
//  Debug screen: do your recent workouts carry an effort rating you gave, or only Apple's
//  estimate? Answers whether "the same workout felt harder" can be read from your own data.
//

import SwiftUI
import SwiftData

struct EffortCheckView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var absorption: AbsorptionSummary?
    @State private var workouts: [EffortCheckWorkout] = []
    @State private var errorMessage: String?
    @State private var hasLoaded = false

    var body: some View {
        List {
            if let errorMessage {
                Text("Couldn't read Apple Health: \(errorMessage)")
                    .foregroundStyle(Color.textSecondary)
            } else if hasLoaded {
                if let absorption {
                    Section {
                        Text(Self.trendText(absorption.trend))
                        ForEach(Array(absorption.rides.enumerated()), id: \.offset) { _, ride in
                            LabeledContent(ride.date.formatted(date: .abbreviated, time: .omitted),
                                           value: "rated \(Int(ride.rating.rounded())) · usual \(ride.expected.map { String(format: "%.1f", $0) } ?? "–") · \(Self.differenceText(ride.difference))")
                        }
                    } header: {
                        Text("How rides feel")
                    } footer: {
                        Text("Usual is your median rating for rides of similar length and load. The plan uses the 14-day trend, with recent rides counting most.")
                    }
                }
                let summary = EffortCheckSummary.summarize(workouts)
                Section {
                    Text(summary.verdict.text)
                    LabeledContent("Workouts", value: "\(summary.workouts)")
                    LabeledContent("Rated", value: "\(summary.rated)")
                    LabeledContent("Apple's estimate", value: "\(summary.estimated)")
                } header: {
                    Text("Last 60 days")
                } footer: {
                    Text("A rating is yours when Fitness or Apple Watch wrote it; other apps can write their own. Apple's estimate comes from heart rate, so it isn't how the workout felt. If Effort access wasn't allowed, everything reads as not rated.")
                }
                if !summary.ratingWriters.isEmpty {
                    Section("Ratings written by") {
                        ForEach(summary.ratingWriters, id: \.name) { writer in
                            LabeledContent(writer.name, value: "\(writer.ratings)")
                        }
                    }
                }
                if !summary.sources.isEmpty {
                    Section("By app") {
                        ForEach(summary.sources, id: \.name) { source in
                            LabeledContent(source.name, value: "\(source.workouts) · rated \(source.rated) · estimate \(source.estimated)")
                        }
                    }
                }
                if !workouts.isEmpty {
                    Section("Workouts") {
                        ForEach(Array(workouts.enumerated()), id: \.offset) { _, workout in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(workout.date.formatted(date: .abbreviated, time: .omitted)) · \(workout.isCycling ? "Ride" : "Workout") · \(workout.minutes) min")
                                Text("\(workout.source) · rating: \(score(workout.rated))\(workout.ratedBy.map { " (\($0))" } ?? "") · Apple: \(score(workout.estimated))")
                                    .font(.labelCaption)
                                    .foregroundStyle(Color.textSecondary)
                            }
                        }
                    }
                }
            } else {
                ProgressView()
            }
        }
        .foregroundStyle(Color.textPrimary)
        .navigationTitle("Effort Check")
        .task {
            errorMessage = nil
            absorption = ReadinessRepository.shared.absorptionSummary(modelContext: modelContext)
            do {
                workouts = try await HealthKitManager.shared.fetchEffortCheckWorkouts()
            } catch {
                errorMessage = error.localizedDescription
            }
            hasLoaded = true
        }
    }

    static func trendText(_ trend: Double) -> String {
        // Any trend the plan acts on is named; only a rounding-level one reads as usual.
        if abs(trend) < 0.05 { return "Rides are feeling about as usual." }
        let points = String(format: "%.1f", abs(trend))
        return trend > 0 ? "Rides are feeling about \(points) points harder than usual." : "Rides are feeling about \(points) points easier than usual."
    }

    static func differenceText(_ difference: Double?) -> String {
        guard let difference else { return "not judged" }
        if difference == 0 { return "as usual" }
        return difference > 0 ? String(format: "+%.1f", difference) : String(format: "%.1f", difference)
    }

    private func score(_ value: Double?) -> String {
        value.map { String(Int($0.rounded())) } ?? "none"
    }
}
