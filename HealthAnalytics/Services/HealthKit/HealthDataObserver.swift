//
//  HealthDataObserver.swift
//  HealthAnalytics
//
//  HealthKit background delivery for the signals pattern alerts depend on. iOS
//  relaunches the app in the background for a delivery, and the observer query that
//  receives it must exist by then — so this registers from the app delegate's
//  didFinishLaunching on every launch, not from a view's `.task`.
//

import HealthKit
import UIKit

/// Begin/end for UIApplication background time; a seam so tests can fire expiry.
@MainActor
struct BackgroundTime {
    let begin: (String, @escaping @MainActor @Sendable () -> Void) -> UIBackgroundTaskIdentifier
    let end: (UIBackgroundTaskIdentifier) -> Void

    static var live: BackgroundTime {
        BackgroundTime(
            begin: { UIApplication.shared.beginBackgroundTask(withName: $0, expirationHandler: $1) },
            end: { UIApplication.shared.endBackgroundTask($0) }
        )
    }
}

/// One background-time identifier, ended at most once whichever of the expiration
/// handler and the normal exit gets there first.
@MainActor
private final class BackgroundTimeHold {
    private let time: BackgroundTime
    private var id: UIBackgroundTaskIdentifier = .invalid

    init(time: BackgroundTime) { self.time = time }

    func begin(name: String, onExpiry: @escaping @MainActor @Sendable () -> Void) {
        id = time.begin(name) { [self] in
            onExpiry()
            end()
        }
    }

    func end() {
        guard id != .invalid else { return }
        let held = id
        id = .invalid
        time.end(held)
    }
}

@MainActor
final class HealthDataObserver {
    static let shared = HealthDataObserver()

    nonisolated static let observedTypes: [(type: HKSampleType, wake: BackgroundPassWake)] = [
        (HKQuantityType(.heartRateVariabilitySDNN), .hrvDelivery),
        (HKObjectType.workoutType(), .workoutDelivery),
    ]

    private let store = HKHealthStore()
    private var queries: [HKObserverQuery] = []
    /// Types whose query has fired at least once in this process.
    private var firedTypes: Set<BackgroundPassWake> = []

    private init() {}

    /// Idempotent: only the first call registers.
    func register(onUpdate: @escaping @MainActor (BackgroundPassWake) async -> Void) {
        guard queries.isEmpty, HKHealthStore.isHealthDataAvailable() else { return }
        for (type, wake) in Self.observedTypes {
            let query = HKObserverQuery(sampleType: type, predicate: nil) { _, completion, error in
                guard error == nil else {
                    #if DEBUG
                    print("⚠️ Observer query failed for \(type): \(String(describing: error))")
                    #endif
                    completion()
                    return
                }
                nonisolated(unsafe) let done = completion
                Task { @MainActor in
                    let fire = Self.wakeForFire(wake, seen: &Self.shared.firedTypes)
                    await Self.handleUpdate(
                        wake: fire,
                        run: { await Self.runHoldingBackgroundTime(wake: $0, run: onUpdate) },
                        completion: done
                    )
                }
            }
            store.execute(query)
            queries.append(query)
            store.enableBackgroundDelivery(for: type, frequency: .immediate) { enabled, error in
                #if DEBUG
                if !enabled { print("⚠️ Background delivery not enabled for \(type): \(String(describing: error))") }
                #endif
            }
        }
    }

    /// A query's first fire in a process is tagged `.launch`: iOS fires every query once
    /// when it is executed, so on a background cold launch (an app-refresh launch, or a
    /// delivery relaunch for the other type) it isn't evidence of a delivery. The pass
    /// still runs for it (a relaunch delivery arrives this way too); it is just counted
    /// apart and never measures HRV-to-commit latency.
    static func wakeForFire(_ wake: BackgroundPassWake, seen: inout Set<BackgroundPassWake>) -> BackgroundPassWake {
        seen.insert(wake).inserted ? .launch : wake
    }

    /// Always calls `completion`, whatever `run` does: iOS backs off delivery for an
    /// app that leaves an observer update uncompleted.
    static func handleUpdate(
        wake: BackgroundPassWake,
        run: (BackgroundPassWake) async -> Void,
        completion: () -> Void
    ) async {
        defer { completion() }
        await run(wake)
    }

    /// Holds UIApplication background time while the pass runs, so the observer
    /// completion isn't left pending across a suspension. On expiry it cancels the task
    /// WAITING for the pass: `SingleFlight` returns that waiter at once while the
    /// flight's work runs on (a resume after suspension is covered by the commit gate),
    /// so the caller can complete the observer before iOS suspends the app.
    static func runHoldingBackgroundTime(
        wake: BackgroundPassWake,
        run: @escaping @MainActor (BackgroundPassWake) async -> Void,
        time: BackgroundTime? = nil   // nil = UIApplication (a default can't touch main-actor state)
    ) async {
        let waiter = Task { @MainActor in await run(wake) }
        let hold = BackgroundTimeHold(time: time ?? .live)
        hold.begin(name: "patternPass") { waiter.cancel() }
        await waiter.value
        hold.end()
    }
}
