//
//  TrainingDNAAnalyzer.swift
//  HealthAnalytics
//
//  Phase 2 — Pattern Engine
//  @ModelActor background service. Detects block crash cycle, HRV precursor,
//  and sleep fragmentation patterns from 180 days of HealthKit history.
//
//  Architecture: owned by ReadinessRepository as `private let trainingDNAAnalyzer`.
//  Never communicates with ViewModels directly.
//

import Foundation
import SwiftData
import HealthKit

// MARK: - HRV Source Preference

enum HRVSourcePreference: String, CaseIterable {
    case auto             = "Auto (Apple Watch priority)"
    case appleWatch       = "Apple Watch"
    case dedicatedDevice  = "Dedicated HRV Device"
}

// MARK: - PatternDataProvider Protocol

protocol PatternDataProvider: Sendable {
    func totalHealthKitHistoryDays() async throws -> Int
    func fetchDailyACWR(days: Int) async throws -> [(date: Date, acwr: Double)]
    func fetchDailyHRV(days: Int, sourcePreference: HRVSourcePreference) async throws -> [(date: Date, hrv: Double)]
    func fetchDailySleep(days: Int) async throws -> [(date: Date, hours: Double, efficiency: Double)]
    func fetchDailySteps(days: Int) async throws -> [(date: Date, steps: Int)]
    func fetchWorkoutDays(days: Int) async throws -> Set<String>  // "yyyy-MM-dd"
}

// MARK: - LivePatternDataProvider

struct LivePatternDataProvider: PatternDataProvider {
    private let store: HKHealthStore

    nonisolated init() { store = HKHealthStore() }

    func totalHealthKitHistoryDays() async throws -> Int {
        let type = HKQuantityType(.heartRateVariabilitySDNN)
        let predicate = HKQuery.predicateForSamples(withStart: .distantPast, end: Date())
        return try await withCheckedThrowingContinuation { cont in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: 1,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, error in
                if let error { cont.resume(throwing: error); return }
                guard let earliest = samples?.first?.startDate else {
                    cont.resume(returning: 0); return
                }
                let days = Calendar.current.dateComponents([.day], from: earliest, to: Date()).day ?? 0
                cont.resume(returning: max(0, days))
            }
            store.execute(query)
        }
    }

    func fetchDailyACWR(days: Int) async throws -> [(date: Date, acwr: Double)] {
        let type = HKQuantityType(.activeEnergyBurned)
        let daily = try await fetchDailyMetric(type: type, unit: .kilocalorie(), days: days, options: .cumulativeSum)
        let sorted = daily.sorted { $0.key < $1.key }
        guard sorted.count >= 7 else { return [] }

        var results: [(Date, Double)] = []
        for i in 6..<sorted.count {
            let acuteSlice = sorted[max(0, i - 6)...i].map { $0.value }
            let acute = acuteSlice.reduce(0, +) / Double(acuteSlice.count)
            let chronicSlice = sorted[max(0, i - 27)...i].map { $0.value }
            let chronic = chronicSlice.reduce(0, +) / Double(chronicSlice.count)
            let acwr = chronic > 0 ? acute / chronic : 0
            results.append((sorted[i].key, acwr))
        }
        return results
    }

    func fetchDailyHRV(days: Int, sourcePreference: HRVSourcePreference) async throws -> [(date: Date, hrv: Double)] {
        let type = HKQuantityType(.heartRateVariabilitySDNN)
        let raw = try await fetchDailyMetric(type: type, unit: HKUnit(from: "ms"), days: days, options: .discreteAverage)
        // Source preference filtering (dedicatedDevice / appleWatch) requires per-sample
        // source inspection — deferred to Phase 2b when full HKSampleQuery path is added.
        // In auto mode the statistics collection query already applies Watch priority.

        // Side effect: write source-blend flag for MetricConditionDetailView badge.
        let sourceCount = await detectHRVSourceCount(lookbackDays: 30)
        UserDefaults.standard.set(sourceCount > 1, forKey: "hrvMultipleSourcesDetected")

        return raw.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    /// Returns the number of distinct bundle IDs writing HRV samples in the past `lookbackDays`.
    private func detectHRVSourceCount(lookbackDays: Int) async -> Int {
        let type = HKQuantityType(.heartRateVariabilitySDNN)
        let start = Calendar.current.date(byAdding: .day, value: -lookbackDays, to: Date()) ?? Date()
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        return await withCheckedContinuation { cont in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: 200,
                sortDescriptors: nil
            ) { _, samples, _ in
                let bundles = Set((samples ?? []).map { $0.sourceRevision.source.bundleIdentifier })
                cont.resume(returning: bundles.count)
            }
            store.execute(query)
        }
    }

    func fetchDailySleep(days: Int) async throws -> [(date: Date, hours: Double, efficiency: Double)] {
        let type = HKCategoryType(.sleepAnalysis)
        let start = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        let fmt = Self.dayFormatter

        return try await withCheckedThrowingContinuation { cont in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, error in
                if let error { cont.resume(throwing: error); return }
                var byDay: [String: (inBed: Double, asleep: Double)] = [:]
                for sample in (samples as? [HKCategorySample]) ?? [] {
                    let key = fmt.string(from: sample.startDate)
                    let dur = sample.endDate.timeIntervalSince(sample.startDate) / 3600
                    var e = byDay[key] ?? (0, 0)
                    if sample.value == HKCategoryValueSleepAnalysis.inBed.rawValue {
                        e.inBed += dur
                    } else {
                        e.asleep += dur
                    }
                    byDay[key] = e
                }
                let result: [(Date, Double, Double)] = byDay.compactMap { key, val in
                    guard let date = fmt.date(from: key) else { return nil }
                    let eff = val.inBed > 0 ? val.asleep / val.inBed : 0
                    return (date, val.asleep, eff)
                }.sorted { $0.0 < $1.0 }
                cont.resume(returning: result)
            }
            self.store.execute(query)
        }
    }

    func fetchDailySteps(days: Int) async throws -> [(date: Date, steps: Int)] {
        let type = HKQuantityType(.stepCount)
        let raw = try await fetchDailyMetric(type: type, unit: .count(), days: days, options: .cumulativeSum)
        return raw.sorted { $0.key < $1.key }.map { ($0.key, Int($0.value)) }
    }

    func fetchWorkoutDays(days: Int) async throws -> Set<String> {
        let type = HKWorkoutType.workoutType()
        let start = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        let fmt = Self.dayFormatter
        return try await withCheckedThrowingContinuation { cont in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error { cont.resume(throwing: error); return }
                let days = Set((samples ?? []).map { fmt.string(from: $0.startDate) })
                cont.resume(returning: days)
            }
            store.execute(query)
        }
    }

    // MARK: - Shared DRY helper: daily aggregation via HKStatisticsCollectionQuery

    private func fetchDailyMetric(
        type: HKQuantityType,
        unit: HKUnit,
        days: Int,
        options: HKStatisticsOptions
    ) async throws -> [Date: Double] {
        let start = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        let anchor = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())

        return try await withCheckedThrowingContinuation { cont in
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: options,
                anchorDate: anchor,
                intervalComponents: DateComponents(day: 1)
            )
            query.initialResultsHandler = { _, results, error in
                if let error { cont.resume(throwing: error); return }
                var daily: [Date: Double] = [:]
                results?.enumerateStatistics(from: start, to: Date()) { stats, _ in
                    let qty = options == .cumulativeSum
                        ? stats.sumQuantity()
                        : stats.averageQuantity()
                    if let v = qty?.doubleValue(for: unit), v > 0 {
                        daily[stats.startDate] = v
                    }
                }
                cont.resume(returning: daily)
            }
            store.execute(query)
        }
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

// MARK: - PatternAnalysisError

enum PatternAnalysisError: Error {
    case insufficientData
    case persistenceFailed(Error)
}

// MARK: - TrainingDNAAnalyzer

@ModelActor
actor TrainingDNAAnalyzer {
    var dataProvider: any PatternDataProvider = LivePatternDataProvider()

    /// Shared day formatter — created once, reused across all formatDay calls.
    private let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone.current
        return f
    }()

    // MARK: - Dependency Injection

    /// Replaces the live data provider with a test double. Call before `analyze()` in tests.
    func setDataProvider(_ provider: any PatternDataProvider) {
        self.dataProvider = provider
    }

    /// Returns all stored TrainingPattern objects from this actor's model context.
    /// Use in tests to verify persistence without relying on cross-context merge timing.
    func fetchAllPatterns() throws -> [TrainingPattern] {
        try modelContext.fetch(FetchDescriptor<TrainingPattern>())
    }

    /// Pre-populates StoredDailyScore records for detectBackToBackReadinessCrash tests.
    /// Used in tests to avoid needing a live ReadinessRepository analysis run.
    func insertDailyScores(_ scores: [StoredDailyScore]) throws {
        for score in scores { modelContext.insert(score) }
        try modelContext.save()
    }

    /// Sets notificationSent = true for the matching pattern type and saves.
    /// Used in tests to simulate a notification being dispatched without going through
    /// PatternNotificationService (which requires UNUserNotification authorization).
    func markNotificationSent(patternType: PatternType) throws {
        let all = try modelContext.fetch(FetchDescriptor<TrainingPattern>())
        all.first { $0.patternType == patternType }?.notificationSent = true
        try modelContext.save()
    }

    // MARK: - Main Entry Point

    /// Returns the total HealthKit history days so callers can persist it for section-visibility gating.
    func analyze(sourcePreference: HRVSourcePreference = .auto) async throws -> Int {
        guard !Task.isCancelled else { return 0 }

        let historyDays = try await dataProvider.totalHealthKitHistoryDays()
        guard historyDays >= 60 else { throw PatternAnalysisError.insufficientData }

        var detected: [TrainingPattern] = []

        if historyDays >= 90, !Task.isCancelled {
            if let p = try await detectBlockCrashCycle() { detected.append(p) }
        }

        if historyDays >= 90, !Task.isCancelled {
            if let p = try await detectHRVPrecursor(sourcePreference: sourcePreference) { detected.append(p) }
        }

        if !Task.isCancelled {
            if let p = try await detectSleepFragmentation() { detected.append(p) }
        }

        if historyDays >= 90, !Task.isCancelled {
            if let p = try await detectBackToBackReadinessCrash() { detected.append(p) }
        }

        if historyDays >= 90, !Task.isCancelled {
            if let p = try await detectPerformancePeak(sourcePreference: sourcePreference) { detected.append(p) }
            if let p = try await detectTaperUnderway(sourcePreference: sourcePreference) { detected.append(p) }
        }

        guard !Task.isCancelled else { return historyDays }

        try upsertPatterns(detected)

        let allStored = (try? modelContext.fetch(FetchDescriptor<TrainingPattern>())) ?? []
        let detectedTypes = detected.map(\.patternType)
        let unsent = allStored.filter { !$0.notificationSent && detectedTypes.contains($0.patternType) }
        await PatternNotificationService.shared.notifyIfNew(unsent)

        do {
            try modelContext.save()
        } catch {
            throw PatternAnalysisError.persistenceFailed(error)
        }

        return historyDays
    }

    // MARK: - Pattern 1: Block Crash Cycle

    private func detectBlockCrashCycle() async throws -> TrainingPattern? {
        let history = try await dataProvider.fetchDailyACWR(days: 180)
        guard history.count >= 30 else { return nil }

        // Identify training blocks: runs of ACWR > 0.8 lasting ≥ 14 days
        var blocks: [(start: Date, end: Date)] = []
        var blockStart: Date?
        var blockLast: Date?

        for (date, acwr) in history {
            if acwr > 0.8 {
                if blockStart == nil { blockStart = date }
                blockLast = date
            } else if let start = blockStart, let last = blockLast {
                if Calendar.current.dateComponents([.day], from: start, to: last).day ?? 0 >= 14 {
                    blocks.append((start, last))
                }
                blockStart = nil; blockLast = nil
            }
        }
        if let start = blockStart, let last = blockLast,
           Calendar.current.dateComponents([.day], from: start, to: last).day ?? 0 >= 14 {
            blocks.append((start, last))
        }

        guard blocks.count >= 3 else { return nil }

        // Collect ACWR values at end of each block (crash signal)
        let crashACWRs: [Double] = blocks.compactMap { block in
            history.filter { $0.date >= block.end &&
                $0.date <= Calendar.current.date(byAdding: .day, value: 5, to: block.end)! }
                .map(\.acwr)
                .first
        }

        guard crashACWRs.count >= 3 else { return nil }

        // StatisticalValidator called ONCE on the full candidate set
        guard let stats = StatisticalValidator.bootstrapConfidenceInterval(data: crashACWRs),
              stats.mean < 0.85 else { return nil }

        let instanceDates = blocks.map { $0.end }
        let matching = crashACWRs.filter { $0 < 0.85 }.count

        return TrainingPattern(
            patternType: .blockCrashCycle,
            confidenceNumerator: matching,
            confidenceDenominator: blocks.count,
            evidenceSummary: "Your HRV and training load consistently drop in the final days of each training block, indicating accumulated overreach.",
            citationKey: PatternType.blockCrashCycle.citationKey,
            instanceDates: instanceDates,
            coachingResponse: "Try adding an extra deload day at the end of each block. Reduce volume 3–5 days before your planned rest week rather than stopping abruptly."
        )
    }

    // MARK: - Pattern 2: HRV Precursor

    private func detectHRVPrecursor(sourcePreference: HRVSourcePreference) async throws -> TrainingPattern? {
        let hrvHistory = try await dataProvider.fetchDailyHRV(days: 180, sourcePreference: sourcePreference)
        let stepHistory = try await dataProvider.fetchDailySteps(days: 180)
        let workoutDays = try await dataProvider.fetchWorkoutDays(days: 180)

        guard hrvHistory.count >= 30 else { return nil }

        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"

        // Detect sick day proxies: step count < 2000 for 2+ CONSECUTIVE days AND no workout
        let stepsSorted = stepHistory.sorted { $0.date < $1.date }
        var sickDayWindows: [Date] = []
        var i = 0
        while i < stepsSorted.count - 1 {
            let a = stepsSorted[i], b = stepsSorted[i + 1]
            let consecutive = Calendar.current.isDate(
                b.date, inSameDayAs: Calendar.current.date(byAdding: .day, value: 1, to: a.date)!
            )
            if consecutive && a.steps < 2000 && b.steps < 2000
                && !workoutDays.contains(fmt.string(from: a.date))
                && !workoutDays.contains(fmt.string(from: b.date)) {
                sickDayWindows.append(a.date)
                i += 2; continue
            }
            i += 1
        }

        guard sickDayWindows.count >= 3 else { return nil }

        guard let baselineHRV = median(hrvHistory.map(\.hrv)), baselineHRV > 0 else { return nil }

        // Check HRV 36–72h before each sick day window
        var precursorMatches: [Date] = []
        for sickDate in sickDayWindows {
            let t72 = Calendar.current.date(byAdding: .hour, value: -72, to: sickDate)!
            let t36 = Calendar.current.date(byAdding: .hour, value: -36, to: sickDate)!
            let vals = hrvHistory.filter { $0.date >= t72 && $0.date <= t36 }.map(\.hrv)
            if let mean = vals.isEmpty ? nil : vals.reduce(0, +) / Double(vals.count),
               mean < baselineHRV * 0.85 {
                precursorMatches.append(sickDate)
            }
        }

        guard precursorMatches.count >= 3 else { return nil }

        let precursorDrops: [Double] = precursorMatches.compactMap { date in
            let t72 = Calendar.current.date(byAdding: .hour, value: -72, to: date)!
            let t36 = Calendar.current.date(byAdding: .hour, value: -36, to: date)!
            let vals = hrvHistory.filter { $0.date >= t72 && $0.date <= t36 }.map(\.hrv)
            return vals.isEmpty ? nil : vals.reduce(0, +) / Double(vals.count)
        }

        // StatisticalValidator called ONCE on the full candidate set
        guard let stats = StatisticalValidator.bootstrapConfidenceInterval(data: precursorDrops),
              stats.mean < baselineHRV * 0.9 else { return nil }

        return TrainingPattern(
            patternType: .hrvPrecursor,
            confidenceNumerator: precursorMatches.count,
            confidenceDenominator: sickDayWindows.count,
            evidenceSummary: "Your HRV consistently drops 15%+ below baseline 36–72 hours before illness — a detectable early warning signature.",
            citationKey: PatternType.hrvPrecursor.citationKey,
            instanceDates: precursorMatches,
            coachingResponse: "When HRV drops 15%+ below baseline with no obvious training cause, prioritize sleep and reduce intensity for 48 hours."
        )
    }

    // MARK: - Pattern 3: Sleep Fragmentation

    private func detectSleepFragmentation() async throws -> TrainingPattern? {
        let sleepHistory = try await dataProvider.fetchDailySleep(days: 180)
        let acwrHistory = try await dataProvider.fetchDailyACWR(days: 180)

        guard sleepHistory.count >= 20 else { return nil }

        // High-load periods: 7+ consecutive days of ACWR > 1.0
        var highLoadPeriods: [(start: Date, end: Date)] = []
        var pStart: Date?; var pLast: Date?

        for (date, acwr) in acwrHistory.sorted(by: { $0.date < $1.date }) {
            if acwr > 1.0 {
                if pStart == nil { pStart = date }
                pLast = date
            } else if let s = pStart, let l = pLast {
                if Calendar.current.dateComponents([.day], from: s, to: l).day ?? 0 >= 7 {
                    highLoadPeriods.append((s, l))
                }
                pStart = nil; pLast = nil
            }
        }
        if let s = pStart, let l = pLast,
           Calendar.current.dateComponents([.day], from: s, to: l).day ?? 0 >= 7 {
            highLoadPeriods.append((s, l))
        }

        guard highLoadPeriods.count >= 2 else { return nil }

        // Baseline sleep efficiency: days NOT in any high-load period
        let baselineSleep = sleepHistory.filter { s in
            !highLoadPeriods.contains { s.date >= $0.start && s.date <= $0.end }
        }
        guard let baselineEff = median(baselineSleep.map(\.efficiency)), baselineEff > 0 else { return nil }

        var fragmentedPeriods: [Date] = []
        for period in highLoadPeriods {
            let inPeriod = sleepHistory.filter { $0.date >= period.start && $0.date <= period.end }
            guard !inPeriod.isEmpty else { continue }
            let meanEff = inPeriod.map(\.efficiency).reduce(0, +) / Double(inPeriod.count)
            if meanEff < baselineEff * 0.9 { fragmentedPeriods.append(period.start) }
        }

        guard fragmentedPeriods.count >= 2 else { return nil }

        let effDrops: [Double] = fragmentedPeriods.compactMap { date in
            guard let period = highLoadPeriods.first(where: { $0.start == date }) else { return nil }
            let vals = sleepHistory.filter { $0.date >= period.start && $0.date <= period.end }.map(\.efficiency)
            return vals.isEmpty ? nil : vals.reduce(0, +) / Double(vals.count)
        }

        // StatisticalValidator called ONCE on the full candidate set
        guard effDrops.count >= 2,
              let stats = StatisticalValidator.bootstrapConfidenceInterval(data: effDrops),
              stats.mean < baselineEff * 0.92 else { return nil }

        return TrainingPattern(
            patternType: .sleepFragmentation,
            confidenceNumerator: fragmentedPeriods.count,
            confidenceDenominator: highLoadPeriods.count,
            evidenceSummary: "Your sleep efficiency consistently drops during high-load training periods, suggesting accumulated fatigue is disrupting sleep architecture.",
            citationKey: PatternType.sleepFragmentation.citationKey,
            instanceDates: fragmentedPeriods,
            coachingResponse: "During high-load weeks: consistent bedtime, cool room, no screens 30 minutes before bed. Sleep hygiene matters more when training stress is high."
        )
    }

    // MARK: - Pattern 4: Back-to-Back Crash

    /// Detects whether the user's readiness consistently crashes after two consecutive
    /// high-strain training days. Uses vote-based confirmation (drop > 10pts = Yes-vote;
    /// confirm if Yes-rate >= 60% and n >= 4). Pearson r is computed for display only.
    ///
    /// Data source: StoredDailyScore — fetched directly from this actor's modelContext
    /// (StoredDailyScore is in the shared schema since HealthDataContainer was updated).
    private func detectBackToBackReadinessCrash() async throws -> TrainingPattern? {
        let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date()
        let allScores = (try? modelContext.fetch(FetchDescriptor<StoredDailyScore>())) ?? []
        let scores = allScores
            .filter { $0.date >= cutoff }
            .sorted { $0.date < $1.date }

        guard scores.count >= 14 else { return nil }

        let calendar = Calendar.current

        // Build a day-keyed lookup for O(1) access
        let scoreByDate: [String: Int] = Dictionary(
            uniqueKeysWithValues: scores.map { (formatDay($0.date), $0.readinessScore) }
        )
        let workoutByDate: [String: Int] = Dictionary(
            uniqueKeysWithValues: scores.map { (formatDay($0.date), $0.workoutCount) }
        )

        // Identify back-to-back hard days: two consecutive days each with >= 1 workout.
        // "Hard" proxy = workoutCount >= 1 on both days. We look at Day+1 and Day+2 crash.
        var sequences: [(crashDate: Date, dropMagnitude: Double)] = []

        for i in 1..<(scores.count - 1) {
            let dayA = scores[i - 1]
            let dayB = scores[i]
            let dayC = scores[i + 1]   // the crash day

            let keyA = formatDay(dayA.date)
            let keyB = formatDay(dayB.date)
            let keyC = formatDay(dayC.date)

            // Must be three consecutive calendar days
            guard let nextA = calendar.date(byAdding: .day, value: 1, to: dayA.date),
                  calendar.isDate(nextA, inSameDayAs: dayB.date),
                  let nextB = calendar.date(byAdding: .day, value: 1, to: dayB.date),
                  calendar.isDate(nextB, inSameDayAs: dayC.date) else { continue }

            // Both A and B must have workouts (back-to-back hard days)
            guard (workoutByDate[keyA] ?? 0) >= 1,
                  (workoutByDate[keyB] ?? 0) >= 1 else { continue }

            let scoreA = Double(scoreByDate[keyA] ?? 50)
            let scoreC = Double(scoreByDate[keyC] ?? 50)

            // C is the post-sequence crash day — compare against the average of A and B
            let scoreB = Double(scoreByDate[keyB] ?? 50)
            let avgAB = (scoreA + scoreB) / 2.0
            let drop = avgAB - scoreC

            if drop > 0 {
                sequences.append((crashDate: dayC.date, dropMagnitude: drop))
            }
        }

        guard sequences.count >= 4 else { return nil }

        // Vote-based confirmation: drop > 10pts = Yes-vote
        let yesVotes = sequences.filter { $0.dropMagnitude > 10 }
        let yesRate = Double(yesVotes.count) / Double(sequences.count)

        // Pearson r: sequence index vs drop magnitude
        let xVals = (0..<sequences.count).map { Double($0) }
        let yVals = sequences.map { $0.dropMagnitude }
        let pearson = StatisticalValidator.pearsonCorrelation(x: xVals, y: yVals)
        let lagR = pearson?.r ?? 0.0

        // Confirmation gate:
        //   n < 10:  vote gate — yesRate >= 60% (stable at small samples)
        //   n >= 10: combined gate — yesRate >= 40% AND lagCorrelation >= 0.55
        //            (Pearson meaningful at n=10+; relaxed vote floor prevents silencing
        //             consistent crashes that are growing in magnitude)
        if sequences.count < 10 {
            guard yesRate >= 0.60 else { return nil }
        } else {
            guard yesRate >= 0.40, lagR >= 0.55 else { return nil }
        }

        // Average drop across confirmed sequences
        let avgDrop = yVals.reduce(0, +) / Double(yVals.count)

        let instanceDates = yesVotes.map { $0.crashDate }
        let avgDropInt = Int(avgDrop.rounded())

        return TrainingPattern(
            patternType: .backToBackCrash,
            confidenceNumerator: yesVotes.count,
            confidenceDenominator: sequences.count,
            evidenceSummary: "Your readiness drops an average of \(avgDropInt) points the day after back-to-back training sessions. Seen in \(yesVotes.count) of \(sequences.count) sequences over the last 90 days.",
            citationKey: PatternType.backToBackCrash.citationKey,
            instanceDates: instanceDates,
            coachingResponse: "Separate hard sessions by at least one recovery day. If you must train back-to-back, keep day 2 at zone 1–2 intensity only.",
            lagCorrelation: lagR,
            peakDropDay: 1    // crash is deepest at Day+1 (the day after the second hard session)
        )
    }

    private func formatDay(_ date: Date) -> String {
        dayFormatter.string(from: date)
    }

    // MARK: - Pattern 5: Performance Peak

    /// Detects when the user is in a race-ready peak window.
    /// Criteria: HRV elevated (top 20% of 90-day range) for 7+ consecutive days AND
    /// ACWR in the sweet spot (0.8–1.3) for 10+ consecutive days.
    ///
    /// Probability: hrvScore * 0.60 + acwrScore * 0.40 — confirmation gate >= 80%.
    /// HRV data from dataProvider (daily aggregated, same path as detectHRVPrecursor).
    /// ACWR streak from StoredDailyScore.dailyStrain (pre-computed ACWR ratio).
    private func detectPerformancePeak(sourcePreference: HRVSourcePreference) async throws -> TrainingPattern? {
        let hrvHistory = try await dataProvider.fetchDailyHRV(days: 90, sourcePreference: sourcePreference)
        guard hrvHistory.count >= 7 else { return nil }

        // ACWR streak from StoredDailyScore (same source as detectBackToBackReadinessCrash)
        let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date()
        let allScores = (try? modelContext.fetch(FetchDescriptor<StoredDailyScore>())) ?? []
        let scores = allScores.filter { $0.date >= cutoff }.sorted { $0.date < $1.date }

        // HRV elevation streak: consecutive trailing days in top 20% of 90-day range
        let sortedHRV = hrvHistory.map(\.hrv).sorted()
        let p80idx = Int(Double(sortedHRV.count) * 0.80)
        let p80threshold = sortedHRV[min(p80idx, sortedHRV.count - 1)]

        let sortedHRVByDate = hrvHistory.sorted { $0.date > $1.date } // newest first
        var hrvStreakDays = 0
        for entry in sortedHRVByDate {
            if entry.hrv >= p80threshold {
                hrvStreakDays += 1
            } else {
                break  // missing day or below threshold — streak ends
            }
        }

        // ACWR sweet-spot streak: consecutive trailing days where dailyStrain in [0.8, 1.3]
        var acwrStreakDays = 0
        for score in scores.reversed() {
            if score.dailyStrain >= 0.8 && score.dailyStrain <= 1.3 {
                acwrStreakDays += 1
            } else {
                break
            }
        }

        let hrvScore  = min(1.0, Double(hrvStreakDays)  / 7.0)  * 0.60
        let acwrScore = min(1.0, Double(acwrStreakDays) / 10.0) * 0.40
        let probability = (hrvScore + acwrScore)   // 0.0–1.0

        guard probability >= 0.80 else { return nil }

        // Signal strength label — avoids displaying a deceptively precise percentage
        let signalLabel: String
        switch probability {
        case 0.90...: signalLabel = "Peak form"
        default:      signalLabel = "Building"
        }

        return TrainingPattern(
            patternType: .performancePeak,
            confidenceNumerator: hrvStreakDays,
            confidenceDenominator: 7,
            evidenceSummary: "\(signalLabel) — HRV elevated for \(hrvStreakDays) consecutive days and training load optimal for \(acwrStreakDays) days. Pyne et al. 2009.",
            citationKey: PatternType.performancePeak.citationKey,
            instanceDates: [Date()],
            coachingResponse: "You're in peak form — great week for a race or benchmark effort. Maintain current load; don't add volume.",
            probability: probability
        )
    }

    // MARK: - Pattern 6: Taper Underway

    /// Detects when the user has intentionally reduced training load before a race.
    /// Criteria: ACWR last 7 days dropped >= 30% vs days 8–28 AND HRV slope last 7 days is positive.
    /// Predicted peak date: today + 14 days (Mujika & Padilla 2003 — recreational athletes).
    private func detectTaperUnderway(sourcePreference: HRVSourcePreference) async throws -> TrainingPattern? {
        let cutoff28 = Calendar.current.date(byAdding: .day, value: -28, to: Date()) ?? Date()
        let allScores = (try? modelContext.fetch(FetchDescriptor<StoredDailyScore>())) ?? []
        let scores28 = allScores.filter { $0.date >= cutoff28 }.sorted { $0.date < $1.date }
        guard scores28.count >= 28 else { return nil }

        // Load drop: mean ACWR last 7 days vs mean ACWR days 8–28
        let last7  = scores28.suffix(7).map(\.dailyStrain)
        let prev21 = scores28.prefix(scores28.count - 7).map(\.dailyStrain)
        guard !last7.isEmpty, !prev21.isEmpty else { return nil }

        let acwrLast7  = last7.reduce(0, +)  / Double(last7.count)
        let acwrPrev21 = prev21.reduce(0, +) / Double(prev21.count)
        let dropPct    = acwrPrev21 > 0.01 ? (acwrPrev21 - acwrLast7) / acwrPrev21 : 0.0

        guard dropPct >= 0.30 else { return nil }

        // HRV trend: positive slope over last 7 days
        let hrvHistory = try await dataProvider.fetchDailyHRV(days: 7, sourcePreference: sourcePreference)
        let sortedHRV = hrvHistory.sorted { $0.date < $1.date }
        let hrvValues = sortedHRV.map(\.hrv)
        let xVals = (0..<hrvValues.count).map { Double($0) }
        let hrv_slope_positive: Bool
        if let reg = StatisticalValidator.linearRegression(x: xVals, y: hrvValues) {
            hrv_slope_positive = reg.slope > 0
        } else {
            hrv_slope_positive = false
        }

        let loadConfidence = min(1.0, dropPct / 0.30) * 0.60
        let hrvConfidence  = hrv_slope_positive ? 0.40 : 0.0
        let probability    = loadConfidence + hrvConfidence
        guard probability >= 0.80 else { return nil }

        // Peak date: fixed 14-day estimate (recreational athletes, Mujika & Padilla 2003)
        let peakDate = Calendar.current.date(byAdding: .day, value: 14, to: Date()) ?? Date()

        let loadDropPct = Int((dropPct * 100).rounded())
        let peakFormatter = DateFormatter()
        peakFormatter.dateStyle = .medium
        peakFormatter.timeStyle = .none
        let peakDateStr = peakFormatter.string(from: peakDate)

        return TrainingPattern(
            patternType: .tapering,
            confidenceNumerator: Int((dropPct * 100).rounded()),
            confidenceDenominator: 30,
            evidenceSummary: "Load down \(loadDropPct)% — peak form expected \(peakDateStr). Mujika & Padilla 2003.",
            citationKey: PatternType.tapering.citationKey,
            instanceDates: [Date()],
            coachingResponse: "Taper underway — keep intensity but cut volume. Trust the process; fitness is locked in.",
            peakDate: peakDate
        )
    }

    // MARK: - Upsert

    private func upsertPatterns(_ patterns: [TrainingPattern]) throws {
        // Fetch all stored patterns once and filter in-memory.
        // #Predicate cannot capture custom enum values — SwiftData only supports scalar captures.
        let allStored = try modelContext.fetch(FetchDescriptor<TrainingPattern>())
        for new in patterns {
            let existing = allStored.first { $0.patternType == new.patternType }

            if let existing {
                existing.detectedAt = new.detectedAt
                existing.confidenceNumerator = new.confidenceNumerator
                existing.confidenceDenominator = new.confidenceDenominator
                existing.instanceDates = new.instanceDates
                existing.evidenceSummary = new.evidenceSummary
                existing.coachingResponse = new.coachingResponse
                existing.lagCorrelation = new.lagCorrelation
                existing.peakDropDay = new.peakDropDay
                existing.probability = new.probability
                existing.peakDate = new.peakDate
                // notificationSent is NEVER reset once true
            } else {
                modelContext.insert(new)
            }
        }
    }

    // MARK: - Math

    private func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let s = values.sorted()
        let m = s.count / 2
        return s.count.isMultiple(of: 2) ? (s[m - 1] + s[m]) / 2 : s[m]
    }
}
