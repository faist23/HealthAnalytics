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
///
/// `work` returns whether it completed. False means it ended abandoned (a background
/// pass that resumed past its budget and stored nothing): a caller that JOINED such a
/// run got nothing from it, so once it ends that caller runs its own `work` — or joins
/// a fresh run another joiner already started — exactly once, whatever that returns.
/// The caller that started the abandoned run never retries, and a cancelled joiner
/// just returns.
@MainActor
final class SingleFlight {
    private var current: Task<Bool, Never>?

    func run(_ work: @escaping @MainActor () async -> Bool) async {
        if let current {
            let completed = await Self.wait(for: current)
            // nil: this caller was cancelled while waiting. true: nothing to redo.
            guard completed == false, !Task.isCancelled else { return }
        }
        await start(work)
    }

    /// Starts `work`, or joins the run in flight without any further retry.
    private func start(_ work: @escaping @MainActor () async -> Bool) async {
        if let current {
            await Self.wait(for: current)
            return
        }
        let task = Task { [weak self] in
            let completed = await work()
            // Cleared from inside the task so it happens at completion, before any
            // joiner resumes — a request arriving just after can't join a finished run.
            self?.current = nil
            return completed
        }
        current = task
        await Self.wait(for: task)
    }

    /// Runs `work` to completion even if the caller is cancelled. For work with its
    /// own coalescing (`performFullAnalysis`), where joining would drop a request.
    static func shielded(_ work: @escaping @MainActor () async -> Void) async {
        await wait(for: Task { await work() })
    }

    /// Returns when `task` finishes or when the caller is cancelled, whichever is first.
    /// iOS cancels a background task's handler when its time budget expires and expects
    /// it to return promptly; the work itself keeps running. `AsyncStream` iteration ends
    /// on the iterating task's cancellation, including a cancellation that came first.
    /// Nil when the caller was cancelled before `task` finished.
    @discardableResult
    private static func wait<T: Sendable>(for task: Task<T, Never>) async -> T? {
        let (done, finished) = AsyncStream<T>.makeStream()
        Task {
            finished.yield(await task.value)
            finished.finish()
        }
        var result: T?
        for await value in done { result = value }
        return result
    }
}
