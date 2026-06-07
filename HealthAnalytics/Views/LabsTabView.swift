//
//  LabsTabView.swift
//  HealthAnalytics
//
//  Created during the v0.1.9.0 Intelligence redesign as the 5th tab.
//  Labs is where experimental or secondary-importance features live so they're
//  discoverable without competing for primary attention on Coach / Readiness /
//  Load / Patterns. Phase R.1 (this commit) creates the placeholder shell.
//  Phase R.2 moves the AgingAlphaCard and CompoundScoreCard in as initial
//  content. Future Labs additions should announce themselves with a brief
//  "what we're learning" caption — this tab is intentional exploration, not a
//  graveyard for unfinished work.
//

import SwiftUI

struct LabsTabView: View {
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        NavigationStack {
            ZStack {
                TabBackgroundColor.insights(for: colorScheme)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: .spacingLg) {
                        Text("Experimental features and signals we're still studying. Treat the numbers here as interesting, not prescriptive.")
                            .font(.subheadline)
                            .foregroundStyle(Color.textSecondary)
                            .padding(.horizontal)

                        Text("Aging and Cyclist Compound Score arrive here in the next phase of the redesign.")
                            .font(.caption)
                            .foregroundStyle(Color.textTertiary)
                            .padding(.horizontal)

                        Spacer()
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
}

#Preview {
    LabsTabView()
}
