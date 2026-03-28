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
        return raw.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
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

    // MARK: - Upsert

    private func upsertPatterns(_ patterns: [TrainingPattern]) throws {
        for new in patterns {
            let type = new.patternType
            let existing = try modelContext.fetch(
                FetchDescriptor<TrainingPattern>(predicate: #Predicate { $0.patternType == type })
            ).first

            if let existing {
                existing.detectedAt = new.detectedAt
                existing.confidenceNumerator = new.confidenceNumerator
                existing.confidenceDenominator = new.confidenceDenominator
                existing.instanceDates = new.instanceDates
                existing.evidenceSummary = new.evidenceSummary
                existing.coachingResponse = new.coachingResponse
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
