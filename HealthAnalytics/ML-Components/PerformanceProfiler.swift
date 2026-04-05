//
//  PerformanceProfiler.swift
//  HealthAnalytics
//
//  Quick performance profiling to find bottlenecks
//

import Foundation

struct PerformanceProfiler {
    
    /// Measure execution time of a block
    static func measure<T>(_ label: String, block: () throws -> T) rethrows -> T {
        let start = CFAbsoluteTimeGetCurrent()
        defer {
            let duration = CFAbsoluteTimeGetCurrent() - start
            #if DEBUG
            print("⏱️ \(label): \(String(format: "%.2f", duration * 1000))ms")
            #endif
        }
        return try block()
    }

    /// Measure async execution time
    static func measureAsync<T>(_ label: String, block: () async throws -> T) async rethrows -> T {
        let start = CFAbsoluteTimeGetCurrent()
        defer {
            let duration = CFAbsoluteTimeGetCurrent() - start
            #if DEBUG
            print("⏱️ \(label): \(String(format: "%.2f", duration * 1000))ms")
            #endif
        }
        return try await block()
    }
}
