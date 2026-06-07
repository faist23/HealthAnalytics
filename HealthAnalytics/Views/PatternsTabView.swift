//
//  PatternsTabView.swift
//  HealthAnalytics
//
//  Renamed from IntelligenceTabView during the v0.1.9.0 Intelligence redesign.
//  "Patterns" is what's inside — the previous "Intelligence" label was about the
//  engine, not the user-visible content. R.5 added the "Patterns active this
//  week: N" header strip + tab-icon badge + collapsible "Data sources" footer.
//  R.6 still owes the nested-ScrollView fix (this view's outer ScrollView still
//  embeds InsightsView's inner one).
//

import SwiftUI
import SwiftData

struct PatternsTabView: View {
    @Environment(\.colorScheme) var colorScheme
    @ObservedObject private var repo = ReadinessRepository.shared

    @Query private var detectedPatterns: [TrainingPattern]

    private var activePatternCount: Int {
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return detectedPatterns.filter { $0.detectedAt >= sevenDaysAgo }.count
    }

    private var headerStripText: String {
        switch activePatternCount {
        case 0:  return "No patterns active this week."
        case 1:  return "1 pattern active this week."
        default: return "\(activePatternCount) patterns active this week."
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                TabBackgroundColor.insights(for: colorScheme)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // R.5: plain-text index of active patterns. No card chrome,
                        // no button — it's a header strip, not a hero.
                        Text(headerStripText)
                            .font(.subheadline)
                            .foregroundStyle(Color.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)

                        InsightsView()

                        dataSourcesFooter
                    }
                    .padding(.vertical)
                }
            }
            .navigationTitle("Patterns")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
        }
    }

    /// R.5: collapsible "Data sources" footer. Status-style audit content moved
    /// out of the InsightsView dashboard and tucked into a DisclosureGroup at
    /// the bottom of Patterns. Discoverable by anyone curious enough to scroll
    /// to the end, but doesn't compete for daily attention.
    @ViewBuilder
    private var dataSourcesFooter: some View {
        let summary = repo.currentReadiness?.dataSummary ?? []
        if !summary.isEmpty {
            DisclosureGroup("Data sources") {
                DataCollectionCard(summary: summary.map {
                    DataCollectionCard.ActivitySummary(
                        activityType: $0.activityType,
                        goodSleep: $0.goodSleep,
                        poorSleep: $0.poorSleep
                    )
                })
                .padding(.top, .spacingSm)
            }
            .font(.subheadline)
            .foregroundStyle(Color.textSecondary)
            .padding(.horizontal)
        }
    }
}

#Preview {
    PatternsTabView()
}
