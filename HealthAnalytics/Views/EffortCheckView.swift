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
    @State private var rideCost: RideCostSummary?
    @State private var workouts: [EffortCheckWorkout] = []
    @State private var errorMessage: String?
    @State private var hasLoaded = false

    var body: some View {
        List {
            if let errorMessage {
                Text("Couldn't read Apple Health: \(errorMessage)")
                    .foregroundStyle(Color.textSecondary)
            } else if hasLoaded {
                if let rideCost {
                    Section {
                        Text(Self.trendText(rideCost.trend))
                        ForEach(Array(rideCost.rows.enumerated()), id: \.offset) { _, row in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(row.ride.date.formatted(date: .abbreviated, time: .omitted)) · \(row.ride.title ?? "Ride")")
                                Text(Self.rowText(row))
                                    .font(.labelCaption)
                                    .foregroundStyle(Color.textSecondary)
                            }
                        }
                        ForEach(UnpricedReason.allCases.filter { rideCost.unpriced[$0] != nil }, id: \.self) { reason in
                            LabeledContent("Not priced: \(reason.text)", value: "\(rideCost.unpriced[reason] ?? 0)")
                        }
                    } header: {
                        Text("Ride cost")
                    } footer: {
                        Text("Usual is your median for rides in the same setting (indoor or outdoor) at the same intensity and a similar length, in the 90 days before. Intensity is normalized power ÷ your FTP that day. The plan uses the 14-day trend, with recent rides counting most.")
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
            rideCost = ReadinessRepository.shared.rideCostSummary(modelContext: modelContext)
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
        if abs(trend) < 0.05 { return "Rides are costing about what they usually do." }
        let points = String(format: "%.1f", abs(trend))
        return trend > 0 ? "Rides are costing about \(points) points more than usual." : "Rides are costing about \(points) points less than usual."
    }

    /// "indoor · IF 0.70 · HR 152 (usual 140, +12) · rated 8 (usual 5)".
    static func rowText(_ row: RideCostSummary.Row) -> String {
        let ride = row.ride, price = row.price
        var parts = [ride.isIndoor ? "indoor" : "outdoor", String(format: "IF %.2f", ride.intensity)]
        let hr = Int(ride.heartRate.rounded())
        if let normal = price.normalHeartRate {
            let difference = hr - Int(normal.rounded())
            parts.append("HR \(hr) (usual \(Int(normal.rounded())), \(difference >= 0 ? "+" : "")\(difference))")
        } else {
            parts.append("HR \(hr) (not judged)")
        }
        if let rating = ride.rating {
            let rated = "rated \(Int(rating.rounded()))"
            parts.append(price.normalRating.map { "\(rated) (usual \(String(format: "%g", $0)))" } ?? "\(rated) (not judged)")
        }
        return parts.joined(separator: " · ")
    }

    private func score(_ value: Double?) -> String {
        value.map { String(Int($0.rounded())) } ?? "none"
    }
}
