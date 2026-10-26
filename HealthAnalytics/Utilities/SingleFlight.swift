//
//  SingleFlight.swift
//  HealthAnalytics
//
//  Repository-owned async work that callers can await but never cancel.
//

import Foundation

/// Runs one piece of work at a time and lets every caller await it.
///
/// Analysis is requested from view `.task` / `.refreshable` blocks, and SwiftUI cancels
/// those when the user swipes away. Work started here runs in its own unstructured task,
/// so a caller's cancellation ends only that caller's wait — never the work. A run
/// requested while one is in flight joins it instead of starting a second.
@MainActor
final class SingleFlight {
    private var current: Task<Void, Never>?

    func run(_ work: @escaping @MainActor () async -> Void) async {
        if let current {
            await current.value
            return
        }
        let task = Task { [weak self] in
            await work()
            // Cleared from inside the task so it happens at completion, before any
            // joiner resumes — a request arriving just after can't join a finished run.
            self?.current = nil
        }
        current = task
        await task.value
    }

    /// Runs `work` to completion even if the caller is cancelled. For work with its
    /// own coalescing (`performFullAnalysis`), where joining would drop a request.
    static func shielded(_ work: @escaping @MainActor () async -> Void) async {
        await Task { await work() }.value
    }
}
