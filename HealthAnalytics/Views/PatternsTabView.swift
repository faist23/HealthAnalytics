//
//  PatternsTabView.swift
//  HealthAnalytics
//
//  R.6: this view now owns the only ScrollView on the Patterns tab —
//  ScrollViewReader proxy.scrollTo(pattern) operates on the real scroll
//  surface, so Recovery → Patterns deep-link auto-scrolls cleanly to
//  the matching TrainingDNACard. InsightsView is a content producer.
//

import SwiftUI
import SwiftData

struct PatternsTabView: View {
    @EnvironmentObject var coordinator: TabCoordinator
    @Environment(\.colorScheme) var colorScheme
    @ObservedObject private var repo = ReadinessRepository.shared

    @Query private var detectedPatterns: [TrainingPattern]

    @State private var pendingScroll: PatternType? = nil

    private var activePatternCount: Int {
        detectedPatterns.filter { $0.isActive }.count
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

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 20) {
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
                    .refreshable {
                        await SyncManager.shared.performSmartSync(force: true)
                        await ReadinessRepository.shared.forceRefresh(
                            modelContext: HealthDataContainer.shared.mainContext
                        )
                    }
                    .onChange(of: coordinator.pendingScrollPattern) { _, newPattern in
                        guard let pattern = newPattern else { return }
                        coordinator.pendingScrollPattern = nil
                        // If the pattern card is already in the @Query result,
                        // scroll immediately. Otherwise stash and wait — the
                        // .onChange below fires when the data lands.
                        if detectedPatterns.contains(where: { $0.patternType == pattern }) {
                            scroll(proxy: proxy, to: pattern)
                        } else {
                            pendingScroll = pattern
                        }
                    }
                    .onChange(of: detectedPatterns.map(\.patternType)) { _, _ in
                        guard let pattern = pendingScroll,
                              detectedPatterns.contains(where: { $0.patternType == pattern }) else { return }
                        pendingScroll = nil
                        scroll(proxy: proxy, to: pattern)
                    }
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

    private func scroll(proxy: ScrollViewProxy, to pattern: PatternType) {
        Task { @MainActor in
            withAnimation { proxy.scrollTo(pattern, anchor: .top) }
        }
    }

    /// R.5 footer — collapsed by default.
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
