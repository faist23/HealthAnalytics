//
//  LabsTabView.swift
//  HealthAnalytics
//
//  Created during the v0.1.9.0 Intelligence redesign as the 5th tab.
//  Labs is where experimental or secondary-importance features live so they're
//  discoverable without competing for primary attention on Coach / Readiness /
//  Load / Patterns. Phase R.2 added the first two residents: biological aging
//  (AgingAlphaCard) and the cycling compound score (CyclingCompoundScoreCard).
//  Future Labs additions should announce themselves with a brief "what we're
//  learning" caption — this tab is intentional exploration, not a graveyard.
//

import SwiftUI

struct LabsTabView: View {
    @Environment(\.colorScheme) var colorScheme
    @ObservedObject private var repo = ReadinessRepository.shared

    var body: some View {
        NavigationStack {
            ZStack {
                TabBackgroundColor.insights(for: colorScheme)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: .spacingLg) {
                        header
                        agingCard
                        compoundScoreCard
                        if !hasAnyContent {
                            emptyState
                        }
                    }
                    .padding(.vertical)
                }
            }
            .navigationTitle("Labs")
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

    private var header: some View {
        Text("Experimental signals we're still studying. Treat the numbers here as interesting, not prescriptive.")
            .font(.subheadline)
            .foregroundStyle(Color.textSecondary)
            .padding(.horizontal)
    }

    @ViewBuilder
    private var agingCard: some View {
        if let aging = repo.currentReadiness?.agingAssessment {
            AgingAlphaCard(assessment: aging)
                .padding(.horizontal)
        }
    }

    @ViewBuilder
    private var compoundScoreCard: some View {
        if let analysis = repo.currentReadiness?.compoundScoreAnalysis {
            CyclingCompoundScoreCard(analysis: analysis)
                .padding(.horizontal)
        }
    }

    private var hasAnyContent: Bool {
        repo.currentReadiness?.agingAssessment != nil ||
        repo.currentReadiness?.compoundScoreAnalysis != nil
    }

    private var emptyState: some View {
        VStack(spacing: .spacingSm) {
            Image(systemName: "flask")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.secondary)
            Text("Labs needs a bit more data")
                .font(.headline)
                .foregroundStyle(Color.textPrimary)
            Text("Aging signal needs ~30 days of HRV + sleep history. The cycling compound score needs a few power-equipped rides logged.")
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, .spacingMd)
    }
}

#Preview {
    LabsTabView()
}
