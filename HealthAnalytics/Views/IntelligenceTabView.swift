//
//  IntelligenceTabView.swift
//  HealthAnalytics
//

import SwiftUI

struct IntelligenceTabView: View {
    @Environment(\.colorScheme) var colorScheme
    @State private var showSettings = false
    
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
                        
                        // We embed the InsightsView here (or it can replace this file if we adapt InsightsView directly)
                        InsightsView()
                    }
                    .padding(.vertical)
                }
            }
            .navigationTitle("Intelligence")
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
    IntelligenceTabView()
}
