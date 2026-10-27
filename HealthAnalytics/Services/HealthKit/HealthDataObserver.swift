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

@MainActor
final class HealthDataObserver {
    static let shared = HealthDataObserver()

    nonisolated static let observedTypes: [(type: HKSampleType, wake: BackgroundPassWake)] = [
        (HKQuantityType(.heartRateVariabilitySDNN), .hrvDelivery),
        (HKObjectType.workoutType(), .workoutDelivery),
    ]

    private let store = HKHealthStore()
    private var queries: [HKObserverQuery] = []

    private init() {}

    /// Idempotent: only the first call registers.
    func register(onUpdate: @escaping @MainActor (BackgroundPassWake) async -> Void) {
        guard queries.isEmpty, HKHealthStore.isHealthDataAvailable() else { return }
        for (type, wake) in Self.observedTypes {
            let query = HKObserverQuery(sampleType: type, predicate: nil) { _, completion, error in
                guard error == nil else { completion(); return }
                nonisolated(unsafe) let done = completion
                Task { @MainActor in
                    await Self.handleUpdate(wake: wake, run: onUpdate, completion: done)
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
}
