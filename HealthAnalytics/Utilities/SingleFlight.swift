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
            await Self.wait(for: current)
            return
        }
        let task = Task { [weak self] in
            await work()
            // Cleared from inside the task so it happens at completion, before any
            // joiner resumes — a request arriving just after can't join a finished run.
            self?.current = nil
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
    /// it to return promptly; the work itself keeps running.
    private static func wait(for task: Task<Void, Never>) async {
        let gate = ResumeOnce()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                gate.install(continuation)
                Task { await task.value; gate.resume() }
            }
        } onCancel: {
            gate.resume()
        }
    }
}

/// A continuation resumed at most once, by whichever of completion or cancellation
/// arrives first — including a cancellation that lands before `install`.
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?
    private var resumed = false

    func install(_ c: CheckedContinuation<Void, Never>) {
        lock.lock()
        if resumed { lock.unlock(); c.resume(); return }
        continuation = c
        lock.unlock()
    }

    func resume() {
        lock.lock()
        resumed = true
        let c = continuation
        continuation = nil
        lock.unlock()
        c?.resume()
    }
}
