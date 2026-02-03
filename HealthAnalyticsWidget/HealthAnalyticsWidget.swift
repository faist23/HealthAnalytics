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
        let descriptor = FetchDescriptor<CachedAnalysis>()
        let modelContext = HealthDataContainer.shared.mainContext
        let cachedData = try? modelContext.fetch(descriptor).last
        
        let entry: SimpleEntry
        if let cached = cachedData {
            // Map hex back to Color
            let color = cached.statusColorHex == "#34C759" ? Color.green :
            (cached.statusColorHex == "#FF9500" ? Color.orange : Color.blue)
            
            entry = SimpleEntry(
                date: Date(),
                headline: cached.headline,
                targetAction: cached.targetAction,
                statusColor: color
            )
        } else {
            entry = SimpleEntry(date: Date(), headline: "Sync Required", targetAction: "Open app to analyze data", statusColor: .gray)
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

