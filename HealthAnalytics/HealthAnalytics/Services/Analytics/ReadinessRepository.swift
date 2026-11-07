//
//  ReadinessRepository.swift
//  HealthAnalytics
//
//  The "Master Coach" layer. Centralizes all analysis services,
//  reconciles competing advice, and ensures UI consistency.
//

import Foundation
import SwiftUI
import UIKit
import SwiftData
import HealthKit
import Combine

@MainActor
class ReadinessRepository: ObservableObject {
    static let shared = ReadinessRepository()
    
    // MARK: - Published State
    
    @Published private(set) var currentReadiness: UnifiedReadiness?
    @Published private(set) var intraDayReadiness: RecoveryDecayService.IntraDayReadiness?
    @Published private(set) var forecast: [ReadinessForecastDay]?
    @Published private(set) var isAnalyzing = false
    /// Non-nil when analysis fails; nil on success. Views branch on this to show
    /// "add workouts" vs "something went wrong" vs normal content.
    @Published private(set) var analysisError: String?
    /// Pattern analysis's own failure, shown by the Training DNA card. Kept apart from
    /// `analysisError` so a recovery failure isn't shown as a pattern failure and a later
    /// recovery run can't clear a real pattern error.
    @Published private(set) var patternAnalysisError: String?
    /// Bumped whenever the score backfill inserts rows. A pattern run that overlapped one
    /// (the first launch: Recovery's run starts before the backfill saves) doesn't stamp the
    /// throttle, so the next trigger re-runs on the full history.
    private var scoreBackfillGeneration = 0
    /// Bumped by every pattern run that starts. A run replaced as hung (see
    /// `hungPatternRunLimit`) may still end later; only the newest run reports an error.
    private var patternRunGeneration = 0
    
    // MARK: - Dependencies

    private let readinessAnalyzer = ReadinessAnalyzer()
    private let riskCalculator = InjuryRiskCalculator()
    private let recommendationService = DailyRecommendationService()
    private let loadCalculator = TrainingLoadCalculator()
    private let recoveryService = RecoveryDecayService()

    // ML sub-services (moved from ReadinessViewModel per GEMINI.md mandate)
    private let trendDetector = TrendDetector()

    // Training load & zone sub-services (moved from ReadinessViewModel per GEMINI.md mandate)
    private let predictiveReadinessService = PredictiveReadinessService()
    private let correlationEngineRepo      = CorrelationEngine()
    private let loadVizService             = TrainingLoadVisualizationService()

    // Insights sub-services (moved from InsightsViewModel per GEMINI.md mandate)
    private let nutritionEngine            = NutritionCorrelationEngine()
    private let agingService               = BiologicalAgingService()
    private let actionableRecommendations  = ActionableRecommendations()
    private let cyclingPowerAnalyzer       = CyclingPowerAnalyzer()

    // Per-tab sub-services (moved from ReadinessViewModel + DashboardViewModel — Phase 1.2)
    private let cardiovascularStrainService = CardiovascularStrainService()
    private let metAnalyzer                 = METAnalyzer()
    private let balanceAnalyzer             = BalancedTrainingAnalyzer()

    // maxHR cache (was on ReadinessViewModel — Phase 1.2 migration)
    private static let maxHRCacheKey = "cachedPersonalMaxHR"
    private static let maxHRCacheDateKey = "cachedPersonalMaxHRDate"
    private static let maxHRCacheTTL: TimeInterval = 7 * 86400 // 7 days

    // Phase 2 — Pattern Engine sub-service
    private var trainingDNAAnalyzer: TrainingDNAAnalyzer?


    private var lastFingerprint: PredictionCache.DataFingerprint?
    private var lastAnalysisDate: Date?
    /// The active pattern set baked into the published `coachAdvice`. A pattern
    /// expiring changes no data count, so the fingerprint alone would keep serving
    /// a Coach paragraph that cites a card the Patterns tab has already dropped.
    private var lastActivePatternTypes: Set<PatternType>?
    /// The illness state baked into the published `coachAdvice`. Logging a sick day
    /// changes no data count, so without it the paragraph would keep advising training.
    private var lastIllnessState: MasterCoachEngine.IllnessState?
    /// The active Coach notes (Injury, Stress, Travel, custom) baked into `coachAdvice`. A
    /// chip tap during a running analysis is replayed through `refreshIfNecessary`, so without
    /// this the replay reused the cache and dropped the note; a note expiring (its TTL) changes
    /// the paragraph too.
    private var lastActiveMemoryIDs: Set<UUID>?
    /// The plan's store inputs. A zone backfill or a recomputed row moves the plan without
    /// moving any count or latest date the fingerprint can see.
    private var lastForecastSignature: Int?
    /// When the plan last forced a score backfill for lack of history (see `shouldForceScoreBackfill`).
    private var lastForcedBackfillDate: Date?
    private struct ForecastInputReadFailed: Error {}

    /// Set when a refresh arrives while `performFullAnalysis` is mid-flight, so the
    /// run can re-check the store on the way out instead of the request being lost.
    private var pendingRefreshRequested = false

    private var syncCompletedObserver: NSObjectProtocol?

    /// Pattern analysis is requested from view `.task`s; the flight owns the run so a
    /// tab swipe can't cancel it and back-to-back appears join one analysis.
    private let patternAnalysisFlight = SingleFlight()
    /// Whether the app is in the foreground when a pattern run's outcome lands. A run
    /// that finishes in the foreground refreshes Coach and reports errors; one that
    /// finishes in the background (often with the device locked, where HealthKit refuses
    /// reads) stays silent, and the next foreground catches up because the active
    /// pattern set is part of the cache key. Decided at completion, not from who started
    /// the run: a background run that resumes and finishes after the user reopens the
    /// app must still refresh Coach. Overridable for tests.
    var isAppInForeground: @MainActor () -> Bool = ReadinessRepository.applicationIsInForeground

    static func applicationIsInForeground() -> Bool {
        UIApplication.shared.applicationState != .background
    }

    /// HealthKit refusing reads because the device is (or was, mid-run) locked. Never an
    /// error row, even when the run finishes in the foreground — a run suspended across a
    /// lock resumes on unlock and fails for a reason that no longer applies. Unstamped,
    /// so the next appear retries.
    nonisolated static func isLockedDeviceError(_ error: Error) -> Bool {
        (error as? HKError)?.code == .errorDatabaseInaccessible
    }

    /// Who asked for pattern analysis. Decides only the throttle (`shouldRunPatternAnalysis`);
    /// how the run reports is decided when it finishes — see `isAppInForeground`.
    enum PatternAnalysisTrigger: Sendable {
        /// RecoveryTabView appearing. Throttled by `forcedPatternAnalysisMinInterval`.
        case appear
        /// InsightsView appearing. Runs only when the last run is older than
        /// `patternAnalysisStalenessInterval`.
        case staleCheck
        /// The user tapped "Try again". Always runs.
        case userRetry
        /// The `.appRefresh` background task. Throttled like `.appear`.
        case background
    }

    /// An automatic run (the Recovery tab triggers one on every appear) is skipped if a
    /// run completed this recently. Patterns move over days, so this only sheds tab-swipe
    /// churn; a user-initiated retry is never throttled.
    nonisolated static let forcedPatternAnalysisMinInterval: TimeInterval = 5 * 60

    /// How old the last run must be before an InsightsView appear re-runs it. Must stay
    /// below `TrainingPattern.activeWindowDays` or patterns expire before their refresh.
    nonisolated static let patternAnalysisStalenessInterval: TimeInterval = 7 * 86400

    /// UserDefaults key for the pattern-analysis throttle stamp, shared by the foreground
    /// run and the background pass.
    nonisolated static let lastPatternAnalysisKey = "lastPatternAnalysisDate"

    private static let dailyScoreDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone.current
        return f
    }()

    private init() {}

    /// Wires the repository to refresh whenever sync completes. Idempotent — safe
    /// to call multiple times; only the first call subscribes. Pulls the model
    /// context fresh from `HealthDataContainer.shared` at each refresh so a
    /// `resetAllData()` flow doesn't leave us holding a stale context.
    func bootstrap() {
        guard syncCompletedObserver == nil else { return }
        syncCompletedObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("DataSyncCompleted"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                // Only the foreground posts DataSyncCompleted (sync, zone backfill, reset), never
                // the background pass, so recent rows aren't refilled from Health-only data.
                // This Task runs after the poster clears isSyncing, so a sync's own post
                // recomputes, even with its zone backfill already running; a reset's post, a zone
                // backfill posting mid-reset, or a sync whose HealthKit fetch failed does not.
                if SyncManager.shared.mayRecomputeDailyLoads {
                    self.recomputeRecentDailyLoads(modelContext: HealthDataContainer.shared.mainContext)
                }
                await self.refreshIfNecessary(
                    modelContext: HealthDataContainer.shared.mainContext
                )
            }
        }
    }

    #if DEBUG
    /// Resets published state to a clean baseline. Use in unit tests to prevent
    /// cross-test contamination through ReadinessRepository.shared.
    func resetForTesting() {
        currentReadiness = nil
        forecast = nil
        lastFingerprint = nil
        lastAnalysisDate = nil
        lastActivePatternTypes = nil
        lastIllnessState = nil
        lastActiveMemoryIDs = nil
        lastForecastSignature = nil
        lastForcedBackfillDate = nil
        analysisError = nil
        patternAnalysisError = nil
        isAppInForeground = Self.applicationIsInForeground
    }
    #endif

    // MARK: - Pattern Analysis (Phase 2)

    /// Callers await the run but never own it — see `patternAnalysisFlight`. A request
    /// that arrives mid-run joins it. Joiners need no follow-up: the run itself decides,
    /// when it finishes, whether to refresh Coach and report errors (`isAppInForeground`).
    /// The one exception is a joined run that stored nothing because it spanned a
    /// suspension (a background pass that ended `abandoned`, or a foreground run whose
    /// commit gate declined): `SingleFlight` then runs this request once on its own.
    /// A foreground request gives up on a pattern run this old: it can't commit anything
    /// (`BackgroundPatternPass.maxDuration` is 2 minutes), so it is hung, and joining it
    /// would block "Try again" until the process dies.
    nonisolated static let hungPatternRunLimit: TimeInterval = 10 * 60

    func runPatternAnalysis(container: ModelContainer, trigger: PatternAnalysisTrigger) async {
        await patternAnalysisFlight.run({ [self] in
            await performPatternAnalysis(container: container, trigger: trigger)
        }, replacingRunsOlderThan: Self.hungPatternRunLimit)
    }

    /// The background pattern pass (HealthKit delivery, app refresh). Shares
    /// `patternAnalysisFlight` with the foreground, so overlapping wakes and a Recovery
    /// visit during a background run still produce one run. A pass that ends `abandoned`
    /// reports not-completed, so a wake or appear that joined it runs once more instead
    /// of being swallowed by a run that stored nothing.
    func runBackgroundPass(container: ModelContainer, wake: BackgroundPassWake) async {
        let log = BackgroundPassLog.standard
        // `!= .background`, not `== .active`: a foreground cold launch is still `.inactive`
        // when didFinishLaunching runs the observer queries, and their first callbacks
        // must not count as background deliveries. Same rule as `applicationIsInForeground`.
        let inForeground = Self.applicationIsInForeground()
        log.recordWake(wake, appActive: inForeground)
        // The observers' registration callbacks on every foreground cold launch would
        // otherwise run a full pass; the foreground's own sync and refresh cover it.
        // Checked here to avoid joining a run at all, and again by `shouldStart`, which is
        // the check that matters: a joiner's retry starts a run later, maybe after the
        // user opened the app.
        if BackgroundPatternPass.skipIfForeground(appInForeground: inForeground, log: log, at: Date()) { return }
        await patternAnalysisFlight.run(
            BackgroundPatternPass.flightWork(makePass: { [self] in
                BackgroundPatternPass(
                    steps: LiveBackgroundPassSteps(repository: self, container: container), log: log, wake: wake
                )
            }),
            shouldStart: BackgroundPatternPass.shouldStart(
                appInForeground: { Self.applicationIsInForeground() }, log: log
            )
        )
    }

    /// Detection + gated commit for the background pass, on the same analyzer instance
    /// as the foreground. Throws what `analyze` throws, including `.commitDeclined`.
    func analyzePatternsForBackgroundPass(
        container: ModelContainer,
        commitGate: @escaping @Sendable () async -> Bool
    ) async throws {
        if trainingDNAAnalyzer == nil {
            trainingDNAAnalyzer = TrainingDNAAnalyzer(modelContainer: container)
        }
        let historyDays = try await trainingDNAAnalyzer!.analyze(
            sourcePreference: hrvSourcePreference,
            commitGate: commitGate
        )
        UserDefaults.standard.set(historyDays, forKey: "healthKitHistoryDays")
    }

    private var hrvSourcePreference: HRVSourcePreference {
        HRVSourcePreference(
            rawValue: UserDefaults.standard.string(forKey: "preferredHRVSource") ?? HRVSourcePreference.auto.rawValue
        ) ?? .auto
    }

    /// Returns false only when the commit gate declined, so joiners rerun (see
    /// `runPatternAnalysis`); every other outcome counts as completed.
    private func performPatternAnalysis(container: ModelContainer, trigger: PatternAnalysisTrigger) async -> Bool {
        let lastRun = UserDefaults.standard.object(forKey: Self.lastPatternAnalysisKey) as? Date
        guard Self.shouldRunPatternAnalysis(lastRun: lastRun, trigger: trigger) else { return true }
        patternAnalysisError = nil
        let backfillGenerationAtStart = scoreBackfillGeneration
        patternRunGeneration += 1
        let runGeneration = patternRunGeneration

        // The throttle is stamped AFTER a run that actually reached upsertPatterns —
        // never before. `analyze()` refreshes every pattern's `detectedAt`, which is
        // the only thing keeping `TrainingPattern.isActive` true. Stamping up front
        // meant a run that bailed early (this `.task` cancelled by a tab swipe, a
        // HealthKit failure, a persistence throw) burned the whole 7-day window
        // without refreshing anything — so every pattern surface, including the
        // hrvPrecursor illness alarm on Coach, went dark until the next forced run.
        if trainingDNAAnalyzer == nil {
            trainingDNAAnalyzer = TrainingDNAAnalyzer(modelContainer: container)
        }

        let analyzer = trainingDNAAnalyzer!
        let preference = hrvSourcePreference
        // Same abandon rule as the background pass: a run the user left mid-detection can be
        // suspended and resumed hours later by a delivery wake, mixing reads from both
        // moments. Past `BackgroundPatternPass.maxDuration` it commits nothing, sends no
        // alert and stays unstamped.
        let startedAt = Date()

        do {
            let historyDays = try await analyzer.analyze(
                sourcePreference: preference,
                commitGate: { BackgroundPatternPass.isWithinBudget(startedAt: startedAt, now: Date()) }
            )
            UserDefaults.standard.set(historyDays, forKey: "healthKitHistoryDays")
            // `analyze()` returns normally when cancelled (its guards `return historyDays`),
            // so a clean return is NOT proof the patterns were refreshed. Callers can no
            // longer cancel this task (it belongs to the flight), but check anyway.
            if !Task.isCancelled {
                // A backfill that added rows mid-run changed what the detectors should have
                // seen: leave the throttle unstamped so the next trigger runs again.
                if scoreBackfillGeneration == backfillGenerationAtStart {
                    UserDefaults.standard.set(Date(), forKey: Self.lastPatternAnalysisKey)
                }
                // The Coach paragraph bakes in the active pattern set. A run that
                // detected or expired a pattern must re-check the cache now, or a
                // launch-time analysis that finished after the coach read leaves
                // Coach behind Patterns until the next unrelated refresh. No-op when
                // the set is unchanged; coalesces if an analysis is in flight. Skipped when
                // the app is in the background, where the refresh budget can't fit it.
                if isAppInForeground() {
                    await refreshIfNecessary(modelContext: container.mainContext)
                }
            }
        } catch PatternAnalysisError.commitDeclined {
            // Spanned a suspension: silent and unstamped, and joiners rerun.
            #if DEBUG
            print("⚠️ Pattern analysis spanned a suspension; nothing committed")
            #endif
            return false
        } catch PatternAnalysisError.insufficientData {
            // < 60 days of history — silent, no error surfaced. Safe to throttle: there
            // are no patterns to keep alive, so nothing can go stale behind the window.
            UserDefaults.standard.set(Date(), forKey: Self.lastPatternAnalysisKey)
        } catch {
            // Deliberately NOT stamping — a failed run must be retried on next appear,
            // not locked out for a week.
            if !isAppInForeground() || Self.isLockedDeviceError(error) {
                #if DEBUG
                print("⚠️ Pattern analysis failed silently: \(error)")
                #endif
            } else {
                await MainActor.run {
                    if self.patternRunGeneration == runGeneration {
                        self.patternAnalysisError = "Pattern analysis failed: \(error.localizedDescription)"
                    }
                }
            }
        }
        return true
    }
    
    // MARK: - Models

    /// One day in the 7-day plan: the hardest effort the rider can absorb, and why when it isn't obvious.
    struct ReadinessForecastDay: Identifiable {
        let id = UUID()
        let date: Date
        let effort: ForecastEffort
        let reason: String?

        /// The label `MasterCoachEngine.StateVector.nextDayForecast` reads.
        var coaching: String { effort.label }
    }

    /// Forecast effort tiers, ordered least → most restrictive so two independent
    /// verdicts (what recovery allows, what training load allows) can be combined
    /// with `max` — the more restrictive one wins.
    enum ForecastEffort: Int, Comparable {
        case hard = 0
        case moderate = 1
        case easy = 2
        case rest = 3

        static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

        /// `MasterCoachEngine` reads the label text.
        var label: String {
            switch self {
            case .hard:     return "Hard effort OK"
            case .moderate: return "Moderate training"
            case .easy:     return "Easy only"
            case .rest:     return "Rest recommended"
            }
        }
    }

    struct UnifiedReadiness {
        let score: Int
        let morningScore: Int
        let level: ReadinessLevel
        let recommendation: DailyRecommendationService.DailyRecommendation
        let injuryRisk: InjuryRiskCalculator.InjuryRiskAssessment
        let breakdown: ReadinessAnalyzer.ScoreBreakdown
        let trend: ReadinessAnalyzer.ReadinessScore.Trend
        let date: Date
        let intraDay: RecoveryDecayService.IntraDayReadiness

        // RECONCILED MESSAGE: The single "Master Coach" advice
        let coachAdvice: String

        /// Overnight recovery rate multiplier derived from yesterday's combined load.
        /// Passed to EnergyBankChart so the projected curve reflects the same rate used for today's score.
        let overnightRecoveryMultiplier: Double

        /// TSS-equivalent load from today's excess steps (above personal 30-day baseline).
        /// Capped at 20% of today's workout TSS. Passed to EnergyBankChart for consistent curve rendering.
        let todayStepExcessTSS: Double

        // Training load & zone outputs (moved from ReadinessViewModel per GEMINI.md mandate)
        let primaryActivity: String
        let trainingLoadSummary: TrainingLoadCalculator.TrainingLoadSummary?
        let readinessAssessment: PredictiveReadinessService.ReadinessAssessment?
        let acwrTrend: [ACWRDataPoint]
        let loadVisualization: TrainingLoadVisualizationService.LoadVisualizationData?

        // Phase 4: Smart Routing Activity Readiness
        let activityReadiness: [String: Int]?

        // Insights sub-service outputs (moved from InsightsViewModel per GEMINI.md mandate)
        let metricTrends: [MetricTrend]
        let sleepPerformanceInsight: CorrelationEngine.SleepPerformanceInsight?
        let activityTypeInsights: [CorrelationEngine.ActivityTypeInsight]
        let dataSummary: [(activityType: String, goodSleep: Int, poorSleep: Int)]
        let simpleInsights: [CorrelationEngine.SimpleInsight]
        let hrvPerformanceInsights: [CorrelationEngine.HRVPerformanceInsight]
        let proteinRecoveryInsight: NutritionCorrelationEngine.ProteinRecoveryInsight?
        let proteinPerformanceInsights: [NutritionCorrelationEngine.ProteinPerformanceInsight]
        let carbPerformanceInsights: [NutritionCorrelationEngine.CarbPerformanceInsight]
        let recommendations: [ActionableRecommendations.Recommendation]
        let agingAssessment: BiologicalAgingService.AgingAssessment?
        let compoundScoreAnalysis: CyclingPowerAnalyzer.CompoundScoreAnalysis?

        // Per-tab outputs (moved from ReadinessViewModel + DashboardViewModel — Phase 1.2)
        let todayWorkouts: [WorkoutData]
        let todaySteps: Int
        let cardiovascularStrain: CardiovascularStrainService.Result?
        let holisticMetrics: HealthMetrics?

        // Raw chart-source arrays (consumed by view-derivation logic that depends on selectedPeriod)
        let hrvData: [HealthDataPoint]
        let rhrData: [HealthDataPoint]
        let sleepData: [HealthDataPoint]
        let stepCountData: [HealthDataPoint]
        let workouts: [WorkoutData]
        let weightData: [HealthDataPoint]
    }
    
    // MARK: - Main Analysis Entry Point
    
    func refreshIfNecessary(modelContext: ModelContext) async {
        // Backfill StoredDailyScore from HealthKit history on first launch.
        await backfillHistoricalScores(modelContext: modelContext)
        // One-time migration: populate dailyLoad on existing rows (default was 0.0 from schema add).
        backfillDailyLoad(modelContext: modelContext)

        // 1. Calculate current data fingerprint
        guard let fingerprint = try? calculateFingerprint(context: modelContext) else { return }
        
        // 2. Check if we can skip (same data, same day, same active patterns)
        if currentReadiness != nil,
           Self.canReuseCachedAnalysis(
               lastAnalysisDate: lastAnalysisDate,
               fingerprint: fingerprint,
               lastFingerprint: lastFingerprint,
               activePatternTypes: fetchActivePatternTypes(context: modelContext),
               lastActivePatternTypes: lastActivePatternTypes,
               illnessState: fetchIllnessState(context: modelContext),
               lastIllnessState: lastIllnessState,
               activeMemoryIDs: fetchActiveMemoryIDs(context: modelContext),
               lastActiveMemoryIDs: lastActiveMemoryIDs,
               forecastSignature: forecastInputSignature(context: modelContext),
               lastForecastSignature: lastForecastSignature,
               maxAge: Self.forecastLiveRefreshInterval
           ) {
            #if DEBUG
            print("✅ ReadinessRepository: Using cached unified analysis")
            #endif
            return
        }
        
        await runShieldedAnalysis(modelContext: modelContext, fingerprint: fingerprint)
    }
    
    func forceRefresh(modelContext: ModelContext) async {
        guard let fingerprint = try? calculateFingerprint(context: modelContext) else { return }
        await runShieldedAnalysis(modelContext: modelContext, fingerprint: fingerprint)
    }

    /// Every caller is a view `.task` / `.refreshable` or an app lifecycle task, and any
    /// of them can be cancelled mid-run. A cancelled run used to make MasterCoachEngine's
    /// LLM call throw, fall back to the heuristic paragraph, and cache that for the rest
    /// of the day. The analysis now runs to completion regardless of who asked.
    private func runShieldedAnalysis(modelContext: ModelContext, fingerprint: PredictionCache.DataFingerprint) async {
        await SingleFlight.shielded { [self] in
            await performFullAnalysis(modelContext: modelContext, fingerprint: fingerprint)
        }
    }
    
    // MARK: - Core Analysis Logic
    
    private func performFullAnalysis(modelContext: ModelContext, fingerprint: PredictionCache.DataFingerprint) async {
        // Re-entrancy guard: multiple views call refreshIfNecessary simultaneously on first load.
        // All pass the currentReadiness == nil check before any run sets it — without this guard
        // all three enter here concurrently, producing interleaved SwiftData writes.
        //
        // A run takes a long time (ML training, MasterCoachEngine, HealthKit reads), and a
        // workout finishing sync lands squarely inside that window. Dropping the request
        // outright left the published snapshot describing pre-ride data — the Load tab kept
        // showing yesterday's ACWR until some unrelated trigger happened along. Record the
        // request instead and re-check once this run finishes.
        guard !isAnalyzing else {
            pendingRefreshRequested = true
            #if DEBUG
            print("⏳ ReadinessRepository: refresh requested mid-analysis — queued")
            #endif
            return
        }
        isAnalyzing = true
        analysisError = nil

        #if DEBUG
        print("🔄 ReadinessRepository: Starting unified analysis...")
        #endif

        do {
            // 1. Fetch data with STABLE calendar windows
            let calendar = Calendar.current
            let now = Date()
            let today = calendar.startOfDay(for: now)
            let baselineStart = calendar.date(byAdding: .day, value: -90, to: today)!
            // The 90-day ACWR history chart needs a 28-day chronic lead-in before
            // its first plotted day (day D's ACWR windows [D-28, D]). Fetch workouts
            // 118 days back for the visualization so, after the cold-start trim,
            // the chart fills a full 90 days instead of 62. Metrics/nutrition stay
            // at 90 — widening those would shift readiness baselines elsewhere.
            let loadHistoryStart = calendar.date(byAdding: .day, value: -118, to: today)!

            let workoutDescriptor = FetchDescriptor<StoredWorkout>(
                predicate: #Predicate { $0.startDate >= baselineStart },
                sortBy: [SortDescriptor(\.startDate)]
            )
            let loadHistoryWorkoutDescriptor = FetchDescriptor<StoredWorkout>(
                predicate: #Predicate { $0.startDate >= loadHistoryStart },
                sortBy: [SortDescriptor(\.startDate)]
            )
            let metricDescriptor = FetchDescriptor<StoredHealthMetric>(
                predicate: #Predicate { $0.date >= baselineStart },
                sortBy: [SortDescriptor(\.date)]
            )
            let nutritionDescriptor = FetchDescriptor<StoredNutrition>(
                predicate: #Predicate { $0.date >= baselineStart },
                sortBy: [SortDescriptor(\.date)]
            )

            let storedWorkouts = try modelContext.fetch(workoutDescriptor)
            let loadHistoryWorkouts = (try? modelContext.fetch(loadHistoryWorkoutDescriptor))?
                .map { WorkoutData(from: $0) } ?? []
            let storedMetrics = try modelContext.fetch(metricDescriptor)
            let storedNutrition = try modelContext.fetch(nutritionDescriptor)
            let intentLabels = try modelContext.fetch(FetchDescriptor<StoredIntentLabel>())

            // Convert data
            let workouts = storedWorkouts.map { WorkoutData(from: $0) }
            let nutrition = storedNutrition.map { DailyNutrition(from: $0) }
            let hrvData = storedMetrics.filter { $0.type == "HRV" }.map { HealthDataPoint(date: $0.date, value: $0.value) }
            let rhrData = storedMetrics.filter { $0.type == "RHR" }.map { HealthDataPoint(date: $0.date, value: $0.value) }
            let sleepData  = storedMetrics.filter { $0.type == "Sleep"  }.map { HealthDataPoint(date: $0.date, value: $0.value) }
            let stepData   = storedMetrics.filter { $0.type == "Steps"  }.map { HealthDataPoint(date: $0.date, value: $0.value) }
            let vo2maxData   = storedMetrics.filter { $0.type == "VO2max"  }.map { HealthDataPoint(date: $0.date, value: $0.value) }
            let weightData   = storedMetrics.filter { $0.type == "Weight" }.map { HealthDataPoint(date: $0.date, value: $0.value) }

            // 2. Run Individual Services
            // A: Base Readiness Score
            guard let baseReadiness = readinessAnalyzer.analyzeReadiness(
                restingHR: rhrData,
                hrv: hrvData,
                sleep: sleepData,
                workouts: workouts,
                stravaActivities: [],
                nutrition: []
            ) else {
                throw NSError(domain: "ReadinessRepository", code: 1, userInfo: [NSLocalizedDescriptionKey: "Insufficient data"])
            }

            // Fetch FTP snapshot history once — passed to every load calculation so that
            // each workout is evaluated against the FTP that was in effect on its date.
            let ftpSnapshots = (try? modelContext.fetch(FetchDescriptor<StoredFTPSnapshot>())) ?? []

            // B: Injury Risk
            let trainingLoad = loadCalculator.calculateTrainingLoad(
                healthKitWorkouts: workouts,
                stravaActivities: [],
                stepData: [],
                ftpSnapshots: ftpSnapshots
            )

            let trends = trendDetector.detectTrends(
                restingHRData: rhrData,
                hrvData: hrvData,
                sleepData: sleepData,
                stepData: stepData,
                weightData: weightData,
                workouts: workouts
            )

            let riskAssessment = riskCalculator.assessInjuryRisk(
                trainingLoad: trainingLoad,
                recoveryStatus: [],
                trends: trends
            )

            // C: HRV-Guided Recommendation
            guard let hrvRec = recommendationService.generateDailyRecommendation(
                hrvData: hrvData,
                sleepData: sleepData,
                rhrData: rhrData,
                workouts: workouts,
                readinessScore: baseReadiness.score
            ) else {
                throw NSError(domain: "ReadinessRepository", code: 2, userInfo: [NSLocalizedDescriptionKey: "Recommendation failed"])
            }

            // 3. THE MASTER COACH: Reconcile Advice
            let reconciledAdvice = reconcileAdvice(
                readiness: baseReadiness,
                risk: riskAssessment,
                hrvRec: hrvRec
            )

            let reconciledRecommendation = DailyRecommendationService.DailyRecommendation(
                status: hrvRec.status,
                headline: (riskAssessment.riskLevel == .high || riskAssessment.riskLevel == .veryHigh) ? "RESTRICTED: " + hrvRec.headline : hrvRec.headline,
                guidance: reconciledAdvice,
                targetZones: hrvRec.targetZones,
                avoidZones: hrvRec.avoidZones,
                confidence: hrvRec.confidence,
                reasoning: hrvRec.reasoning
            )

            // 4. Intra-Day Recovery Decay (Dynamic Score)
            // Carry-forward: fatigueScore of 30 = no debt; less than 30 = points suppressed by prior strain.
            let priorDayFatigueImpact = Double(30 - baseReadiness.breakdown.fatigueScore)

            // Mechanism 2 (NEAT): yesterday's combined load (workout + step excess) may impair
            // overnight recovery, slowing how quickly prior-day fatigue resolves today.
            let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
            let yesterdayWorkouts = workouts.filter { calendar.isDate($0.startDate, inSameDayAs: yesterday) }
            let yesterdayWorkoutTSS = yesterdayWorkouts.reduce(0.0) { $0 + loadCalculator.calculateWorkoutLoad($1) }
            let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: today)!
            let recentSteps = stepData.filter { $0.date >= thirtyDaysAgo && $0.date < today }
            let stepBaseline: Double = recentSteps.isEmpty ? 5000 : recentSteps.map(\.value).reduce(0, +) / Double(recentSteps.count)
            let yesterdayStepCount = stepData.first(where: { calendar.isDate($0.date, inSameDayAs: yesterday) })?.value ?? 0
            let yesterdayStepExcess = max(0, yesterdayStepCount - stepBaseline)
            // Rest-day cap: 2.0 TSS absolute ceiling when no workout — steps are supporting load, not primary stress.
            let cap = yesterdayWorkoutTSS > 0 ? yesterdayWorkoutTSS * 0.20 : 2.0
            let yesterdayStepExcessTSS = min(yesterdayStepExcess / 3000.0, cap)
            let recoveryMultiplier = RecoveryDecayService.overnightRecoveryMultiplier(
                workoutTSS: yesterdayWorkoutTSS,
                stepExcessTSS: yesterdayStepExcessTSS
            )

            // Mechanism 1 (NEAT): today's excess steps above personal baseline add to intra-day strain.
            // 3000 steps ≈ 1.0 TSS; capped at 20% of today's total workout TSS.
            // Rest-day cap: 2.0 TSS absolute ceiling — steps are supporting load, not primary stress.
            let todayStepCount = stepData.first(where: { calendar.isDate($0.date, inSameDayAs: today) })?.value ?? 0
            let todayStepExcess = max(0, todayStepCount - stepBaseline)
            let todayWorkoutTSS = workouts
                .filter { calendar.isDate($0.startDate, inSameDayAs: today) }
                .reduce(0.0) { $0 + loadCalculator.calculateWorkoutLoad($1) }
            let todayStepCap = todayWorkoutTSS > 0 ? todayWorkoutTSS * 0.20 : 2.0
            let todayStepExcessTSS = min(todayStepExcess / 3000.0, todayStepCap)

            let intraDay = recoveryService.calculateIntraDayReadiness(
                baselineScore: baseReadiness.score,
                todayWorkouts: workouts,
                priorDayFatigueImpact: max(0, priorDayFatigueImpact),
                todayStepExcessTSS: todayStepExcessTSS,
                overnightRecoveryMultiplier: recoveryMultiplier
            )

            // 5. Load assessment
            let primaryActivity = determinePrimaryActivity(from: workouts)

            let readinessAssessmentResult = predictiveReadinessService.calculateReadiness(
                stravaActivities: [],
                healthKitWorkouts: workouts,
                ftpSnapshots: ftpSnapshots
            )

            // 6. Recovery, load and trend analysis
            let recoveryInsights = correlationEngineRepo.analyzeRecoveryStatus(
                restingHRData: rhrData,
                hrvData: hrvData
            )
            
            let storedDailyScores = (try? modelContext.fetch(FetchDescriptor<StoredDailyScore>())) ?? []
            let dailyReadinessDict = storedDailyScores.reduce(into: [Date: Int]()) { result, score in
                let day = calendar.startOfDay(for: score.date)
                result[day] = score.readinessScore
            }
            
            let trainingLoadSummary = loadCalculator.calculateTrainingLoad(
                healthKitWorkouts: workouts,
                stravaActivities: [],
                stepData: stepData,
                recoveryInsights: recoveryInsights,
                dailyReadiness: dailyReadinessDict,
                ftpSnapshots: ftpSnapshots
            )

            let acwrTrend = calculateImprovedACWRTrend(workouts: workouts, ftpSnapshots: ftpSnapshots)

            let loadVisualization = loadVizService.generateLoadVisualization(
                workouts: loadHistoryWorkouts,
                labels: intentLabels,
                ftpSnapshots: ftpSnapshots,
                daysBack: 90
            )

            // 8. Insights Sub-services (moved from InsightsViewModel per GEMINI.md mandate)
            let sleepPerformanceInsight = correlationEngineRepo.analyzeSleepVsPerformanceCombined(
                sleepData: sleepData, healthKitWorkouts: workouts, stravaActivities: []
            )
            let activityTypeInsights = correlationEngineRepo.analyzeSleepVsPerformanceByActivityType(
                sleepData: sleepData, healthKitWorkouts: workouts, stravaActivities: []
            )
            let insightDataSummary = correlationEngineRepo.getDataSummary(
                sleepData: sleepData, healthKitWorkouts: workouts, stravaActivities: []
            )
            let simpleInsights = correlationEngineRepo.generateSimpleInsights(
                sleepData: sleepData, healthKitWorkouts: workouts, stravaActivities: [],
                restingHRData: rhrData, hrvData: hrvData
            )
            let hrvPerformanceInsights = correlationEngineRepo.analyzeHRVVsPerformance(
                hrvData: hrvData, healthKitWorkouts: workouts, stravaActivities: []
            )
            let proteinRecoveryInsight = nutritionEngine.analyzeProteinVsRecovery(
                nutritionData: nutrition, restingHRData: rhrData, hrvData: hrvData
            )
            let proteinPerformanceInsights = nutritionEngine.analyzeProteinVsPerformance(
                nutritionData: nutrition, healthKitWorkouts: workouts, stravaActivities: []
            )
            let carbPerformanceInsights = nutritionEngine.analyzeCarbsVsPerformance(
                nutritionData: nutrition, healthKitWorkouts: workouts, stravaActivities: []
            )
            let insightsRecommendations = actionableRecommendations.generateRecommendations(
                trainingLoad: trainingLoadSummary,
                recoveryInsights: recoveryInsights,
                trends: trends,
                injuryRisk: riskAssessment
            )
            let agingAssessment = await agingService.calculateAgingAlpha(modelContext: modelContext)
            
            let powerAnalysis = await cyclingPowerAnalyzer.analyzeCompoundScore(
                workouts: workouts,
                weightData: weightData
            )

            // 9. Generate Master Coach Message
            // Read here rather than through the helpers: a failed read must not build a plan with
            // no Injury or HRV limits, so buildForecast below refuses and the last plan stays.
            let patternsRead = try? modelContext.fetch(FetchDescriptor<TrainingPattern>())
            let activePatternTypes = Set((patternsRead ?? []).filter(\.isActive).map(\.patternType))
            let illnessState = fetchIllnessState(context: modelContext)

            let memoriesRead = try? modelContext.fetch(FetchDescriptor<CoachMemoryNote>())
            let allMemories = memoriesRead ?? []
            // Taken once, before synthesis: a note expiring mid-run must not leave the cache
            // key without a note the paragraph still mentions.
            let activeMemoryIDs = Set(allMemories.filter(\.isCurrentlyActive).map(\.id))

            // Tomorrow starts from a score that ignores today's rides, because `baseReadiness.score`
            // reads them through the ACR bracket and the plan already counts them by their load.
            let forecastStartScore = readinessAnalyzer.analyzeReadiness(
                restingHR: rhrData,
                hrv: hrvData,
                sleep: sleepData,
                workouts: workouts.filter { $0.startDate < today },
                stravaActivities: [],
                nutrition: []
            )?.score ?? baseReadiness.score
            let forecastIllness = forecastIllness(state: illnessState, context: modelContext, now: now)
            let forecastSignature = forecastInputSignature(context: modelContext, now: now)
            func buildForecast() -> Result<ForecastPlan?, Error> {
                Result {
                    guard patternsRead != nil, memoriesRead != nil else { throw ForecastInputReadFailed() }
                    return try computeForecastPlan(
                        modelContext: modelContext,
                        startScore: forecastStartScore,
                        currentScore: Self.forecastTodayScore(
                            startScore: forecastStartScore,
                            workouts: workouts,
                            stepExcessTSS: todayStepExcessTSS,
                            now: now
                        ),
                        illness: forecastIllness,
                        activePatterns: activePatternTypes,
                        memories: allMemories,
                        injuryRisk: riskAssessment.riskLevel,
                        sleep: sleepData,
                        now: now
                    )
                }
            }
            let forecastRead = buildForecast()
            let computedForecast = Self.forecastAfterRead(forecastRead.map { $0?.days }, last: self.forecast, now: now)

            let coachState = Self.coachState(
                plan: computedForecast,
                profile: (try? forecastRead.get())??.profile,
                startScore: forecastStartScore,
                morningScore: baseReadiness.score,
                currentScore: intraDay.currentScore,
                acwr: readinessAssessmentResult.acwr,
                injuryRisk: riskAssessment.riskLevel,
                activePatterns: activePatternTypes,
                memories: allMemories,
                illness: illnessState,
                now: now
            )
            let masterCoachMessage = await MasterCoachEngine.generateMessage(state: coachState)
            
            // Phase 4: Smart Routing Activity Readiness
            let activityReadinessScores = SmartRoutingEngine.generateActivityReadiness(baseScore: intraDay.currentScore, memories: allMemories)

            // Per-tab outputs (Phase 1.2)
            let todayWorkouts = workouts.filter { calendar.isDate($0.startDate, inSameDayAs: today) }
            let todayStepsValue = stepData
                .filter { calendar.isDate($0.date, inSameDayAs: today) }
                .map(\.value)
                .reduce(0, +)
            let todaySteps = Int(todayStepsValue)
            let cardiovascularStrain = await computeCardiovascularStrain(rhrData: rhrData)
            let holisticMetrics = buildHolisticMetrics(
                workouts: workouts,
                stepData: stepData,
                hrvData: hrvData,
                sleepData: sleepData,
                trainingLoad: trainingLoad,
                readinessScore: baseReadiness.score
            )

            // 10. Update Published State
            self.currentReadiness = UnifiedReadiness(
                score: intraDay.currentScore,
                morningScore: baseReadiness.score,
                level: mapScoreToLevel(intraDay.currentScore),
                recommendation: reconciledRecommendation,
                injuryRisk: riskAssessment,
                breakdown: baseReadiness.breakdown,
                trend: baseReadiness.trend,
                date: now,
                intraDay: intraDay,
                coachAdvice: masterCoachMessage,
                overnightRecoveryMultiplier: recoveryMultiplier,
                todayStepExcessTSS: todayStepExcessTSS,
                primaryActivity: primaryActivity,
                trainingLoadSummary: trainingLoadSummary,
                readinessAssessment: readinessAssessmentResult,
                acwrTrend: acwrTrend,
                loadVisualization: loadVisualization,
                activityReadiness: activityReadinessScores,
                metricTrends: trends,
                sleepPerformanceInsight: sleepPerformanceInsight,
                activityTypeInsights: activityTypeInsights,
                dataSummary: insightDataSummary,
                simpleInsights: simpleInsights,
                hrvPerformanceInsights: hrvPerformanceInsights,
                proteinRecoveryInsight: proteinRecoveryInsight,
                proteinPerformanceInsights: proteinPerformanceInsights,
                carbPerformanceInsights: carbPerformanceInsights,
                recommendations: insightsRecommendations,
                agingAssessment: agingAssessment,
                compoundScoreAnalysis: powerAnalysis,
                todayWorkouts: todayWorkouts,
                todaySteps: todaySteps,
                cardiovascularStrain: cardiovascularStrain,
                holisticMetrics: holisticMetrics,
                hrvData: hrvData,
                rhrData: rhrData,
                sleepData: sleepData,
                stepCountData: stepData,
                workouts: workouts,
                weightData: weightData
            )

            self.intraDayReadiness = intraDay
            self.lastFingerprint = fingerprint
            self.lastAnalysisDate = now
            self.lastActivePatternTypes = activePatternTypes
            self.lastIllnessState = illnessState
            self.lastActiveMemoryIDs = activeMemoryIDs
            self.lastForecastSignature = forecastSignature

            // Persist today's readiness score for 90-day back-to-back crash pattern detection.
            let todayWorkoutsForLoad = workouts.filter { calendar.isDate($0.startDate, inSameDayAs: today) }
            let ftpSnapshotsForLoad = (try? modelContext.fetch(FetchDescriptor<StoredFTPSnapshot>())) ?? []
            let todayTotalLoad = todayWorkoutsForLoad.reduce(0.0) {
                $0 + predictiveReadinessService.calculateWorkoutLoad($1, ftpSnapshots: ftpSnapshotsForLoad)
            }
            upsertDailyScore(
                date: today,
                score: baseReadiness.score,
                acwr: readinessAssessmentResult.acwr,
                workoutCount: todayWorkoutsForLoad.count,
                dailyLoad: todayTotalLoad,
                modelContext: modelContext
            )

            // 7-day plan (requires 14 days of stored scores).
            // If nil, force a HealthKit backfill to fill any gaps and retry once.
            if let f = computedForecast {
                self.forecast = f
            } else {
                var readFailed = false
                if case .failure = forecastRead { readFailed = true }
                if Self.shouldForceScoreBackfill(lastAttempt: lastForcedBackfillDate, readFailed: readFailed, now: now) {
                    lastForcedBackfillDate = now
                    await backfillHistoricalScores(modelContext: modelContext, force: true)
                    self.forecast = Self.forecastAfterRead(buildForecast().map { $0?.days }, last: self.forecast, now: now)
                } else {
                    self.forecast = nil
                }
            }

            #if DEBUG
            print("✅ ReadinessRepository: Unified Analysis Complete. Score: \(baseReadiness.score)")
            #endif

        } catch {
            #if DEBUG
            print("❌ ReadinessRepository Error: \(error)")
            #endif
            analysisError = error.localizedDescription
        }

        isAnalyzing = false

        // Data changed while we were working — re-run against it. refreshIfNecessary
        // recomputes the fingerprint, so this is a no-op unless the store actually
        // moved, which bounds the recursion to real changes.
        if pendingRefreshRequested {
            pendingRefreshRequested = false
            await refreshIfNecessary(modelContext: modelContext)
        }
    }

    // MARK: - Daily Score Persistence

    /// Upserts today's readiness score into StoredDailyScore for 90-day pattern analysis.
    /// Dedup is in-memory (dateString equality) — avoids @Attribute(.unique) migration risk.
    private func upsertDailyScore(
        date: Date,
        score: Int,
        acwr: Double,
        workoutCount: Int,
        dailyLoad: Double,
        modelContext: ModelContext
    ) {
        let dateStr = Self.dailyScoreDateFormatter.string(from: date)

        // Fetch only today's record via predicate rather than all records.
        let predicate = #Predicate<StoredDailyScore> { $0.dateString == dateStr }
        let todayScores = (try? modelContext.fetch(FetchDescriptor(predicate: predicate))) ?? []
        if let existing = todayScores.first {
            existing.readinessScore = score
            existing.dailyStrain = acwr
            existing.workoutCount = workoutCount
            existing.dailyLoad = dailyLoad
        } else {
            let record = StoredDailyScore(
                date: date,
                readinessScore: score,
                dailyStrain: acwr,
                workoutCount: workoutCount,
                dailyLoad: dailyLoad
            )
            modelContext.insert(record)
        }
        try? modelContext.save()
    }

    // MARK: - Recent Daily Load Recompute

    /// How many complete days before today get their load recomputed after a sync.
    nonisolated static let dailyLoadRecomputeDays = 7

    /// A day's `dailyLoad` and `workoutCount` were fixed at its last write (often mid-day), so a
    /// ride synced later (an evening ride synced next morning, a backdated upload) never counted,
    /// and a ride removed from the store kept its load. Recomputes both for the EXISTING rows of
    /// the last `days` complete days from the stored workouts. Rows are found by `dateString`
    /// (a stored `date` can drift across midnight when travelling); a row is written only when
    /// its load moves by more than 0.01 or its count changes; every row for the day is written,
    /// duplicates included. Never touches `readinessScore` or
    /// `dailyStrain`, never creates a row, never touches today (analysis rewrites it). The caller
    /// runs it only when `SyncManager.mayRecomputeDailyLoads`. Returns how many rows changed.
    @discardableResult
    static func recomputeRecentDailyLoads(context: ModelContext, now: Date, days: Int = dailyLoadRecomputeDays,
                                          calendar: Calendar = .current,
                                          load: (StoredWorkout) -> Double) -> Int {
        let today = calendar.startOfDay(for: now)
        var changed = 0
        for back in 1...max(1, days) {
            guard let dayStart = calendar.date(byAdding: .day, value: -back, to: today),
                  let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { continue }
            let dateStr = dailyScoreDateFormatter.string(from: dayStart)
            // Every row for the day: detectors read a day's highest row, so a twin left at the
            // old load would hide a removed ride.
            // A failed fetch skips the day: read as "no rides" it would save zero load.
            guard let rows = try? context.fetch(FetchDescriptor<StoredDailyScore>(
                predicate: #Predicate { $0.dateString == dateStr }
            )), !rows.isEmpty,
                  let workouts = try? context.fetch(FetchDescriptor<StoredWorkout>(
                predicate: #Predicate { $0.startDate >= dayStart && $0.startDate < dayEnd },
                sortBy: [SortDescriptor(\.startDate)]
            )) else { continue }
            let dayLoad = workouts.reduce(0.0) { $0 + load($1) }
            for row in rows where abs(row.dailyLoad - dayLoad) > 0.01 || row.workoutCount != workouts.count {
                row.dailyLoad = dayLoad
                row.workoutCount = workouts.count
                changed += 1
            }
        }
        if changed > 0 { try? context.save() }
        return changed
    }

    /// After a foreground sync or zone backfill, when `SyncManager.mayRecomputeDailyLoads` (never
    /// on a reset's post or after a sync whose HealthKit fetch failed): the stored workouts may
    /// have gained, lost or re-zoned rides for recent days.
    func recomputeRecentDailyLoads(modelContext: ModelContext) {
        // A failed read must not become "no FTP history": rides without zones would be re-scored
        // at today's FTP. Skip; the next good sync recomputes.
        guard let ftpSnapshots = try? modelContext.fetch(FetchDescriptor<StoredFTPSnapshot>()) else { return }
        let changed = Self.recomputeRecentDailyLoads(context: modelContext, now: Date()) { [predictiveReadinessService] in
            predictiveReadinessService.calculateWorkoutLoad(WorkoutData(from: $0), ftpSnapshots: ftpSnapshots)
        }
        #if DEBUG
        if changed > 0 { print("📈 Recomputed load for \(changed) recent day(s)") }
        #endif
    }

    // MARK: - Historical Score Backfill

    /// Populates StoredDailyScore for the last 90 days from already-synced SwiftData records.
    /// Runs once on first launch (UserDefaults gate) and re-runs whenever fewer than 14 records
    /// exist (e.g. after a data clear). This unlocks the 7-day forecast and 14-Day Signature
    /// without requiring 14 consecutive days of app opens.
    private func backfillHistoricalScores(modelContext: ModelContext, force: Bool = false) async {
        // V5: diagnose existingDates vs per-day filter failure.
        let udKey = "historicalScoreBackfillV5Done"
        let existingCount = (try? modelContext.fetchCount(FetchDescriptor<StoredDailyScore>())) ?? 0

        // Re-run if there are gap days since the last stored score — covers the case where
        // the user doesn't open the app every day and recent history has holes.
        let hasRecentGap: Bool = {
            let cal = Calendar.current
            let yday = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: Date())) ?? Date()
            let allScores = (try? modelContext.fetch(FetchDescriptor<StoredDailyScore>())) ?? []
            guard let lastDate = allScores.map({ cal.startOfDay(for: $0.date) }).max() else { return true }
            return (cal.dateComponents([.day], from: lastDate, to: yday).day ?? 0) >= 1
        }()

        guard force || !UserDefaults.standard.bool(forKey: udKey) || existingCount < 14 || hasRecentGap else { return }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let ninetyDaysAgo  = calendar.date(byAdding: .day, value: -90, to: today),
              let yesterday       = calendar.date(byAdding: .day, value:  -1, to: today),
              let fetchStart      = calendar.date(byAdding: .day, value: -28, to: ninetyDaysAgo)
        else { return }

        let hk = HealthKitManager.shared

        // Pull 90+28 days of biometrics straight from HealthKit — this is the only source
        // that has historical data predating the app install.
        async let rhrFetch  = try? hk.fetchRestingHeartRate(startDate: fetchStart, endDate: today)
        async let hrvFetch  = try? hk.fetchHeartRateVariability(startDate: fetchStart, endDate: today)
        async let sleepFetch = try? hk.fetchSleepDuration(startDate: fetchStart, endDate: today)
        async let hkWorkoutFetch = try? hk.fetchWorkouts(startDate: fetchStart, endDate: today)

        let (allRHR, allHRV, allSleep, hkWorkouts) = await (
            rhrFetch ?? [],
            hrvFetch ?? [],
            sleepFetch ?? [],
            hkWorkoutFetch ?? []
        )


        // Workouts: merge HealthKit history with StoredWorkout (has Strava power data).
        // StoredWorkout wins on overlap via date-key dedup so zone-weighted loads are preserved.
        let workoutDescriptor = FetchDescriptor<StoredWorkout>(
            predicate: #Predicate { $0.startDate >= fetchStart },
            sortBy: [SortDescriptor(\.startDate)]
        )
        let storedWorkouts = (try? modelContext.fetch(workoutDescriptor)) ?? []
        let ftpSnapshots   = (try? modelContext.fetch(FetchDescriptor<StoredFTPSnapshot>())) ?? []

        // Build a merged workout list: prefer StoredWorkout (richer data), fill gaps from HK.
        let storedWorkoutDates = Set(storedWorkouts.map { calendar.startOfDay(for: $0.startDate) })
        let hkOnlyWorkouts = hkWorkouts.filter { !storedWorkoutDates.contains(calendar.startOfDay(for: $0.startDate)) }
        let allWorkouts = storedWorkouts.map { WorkoutData(from: $0) } + hkOnlyWorkouts

        // Skip dates that already have a StoredDailyScore.
        let allExisting  = (try? modelContext.fetch(FetchDescriptor<StoredDailyScore>())) ?? []
        let existingDates = Set(allExisting.map { $0.dateString })

        let formatter = Self.dailyScoreDateFormatter
        var inserted = 0

        var day = ninetyDaysAgo
        while day <= yesterday {
            let dateStr = formatter.string(from: day)
            defer { day = calendar.date(byAdding: .day, value: 1, to: day) ?? today }

            guard !existingDates.contains(dateStr) else { continue }

            guard let dayEnd          = calendar.date(byAdding: .day, value:  1, to: day),
                  let window7Start    = calendar.date(byAdding: .day, value:  -7, to: day),
                  let window28Start   = calendar.date(byAdding: .day, value: -28, to: day),
                  let biometricStart  = calendar.date(byAdding: .day, value:  -1, to: day)
            else { continue }

            // ±1-day biometric window — HK records timestamps vary (midnight, morning, etc.)
            let rhrDay   = allRHR.filter   { $0.date >= biometricStart && $0.date < dayEnd }
            let hrvDay   = allHRV.filter   { $0.date >= biometricStart && $0.date < dayEnd }
            let sleepDay = allSleep.filter { $0.date >= biometricStart && $0.date < dayEnd }

            guard (!hrvDay.isEmpty || !rhrDay.isEmpty), !sleepDay.isEmpty else { continue }

            let workoutsInWindow = allWorkouts.filter { $0.startDate >= window28Start && $0.startDate < dayEnd }
            let todayWorkouts    = allWorkouts.filter { calendar.isDate($0.startDate, inSameDayAs: day) }

            guard let readiness = readinessAnalyzer.analyzeReadiness(
                restingHR: rhrDay,
                hrv: hrvDay,
                sleep: sleepDay,
                workouts: workoutsInWindow,
                stravaActivities: [],
                nutrition: []
            ) else { continue }

            // ACWR computed with date-relative windows (PredictiveReadinessService uses Date()).
            let acuteLoad   = allWorkouts.filter { $0.startDate >= window7Start  && $0.startDate < dayEnd }
                .reduce(0.0) { $0 + predictiveReadinessService.calculateWorkoutLoad($1, ftpSnapshots: ftpSnapshots) } / 7.0
            let chronicLoad = allWorkouts.filter { $0.startDate >= window28Start && $0.startDate < dayEnd }
                .reduce(0.0) { $0 + predictiveReadinessService.calculateWorkoutLoad($1, ftpSnapshots: ftpSnapshots) } / 28.0
            let acwr = chronicLoad > 0 ? acuteLoad / chronicLoad : 1.0

            let dayLoad = todayWorkouts.reduce(0.0) {
                $0 + predictiveReadinessService.calculateWorkoutLoad($1, ftpSnapshots: ftpSnapshots)
            }
            modelContext.insert(StoredDailyScore(
                date: day,
                readinessScore: readiness.score,
                dailyStrain: acwr,
                workoutCount: todayWorkouts.count,
                dailyLoad: dayLoad
            ))
            inserted += 1
        }

        // New history changes what the detectors see, so let patterns re-run. Only then:
        // this backfill runs inside the Coach refresh that follows a pattern run, and an
        // unconditional clear would erase that run's stamp and defeat the throttle for
        // anyone it keeps re-checking (no sleep data, or a skipped day).
        if inserted > 0 {
            try? modelContext.save()
            UserDefaults.standard.removeObject(forKey: Self.lastPatternAnalysisKey)
            scoreBackfillGeneration += 1
        }
        UserDefaults.standard.set(true, forKey: udKey)

        #if DEBUG
        if inserted > 0 { print("📅 Backfill: inserted \(inserted) historical StoredDailyScore records") }
        #endif
    }

    /// One-time migration: populates dailyLoad on all existing StoredDailyScore rows from StoredWorkout.
    /// Existing rows got dailyLoad=0.0 from the lightweight SwiftData migration — this fixes them so
    /// the back-to-back crash detector can distinguish warmups (< 1.0 TSS) from real training days.
    private func backfillDailyLoad(modelContext: ModelContext) {
        let udKey = "dailyLoadBackfillV1Done"
        guard !UserDefaults.standard.bool(forKey: udKey) else { return }

        let allScores = (try? modelContext.fetch(FetchDescriptor<StoredDailyScore>())) ?? []
        let ftpSnapshots = (try? modelContext.fetch(FetchDescriptor<StoredFTPSnapshot>())) ?? []
        let storedWorkouts = (try? modelContext.fetch(FetchDescriptor<StoredWorkout>())) ?? []

        #if DEBUG
        if allScores.isEmpty { print("⚠️ backfillDailyLoad: no StoredDailyScore records found — migration skipped") }
        #endif

        let calendar = Calendar.current
        for score in allScores {
            let dayStart = calendar.startOfDay(for: score.date)
            guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { continue }
            let load = storedWorkouts
                .filter { $0.startDate >= dayStart && $0.startDate < dayEnd }
                .reduce(0.0) {
                    $0 + predictiveReadinessService.calculateWorkoutLoad(WorkoutData(from: $1), ftpSnapshots: ftpSnapshots)
                }
            score.dailyLoad = load
        }

        try? modelContext.save()
        UserDefaults.standard.set(true, forKey: udKey)
    }

    // MARK: - 7-Day Forecast Plan

    /// How long a published analysis can be reused. Today's word follows the in-day score,
    /// which moves with the clock and steps, and neither is in the fingerprint. Nothing is
    /// scheduled: this only decides what the next open, return to the app or sync does.
    nonisolated static let forecastLiveRefreshInterval: TimeInterval = 15 * 60

    /// Everything the plan reads from the store, as of one moment.
    struct ForecastStoreSnapshot {
        /// Complete days in the last 90, ascending.
        let days: [ForecastHistoryDay]
        /// Stored workouts over the same span and today, for the ACWR engine.
        let workouts: [WorkoutData]
        let ftpSnapshots: [StoredFTPSnapshot]
        let rodeLoadToday: Double
        /// Hash of the rows and every workout's load. Today's row is left out: analysis rewrites it.
        let signature: Int
    }

    /// Complete days merge duplicates by `dateString` (a stored `date` can drift across midnight)
    /// at the highest load and that row's score. A day's load is the larger of its row and its
    /// stored rides, since a row can go stale either way. A day with no row has a nil score.
    /// Throws on a failed fetch: an empty read must never look like a rider with no history.
    func loadForecastHistory(context: ModelContext, now: Date) throws -> ForecastStoreSnapshot {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        guard let start = calendar.date(byAdding: .day, value: -ForecastProfile.trainingWindowDays, to: today),
              let rowFetchStart = calendar.date(byAdding: .day, value: -1, to: start)
        else { return ForecastStoreSnapshot(days: [], workouts: [], ftpSnapshots: [], rodeLoadToday: 0, signature: 0) }

        let rows = try context.fetch(FetchDescriptor<StoredDailyScore>(predicate: #Predicate { $0.date >= rowFetchStart }))
        let stored = try context.fetch(FetchDescriptor<StoredWorkout>(predicate: #Predicate { $0.startDate >= start }))
        let ftpSnapshots = try context.fetch(FetchDescriptor<StoredFTPSnapshot>())

        var bestRow: [Date: StoredDailyScore] = [:]
        for row in rows {
            let parsed = Self.dailyScoreDateFormatter.date(from: row.dateString) ?? row.date
            let day = calendar.startOfDay(for: parsed)
            guard day >= start, day < today else { continue }
            if let best = bestRow[day], best.dailyLoad >= row.dailyLoad { continue }
            bestRow[day] = row
        }

        let workouts = stored.map { WorkoutData(from: $0) }
        var hasher = Hasher()
        var rideLoads: [Date: Double] = [:]
        for workout in stored.sorted(by: { $0.id < $1.id }) {
            let load = predictiveReadinessService.calculateWorkoutLoad(WorkoutData(from: workout), ftpSnapshots: ftpSnapshots)
            rideLoads[calendar.startOfDay(for: workout.startDate), default: 0] += load
            hasher.combine(workout.id)
            hasher.combine((load * 100).rounded())
        }

        let days = Set(bestRow.keys).union(rideLoads.keys.filter { $0 < today }).sorted().map { day in
            ForecastHistoryDay(date: day, score: bestRow[day]?.readinessScore,
                               load: max(bestRow[day]?.dailyLoad ?? 0, rideLoads[day] ?? 0))
        }
        for day in days {
            hasher.combine(day.date)
            hasher.combine(day.score)
            hasher.combine((day.load * 100).rounded())
        }
        return ForecastStoreSnapshot(days: days, workouts: workouts, ftpSnapshots: ftpSnapshots,
                                     rodeLoadToday: rideLoads[today] ?? 0, signature: hasher.finalize())
    }

    /// Nil on a failed read, which says nothing about whether the store moved.
    func forecastInputSignature(context: ModelContext, now: Date = Date()) -> Int? {
        (try? loadForecastHistory(context: context, now: now))?.signature
    }

    /// Nil below 14 scored days. `startScore` ignores today's rides; `currentScore`
    /// (`forecastTodayScore`) decides today's word. Rebuilt from the store on every analysis.
    func computeForecastPlan(modelContext: ModelContext, startScore: Int, currentScore: Int,
                             illness: ForecastIllness, activePatterns: Set<PatternType>,
                             memories: [CoachMemoryNote],
                             injuryRisk: InjuryRiskCalculator.RiskLevel,
                             sleep: [HealthDataPoint], now: Date = Date()) throws -> ForecastPlan? {
        let calendar = Calendar.current
        let store = try loadForecastHistory(context: modelContext, now: now)
        guard let profile = ForecastProfile.learn(history: store.days, today: now, calendar: calendar) else { return nil }

        let service = predictiveReadinessService
        let input = ForecastPlanInput(
            now: now,
            startScore: startScore,
            currentScore: currentScore,
            rodeLoadToday: store.rodeLoadToday,
            recentLoads: store.days,
            profile: profile,
            illness: illness,
            hrvPrecursorActive: activePatterns.contains(.hrvPrecursor),
            injuryRiskElevated: injuryRisk == .high || injuryRisk == .veryHigh,
            noteCaps: Self.forecastNoteCaps(memories),
            shortSleepNights: Self.shortSleepNights(sleep: sleep, now: now, calendar: calendar),
            projectedACWR: { close, planned in
                service.calculateReadiness(stravaActivities: [], healthKitWorkouts: store.workouts,
                                           ftpSnapshots: store.ftpSnapshots, referenceDate: close,
                                           plannedDailyLoads: planned).acwr
            }
        )
        return ForecastPlan(days: ForecastPlanner.plan(input, calendar: calendar), profile: profile)
    }

    /// The score that decides today's word: `startScore` less the fatigue from today's workouts
    /// and steps, so a ride lowers it and it recovers through the day. Not `intraDay.currentScore`:
    /// that repays yesterday's fatigue as the hours pass, which the stored rows behind the rider's
    /// normal never get, so the word would climb to Hard with no new data.
    static func forecastTodayScore(startScore: Int, workouts: [WorkoutData], stepExcessTSS: Double, now: Date = Date()) -> Int {
        RecoveryDecayService().calculateIntraDayReadiness(
            baselineScore: startScore,
            todayWorkouts: workouts,
            todayStepExcessTSS: stepExcessTSS,
            now: now
        ).currentScore
    }

    /// Only a first load of the day takes the screen. A refresh with today's snapshot to show runs
    /// quietly, since analysis now re-runs on most returns to the app; yesterday's advice doesn't stay up.
    nonisolated static func blocksContent(isAnalyzing: Bool, snapshotDate: Date?, now: Date = Date()) -> Bool {
        guard isAnalyzing else { return false }
        guard let snapshotDate else { return true }
        return !Calendar.current.isDate(snapshotDate, inSameDayAs: now)
    }

    /// A rider who can't reach 14 scored days (no sleep data, say) would otherwise pay for a full
    /// HealthKit backfill on every analysis, and a failed store read says nothing about missing rows.
    nonisolated static func shouldForceScoreBackfill(lastAttempt: Date?, readFailed: Bool, now: Date = Date()) -> Bool {
        guard !readFailed else { return false }
        guard let lastAttempt else { return true }
        return !Calendar.current.isDate(lastAttempt, inSameDayAs: now)
    }

    /// The plan replayed against the last 60 days. Nil on a failed read.
    func forecastCheck(modelContext: ModelContext, now: Date = Date()) -> ForecastCheckResult? {
        guard let store = try? loadForecastHistory(context: modelContext, now: now) else { return nil }
        return ForecastPlanner.replay(history: store.days, days: Self.forecastCheckDays, today: now, calendar: .current)
    }

    nonisolated static let forecastCheckDays = 60

    /// A failed read keeps the last plan while it still starts today. It never falls back to
    /// "no history", and yesterday's plan would call yesterday Today.
    static func forecastAfterRead(_ read: Result<[ReadinessForecastDay]?, Error>, last: [ReadinessForecastDay]?,
                                  now: Date = Date()) -> [ReadinessForecastDay]? {
        switch read {
        case .success(let days):
            return days
        case .failure:
            guard let first = last?.first, Calendar.current.isDate(first.date, inSameDayAs: now) else { return nil }
            return last
        }
    }

    /// The Coach reads the plan's words, so the paragraph and the card can't disagree. Days are
    /// found by date: a plan kept after a failed read may no longer line up by position.
    static func coachState(plan: [ReadinessForecastDay]?, profile: ForecastProfile?, startScore: Int, morningScore: Int,
                           currentScore: Int, acwr: Double, injuryRisk: InjuryRiskCalculator.RiskLevel,
                           activePatterns: Set<PatternType>, memories: [CoachMemoryNote],
                           illness: MasterCoachEngine.IllnessState, now: Date) -> MasterCoachEngine.StateVector {
        let calendar = Calendar.current
        func planned(_ offset: Int) -> ReadinessForecastDay? {
            guard let date = calendar.date(byAdding: .day, value: offset, to: now) else { return nil }
            return plan?.first { calendar.isDate($0.date, inSameDayAs: date) }
        }
        return MasterCoachEngine.StateVector(
            morningScore: morningScore,
            currentScore: currentScore,
            nextDayForecast: planned(1)?.coaching,
            acwr: acwr,
            injuryRisk: injuryRisk,
            activePatterns: activePatterns.map(\.rawValue).sorted(),
            memories: memories,
            illness: illness,
            todayEffort: planned(0)?.effort,
            startedLow: profile.map { $0.band(z: $0.z(Double(startScore))) >= .easy }
        )
    }

    /// Injury caps at Easy; Travel and Stress at Moderate. Other notes don't limit the plan.
    private static func forecastNoteCaps(_ memories: [CoachMemoryNote]) -> [ForecastNoteCap] {
        memories.filter(\.isCurrentlyActive).compactMap { note in
            switch note.category {
            case "Injury": return ForecastNoteCap(cap: .easy, reason: "Injury", until: note.expiresAt)
            case "Travel": return ForecastNoteCap(cap: .moderate, reason: "Travel", until: note.expiresAt)
            case "Stress": return ForecastNoteCap(cap: .moderate, reason: "Stress", until: note.expiresAt)
            default: return nil
            }
        }
    }

    /// The latest consecutive nights, up to 2, under 85% of the rider's 28-day median sleep.
    static func shortSleepNights(sleep: [HealthDataPoint], now: Date, calendar: Calendar) -> Int {
        let today = calendar.startOfDay(for: now)
        guard let windowStart = calendar.date(byAdding: .day, value: -ForecastProfile.normalWindowDays, to: today),
              let staleBefore = calendar.date(byAdding: .day, value: -2, to: today) else { return 0 }
        let recent = sleep.filter { $0.date >= windowStart && $0.date <= now }.sorted { $0.date > $1.date }
        guard let usual = ForecastProfile.median(recent.map(\.value)), let newest = recent.first,
              newest.date >= staleBefore else { return 0 }
        guard newest.value < usual * 0.85 else { return 0 }
        guard recent.count > 1, recent[1].value < usual * 0.85,
              calendar.dateComponents([.day], from: calendar.startOfDay(for: recent[1].date),
                                      to: calendar.startOfDay(for: newest.date)).day == 1
        else { return 1 }
        return 2
    }

    /// What the plan should know about the illness log. A failed log read keeps the state's
    /// whole recovery window rather than ending it early.
    private func forecastIllness(state: MasterCoachEngine.IllnessState, context: ModelContext, now: Date) -> ForecastIllness {
        switch state {
        case .none: return .none
        case .sick: return .sick
        case .recovering:
            guard let events = try? context.fetch(FetchDescriptor<IllnessEvent>()) else {
                return .recovering(daysLeft: MasterCoachEngine.IllnessState.recoveringDays)
            }
            let spells = events.map { (start: $0.startDate, end: $0.endDate) }
            return .recovering(daysLeft: MasterCoachEngine.IllnessState.recoveringDaysLeft(spells, now: now))
        }
    }

    // MARK: - Primary Activity Detection (moved from ReadinessViewModel)

    private func determinePrimaryActivity(from workouts: [WorkoutData]) -> String {
        let calendar = Calendar.current
        let ninetyDaysAgo = calendar.date(byAdding: .day, value: -90, to: Date()) ?? Date()
        var counts: [String: Int] = [:]
        for workout in workouts where workout.startDate >= ninetyDaysAgo {
            switch workout.workoutType {
            case .cycling: counts["Ride", default: 0] += 1
            case .running:  counts["Run",  default: 0] += 1
            case .swimming: counts["Swim", default: 0] += 1
            default: break
            }
        }
        return counts.max(by: { $0.value < $1.value })?.key ?? "Ride"
    }

    private func calculateImprovedACWRTrend(workouts: [WorkoutData], ftpSnapshots: [StoredFTPSnapshot]) -> [ACWRDataPoint] {
        // Delegates to the one ACWR engine. This loop used to live here and passed
        // `startOfDay(targetDate)` as the reference date, which closed every day's
        // window at midnight *before* that day's training: the chart's last point
        // ignored today's ride entirely and sat below the assessment printed
        // beside it, and each earlier point was shifted a day late.
        predictiveReadinessService.calculateACWRTrend(
            healthKitWorkouts: workouts,
            ftpSnapshots: ftpSnapshots,
            days: 7
        )
    }

    // MARK: - Reconciler
    
    private func reconcileAdvice(
        readiness: ReadinessAnalyzer.ReadinessScore,
        risk: InjuryRiskCalculator.InjuryRiskAssessment,
        hrvRec: DailyRecommendationService.DailyRecommendation
    ) -> String {
        
        // 1. HARD OVERRIDE: High or Very High risk always wins
        if risk.riskLevel == .high || risk.riskLevel == .veryHigh {
            if hrvRec.status == .goHard || hrvRec.status == .quality {
                return "Your nervous system is ready, but your training load spike is risky (High Injury Risk). Play it safe: swap today's hard session for easy aerobic work."
            }
            return risk.recommendation
        }
        
        // 2. MODERATE TEMPERING: If HRV is pushing but load is building
        if risk.riskLevel == .moderate && (hrvRec.status == .goHard || hrvRec.status == .quality) {
            return "You're fresh, but injury risk is moderate due to recent load spikes. You can do quality work, but avoid back-to-back hard days and focus on recovery."
        }
        
        // 3. LOW HRV OVERRIDE: If HRV says rest, we listen even if load is low
        if hrvRec.status == .rest || hrvRec.status == .easy {
            return hrvRec.guidance
        }
        
        // 4. SYNERGY: If both are good, give the green light
        if readiness.score >= 70 && (hrvRec.status == .goHard || hrvRec.status == .quality) {
            return hrvRec.guidance
        }
        
        // Fallback
        return hrvRec.guidance
    }
    
    // MARK: - Helpers

    /// Never run → always run. A user retry always runs; automatic appears and the
    /// background task skip a run that completed within `forcedPatternAnalysisMinInterval`;
    /// an InsightsView appear waits out `patternAnalysisStalenessInterval`.
    nonisolated static func shouldRunPatternAnalysis(lastRun: Date?, trigger: PatternAnalysisTrigger, now: Date = Date()) -> Bool {
        guard let lastRun else { return true }
        let window: TimeInterval
        switch trigger {
        case .userRetry: return true
        case .appear, .background: window = forcedPatternAnalysisMinInterval
        case .staleCheck: window = patternAnalysisStalenessInterval
        }
        return now.timeIntervalSince(lastRun) > window
    }

    /// Whether the published snapshot still describes the store. The fingerprint
    /// covers synced data; the pattern set covers the one input that changes with
    /// the clock alone (`TrainingPattern.isActive` expiring, or a fresh detection).
    nonisolated static func canReuseCachedAnalysis(
        lastAnalysisDate: Date?,
        fingerprint: PredictionCache.DataFingerprint,
        lastFingerprint: PredictionCache.DataFingerprint?,
        activePatternTypes: Set<PatternType>,
        lastActivePatternTypes: Set<PatternType>?,
        illnessState: MasterCoachEngine.IllnessState = .none,
        lastIllnessState: MasterCoachEngine.IllnessState? = MasterCoachEngine.IllnessState.none,
        activeMemoryIDs: Set<UUID> = [],
        lastActiveMemoryIDs: Set<UUID>? = [],
        forecastSignature: Int? = nil,
        lastForecastSignature: Int? = nil,
        maxAge: TimeInterval? = nil,
        now: Date = Date()
    ) -> Bool {
        guard let lastAnalysisDate,
              Calendar.current.isDate(lastAnalysisDate, inSameDayAs: now)
        else { return false }
        if let maxAge, now.timeIntervalSince(lastAnalysisDate) > maxAge { return false }
        // A failed signature read says nothing about the store, so it can't force a re-run.
        if let forecastSignature, forecastSignature != lastForecastSignature { return false }
        return fingerprint == lastFingerprint && activePatternTypes == lastActivePatternTypes
            && illnessState == lastIllnessState && activeMemoryIDs == lastActiveMemoryIDs
    }

    /// The Coach notes active now (not resolved, not expired). Read whole: a few rows.
    private func fetchActiveMemoryIDs(context: ModelContext) -> Set<UUID> {
        Set(((try? context.fetch(FetchDescriptor<CoachMemoryNote>())) ?? []).filter(\.isCurrentlyActive).map(\.id))
    }

    /// What the illness log says about today (ongoing, just ended, or nothing). The log is a
    /// handful of rows, so it is read whole (no predicate to translate). A failed read keeps
    /// the last state this repository saw, never "no illness": that would advise training
    /// while the log says sick.
    private func fetchIllnessState(context: ModelContext, now: Date = Date()) -> MasterCoachEngine.IllnessState {
        guard let events = try? context.fetch(FetchDescriptor<IllnessEvent>()) else {
            return lastIllnessState ?? .none
        }
        return MasterCoachEngine.IllnessState.from(events.map { (start: $0.startDate, end: $0.endDate) }, now: now)
    }

    private func fetchActivePatternTypes(context: ModelContext) -> Set<PatternType> {
        let stored = (try? context.fetch(FetchDescriptor<TrainingPattern>())) ?? []
        return Set(stored.filter(\.isActive).map(\.patternType))
    }

    private func calculateFingerprint(context: ModelContext) throws -> PredictionCache.DataFingerprint {
        let workoutCount = try context.fetchCount(FetchDescriptor<StoredWorkout>())
        let sleepCount   = try context.fetchCount(FetchDescriptor<StoredHealthMetric>(predicate: #Predicate { $0.type == "Sleep" }))
        let hrvCount     = try context.fetchCount(FetchDescriptor<StoredHealthMetric>(predicate: #Predicate { $0.type == "HRV" }))
        let rhrCount     = try context.fetchCount(FetchDescriptor<StoredHealthMetric>(predicate: #Predicate { $0.type == "RHR" }))

        // Fetch most-recent date per signal to detect new records that arrive without changing counts.
        var workoutLatestDesc = FetchDescriptor<StoredWorkout>(sortBy: [SortDescriptor(\.startDate, order: .reverse)])
        workoutLatestDesc.fetchLimit = 1

        var sleepLatestDesc = FetchDescriptor<StoredHealthMetric>(
            predicate: #Predicate { $0.type == "Sleep" },
            sortBy: [SortDescriptor(\.date, order: .reverse)])
        sleepLatestDesc.fetchLimit = 1

        var hrvLatestDesc = FetchDescriptor<StoredHealthMetric>(
            predicate: #Predicate { $0.type == "HRV" },
            sortBy: [SortDescriptor(\.date, order: .reverse)])
        hrvLatestDesc.fetchLimit = 1

        var rhrLatestDesc = FetchDescriptor<StoredHealthMetric>(
            predicate: #Predicate { $0.type == "RHR" },
            sortBy: [SortDescriptor(\.date, order: .reverse)])
        rhrLatestDesc.fetchLimit = 1

        let latestWorkout = try context.fetch(workoutLatestDesc).first?.startDate
        let latestSleep   = try context.fetch(sleepLatestDesc).first?.date
        let latestHRV     = try context.fetch(hrvLatestDesc).first?.date
        let latestRHR     = try context.fetch(rhrLatestDesc).first?.date

        return PredictionCache.DataFingerprint(
            workoutCount:      workoutCount,
            sleepCount:        sleepCount,
            hrvCount:          hrvCount,
            rhrCount:          rhrCount,
            latestWorkoutDate: latestWorkout,
            latestSleepDate:   latestSleep,
            latestHRVDate:     latestHRV,
            latestRHRDate:     latestRHR
        )
    }
    
    private func mapScoreToLevel(_ score: Int) -> ReadinessLevel {
        if score >= 80 { return .excellent }
        if score >= 70 { return .good }
        if score >= 60 { return .moderate }
        return .poor
    }

    // MARK: - Cardiovascular Strain (moved from ReadinessViewModel — Phase 1.2)

    /// Returns maxHR from UserDefaults cache if < 7 days old, otherwise queries HealthKit
    /// and refreshes the cache. Falls back to 220-age only if HealthKit returns no data.
    private func resolvedMaxHR() async -> Double {
        let defaults = UserDefaults.standard
        let cacheDate = defaults.object(forKey: Self.maxHRCacheDateKey) as? Date ?? .distantPast
        let isFresh = Date().timeIntervalSince(cacheDate) < Self.maxHRCacheTTL
        let cached = defaults.double(forKey: Self.maxHRCacheKey)

        if isFresh, cached > 100 {
            return cached
        }

        if let personal = try? await HealthKitManager.shared.fetchPersonalMaxHR(over: 90), personal > 100 {
            defaults.set(personal, forKey: Self.maxHRCacheKey)
            defaults.set(Date(), forKey: Self.maxHRCacheDateKey)
            return personal
        }

        let age = HealthKitManager.shared.getUserAge() ?? 35
        return 220.0 - Double(age)
    }

    private func computeCardiovascularStrain(rhrData: [HealthDataPoint]) async -> CardiovascularStrainService.Result? {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        let now = Date()

        async let hrSamplesTask = HealthKitManager.shared.fetchRawHeartRateSamples(
            startDate: todayStart, endDate: now
        )
        let maxHR = await resolvedMaxHR()
        let hrSamples = (try? await hrSamplesTask) ?? []
        let restingHR = rhrData.last?.value ?? 55.0

        let sensitivityOffset = UserDefaults.standard.double(forKey: "strainSensitivityOffset")
        return cardiovascularStrainService.compute(
            todayHRSamples: hrSamples,
            estimatedMaxHR: maxHR,
            restingHR: restingHR,
            sensitivityOffset: sensitivityOffset
        )
    }

    // MARK: - Holistic Metrics (moved from DashboardViewModel — Phase 1.2)

    private func buildHolisticMetrics(
        workouts: [WorkoutData],
        stepData: [HealthDataPoint],
        hrvData: [HealthDataPoint],
        sleepData: [HealthDataPoint],
        trainingLoad: TrainingLoadCalculator.TrainingLoadSummary?,
        readinessScore: Int
    ) -> HealthMetrics {
        let metSummary = metAnalyzer.analyzeMETActivity(
            healthKitWorkouts: workouts,
            stravaActivities: [],
            stepData: stepData
        )
        let balance = balanceAnalyzer.analyzeTrainingBalance(
            healthKitWorkouts: workouts,
            stravaActivities: []
        )

        let metStatus: MetricStatus = {
            guard let summary = metSummary else { return .needsAttention }
            switch summary.status {
            case .excellent: return .excellent
            case .good: return .good
            case .moderate: return .moderate
            case .insufficient: return .needsAttention
            }
        }()

        let trainingBalanceStatus: MetricStatus = {
            guard let bal = balance else { return .needsAttention }
            switch bal.balance {
            case .optimal: return .excellent
            case .enduranceDominant, .strengthDominant: return .moderate
            case .missingStrength, .missingEndurance: return .needsAttention
            case .needsMobility: return .good
            }
        }()

        let hrvBaselineMs: Double? = {
            let thirtyDayData = hrvData.suffix(30).map(\.value)
            guard thirtyDayData.count >= 7 else { return nil }
            return thirtyDayData.reduce(0, +) / Double(thirtyDayData.count)
        }()

        let hrvStatus: MetricStatus = {
            let recentHRVData = hrvData.suffix(7).map(\.value)
            guard !recentHRVData.isEmpty else { return .needsAttention }
            let recentHRV = recentHRVData.reduce(0, +) / Double(recentHRVData.count)
            if recentHRV >= 60 { return .excellent }
            if recentHRV >= 45 { return .good }
            if recentHRV >= 30 { return .moderate }
            return .needsAttention
        }()

        let loadStatus: MetricStatus = {
            guard let ld = trainingLoad else { return .good }
            switch ld.status {
            case .optimal: return .excellent
            case .fresh: return .good
            case .fatigued: return .moderate
            case .overreaching: return .needsAttention
            }
        }()

        let sleepStatus: MetricStatus = {
            let recentSleepData = sleepData.suffix(7).map(\.value)
            guard !recentSleepData.isEmpty else { return .needsAttention }
            let avgSleep = recentSleepData.reduce(0, +) / Double(recentSleepData.count)
            if avgSleep >= 8 { return .excellent }
            if avgSleep >= 7 { return .good }
            if avgSleep >= 6 { return .moderate }
            return .needsAttention
        }()

        let readinessStatus: MetricStatus = {
            if readinessScore >= 80 { return .excellent }
            if readinessScore >= 70 { return .good }
            if readinessScore >= 60 { return .moderate }
            return .needsAttention
        }()

        let recentSleepWindow = sleepData.suffix(7).map(\.value)
        let averageSleep = recentSleepWindow.isEmpty
            ? 0
            : recentSleepWindow.reduce(0, +) / Double(recentSleepWindow.count)

        return HealthMetrics(
            weeklyMETMinutes: metSummary?.weeklyMETMinutes ?? 0,
            metStatus: metStatus,
            strengthPercentage: balance?.strengthPercentage ?? 0,
            trainingBalance: trainingBalanceStatus,
            currentHRV: hrvData.last?.value ?? 0,
            hrvStatus: hrvStatus,
            hrvBaselineMs: hrvBaselineMs,
            acwr: trainingLoad?.acuteChronicRatio ?? 1.0,
            loadStatus: loadStatus,
            averageSleep: averageSleep,
            sleepStatus: sleepStatus,
            readinessScore: readinessScore,
            readinessStatus: readinessStatus
        )
    }
}
