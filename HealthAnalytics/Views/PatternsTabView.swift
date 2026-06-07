//
//  PatternsTabView.swift
//  HealthAnalytics
//
//  Renamed from IntelligenceTabView during the v0.1.9.0 Intelligence redesign.
//  "Patterns" is what's inside — the previous "Intelligence" label was about the
//  engine, not the user-visible content. Phase R.1 (this commit) is the scaffold
//  rename only; later phases (R.2–R.6) move Performance Audit to Load, gut
//  InsightsView, merge correlation sections, add the "Patterns active this week"
//  header strip + tab-icon badge, and inline the remaining content directly
//  (killing the nested ScrollView).
//

import SwiftUI

struct PatternsTabView: View {
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        NavigationStack {
            ZStack {
                TabBackgroundColor.insights(for: colorScheme)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        NavigationLink {
                            PerformanceAuditView()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Performance Audit")
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Text("Why did you perform better?")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.secondary)
                            }
                            .padding()
                            .background(Color.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
                        }
                        .padding(.horizontal)

                        // InsightsView still embedded for now — Phase R.3 starts
                        // gutting it and R.6 inlines the survivors directly here.
                        InsightsView()
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
}

#Preview {
    PatternsTabView()
}
