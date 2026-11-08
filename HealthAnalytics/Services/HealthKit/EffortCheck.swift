//
//  EffortCheck.swift
//  HealthAnalytics
//
//  Read-only check for the effort-score idea (TODOS: "the same workout feeling harder is a
//  stress signal"): do the rider's own rides carry an effort rating they gave? Only
//  `workoutEffortScore` is how a workout felt; `estimatedWorkoutEffortScore` is Apple's guess
//  from heart rate, so it never counts as rated.
//

import Foundation

/// A ride's Apple-written effort rating with the ride's own times, for matching to stored rides.
struct EffortRatingSample: Equatable, Sendable {
    let workoutStart: Date
    let workoutEnd: Date
    let rating: Double
}

/// One workout from Apple Health with its related effort samples.
struct EffortCheckWorkout: Equatable {
    let date: Date
    /// The app that wrote the workout (Strava, Workout, a bike computer's app).
    let source: String
    let isCycling: Bool
    let minutes: Int
    /// The newest `workoutEffortScore` related to the workout, 1-10. Nil when none. Any app can
    /// write one, so it is the rider's own only when `ratedBy` is Fitness or the Watch.
    let rated: Double?
    /// The app that wrote `rated`.
    let ratedBy: String?
    /// Apple's estimate, 1-10. Nil when none.
    let estimated: Double?
}

struct EffortCheckSummary: Equatable {
    struct Source: Equatable {
        let name: String
        let workouts: Int
        let rated: Int
        let estimated: Int
    }

    /// An app that wrote ratings, and how many.
    struct Writer: Equatable {
        let name: String
        let ratings: Int
    }

    enum Verdict: Equatable {
        case noRides
        case noRatedRides
        case someRidesRated(rated: Int, rides: Int)
        case allRidesRated(rides: Int)

        var text: String {
            switch self {
            case .noRides: return "No rides in this period."
            case .noRatedRides: return "None of your rides carry an effort rating, or Effort access is off."
            case .someRidesRated(let rated, let rides): return "\(rated) of your \(rides) rides carry an effort rating."
            case .allRidesRated(let rides): return "All \(rides) of your rides carry an effort rating."
            }
        }
    }

    let workouts: Int
    let rated: Int
    let estimated: Int
    let rides: Int
    let ridesRated: Int
    /// Most workouts first, then by name.
    let sources: [Source]
    /// Who wrote the ratings, most first. Only Fitness or the Watch means the rider rated it.
    let ratingWriters: [Writer]

    var verdict: Verdict {
        if rides == 0 { return .noRides }
        if ridesRated == 0 { return .noRatedRides }
        if ridesRated == rides { return .allRidesRated(rides: rides) }
        return .someRidesRated(rated: ridesRated, rides: rides)
    }

    static func summarize(_ workouts: [EffortCheckWorkout]) -> EffortCheckSummary {
        let sources = Dictionary(grouping: workouts, by: \.source).map { name, group in
            Source(name: name, workouts: group.count,
                   rated: group.filter { $0.rated != nil }.count,
                   estimated: group.filter { $0.estimated != nil }.count)
        }.sorted { ($0.workouts, $1.name) > ($1.workouts, $0.name) }
        let rides = workouts.filter(\.isCycling)
        return EffortCheckSummary(
            workouts: workouts.count,
            rated: workouts.filter { $0.rated != nil }.count,
            estimated: workouts.filter { $0.estimated != nil }.count,
            rides: rides.count,
            ridesRated: rides.filter { $0.rated != nil }.count,
            sources: sources,
            ratingWriters: Dictionary(grouping: workouts.compactMap(\.ratedBy), by: { $0 })
                .map { Writer(name: $0.key, ratings: $0.value.count) }
                .sorted { ($0.ratings, $1.name) > ($1.ratings, $0.name) }
        )
    }
}
