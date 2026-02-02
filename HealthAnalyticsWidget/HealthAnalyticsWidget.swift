//
//  HealthAnalyticsWidget.swift
//  HealthAnalyticsWidget
//
//  Created by Craig Faist on 2/2/26.
//

import WidgetKit
import SwiftUI
import SwiftData

@MainActor // Fixes the Swift 6 concurrency error
struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), headline: "Ready?", targetAction: "Open app to analyze", statusColor: .gray)
    }
    
    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> ()) {
        let entry = SimpleEntry(date: Date(), headline: "Ready to Perform", targetAction: "Aim for 145W today", statusColor: .green)
        completion(entry)
    }
    
    @MainActor
    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> ()) {
        // Fetch latest from shared SwiftData container
        let descriptor = FetchDescriptor<CachedAnalysis>()
        let context = HealthDataContainer.shared.mainContext
        
        // Use logic from your existing PredictionCache to determine what to show
        let cachedData = try? context.fetch(descriptor).last
        
        let entry: SimpleEntry
        if let cached = cachedData {
            // Logic mapping the cached counts back to a status color (simplified)
            entry = SimpleEntry(
                date: Date(),
                headline: "Latest Analysis",
                targetAction: "View today's target power",
                statusColor: .green
            )
        } else {
            entry = SimpleEntry(
                date: Date(),
                headline: "No Data",
                targetAction: "Open app to sync",
                statusColor: .gray
            )
        }
        
        let timeline = Timeline(entries: [entry], policy: .atEnd)
        completion(timeline)
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let headline: String
    let targetAction: String
    let statusColor: Color
}

struct HealthAnalyticsWidgetEntryView : View {
    var entry: Provider.Entry
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(entry.headline)
                    .font(.headline)
                    .minimumScaleFactor(0.8)
                Spacer()
                Circle()
                    .fill(entry.statusColor)
                    .frame(width: 10, height: 10)
            }
            
            Text(entry.targetAction)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            
            Spacer()
            
            Text("HealthAnalytics")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(entry.statusColor.opacity(0.8))
        }
    }
}

struct HealthAnalyticsWidget: Widget {
    let kind: String = "HealthAnalyticsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            HealthAnalyticsWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                // Access the shared App Group database
                .modelContainer(HealthDataContainer.shared)
        }
        .configurationDisplayName("Daily Readiness")
        .description("Get actionable coaching targets on your home screen.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

