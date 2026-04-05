//
//  HealthspanTabView.swift
//  HealthAnalytics
//

import SwiftUI
import SwiftData

struct HealthspanTabView: View {
    @StateObject private var viewModel = InsightsViewModel()
    @State private var showHealthspanDetails = false
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) var colorScheme
    @ObservedObject var syncManager = SyncManager.shared

    var body: some View {
        NavigationStack {
            ZStack {
                Color(white: 0.05) // Dark Whoop-like background
                    .ignoresSafeArea()
                
                if syncManager.isBackfillingHistory {
                    BackfillProgressView(
                        progress: syncManager.backfillProgress,
                        message: syncManager.syncProgress
                    )
                } else {
                    ScrollView {
                        VStack(spacing: 24) {
                            if let error = viewModel.errorMessage {
                                ErrorView(message: error)
                                    .cardStyle(for: .error)
                            }
                            
                            if !viewModel.isLoading {
                                if let aging = viewModel.agingAssessment {
                                    
                                    // 1. Healthspan Circular Gauge
                                    CircularGauge(
                                        title: "BIOLOGICAL AGE",
                                        value: String(format: "%.1f", aging.biologicalAge),
                                        subtitle: aging.agingAlpha >= 0 ? "\(String(format: "%.1f", aging.agingAlpha)) years younger" : "\(String(format: "%.1f", abs(aging.agingAlpha))) years older",
                                        progress: min(Double(aging.chronologicalAge) / aging.biologicalAge * 0.5, 1.0),
                                        color: aging.agingAlpha >= 0 ? AppColors.hrv : AppColors.error
                                    )
                                    
                                    // 2. Pace of Aging Section
                                    VStack(alignment: .leading, spacing: 16) {
                                        Text("PACE OF AGING")
                                            .font(.caption)
                                            .fontWeight(.bold)
                                            .foregroundStyle(.secondary)
                                            .tracking(1)
                                        
                                        HStack {
                                            Text("Slow")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Spacer()
                                            Text(String(format: "%.1fx", 1.0 - (aging.agingAlpha / Double(aging.chronologicalAge))))
                                                .font(.title2.bold())
                                            Spacer()
                                            Text("Fast")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        
                                        GeometryReader { geometry in
                                            ZStack(alignment: .leading) {
                                                // Slider track
                                                HStack(spacing: 2) {
                                                    ForEach(0..<40) { _ in
                                                        Rectangle()
                                                            .fill(Color.white.opacity(0.1))
                                                            .frame(width: 2)
                                                    }
                                                }
                                                .frame(maxWidth: .infinity, alignment: .center)
                                                
                                                // Indicator
                                                let pace = 1.0 - (aging.agingAlpha / Double(aging.chronologicalAge))
                                                let normalizedPosition = min(max((pace + 1.0) / 4.0, 0), 1.0)
                                                
                                                Rectangle()
                                                    .fill(Color.white)
                                                    .frame(width: 4, height: 24)
                                                    .offset(x: geometry.size.width * CGFloat(normalizedPosition))
                                            }
                                        }
                                        .frame(height: 24)
                                        
                                        HStack {
                                            Text("-1.0x").font(.caption2).foregroundStyle(.secondary)
                                            Spacer()
                                            Text("1.0x").font(.caption2).foregroundStyle(.secondary)
                                            Spacer()
                                            Text("3.0x").font(.caption2).foregroundStyle(.secondary)
                                        }
                                    }
                                    .padding()
                                    .solidCard()
                                    .padding(.horizontal)
                                    
                                    // 3. Insight Box
                                    InsightBox(
                                        text: "Your Pace of Aging is currently optimal, largely influenced by your sustained HRV and low RHR. Continue your current habits to keep lowering your Biological Age.",
                                        actionText: "VIEW YOUR ANALYSIS"
                                    ) {
                                        showHealthspanDetails = true
                                    }
                                    .padding(.horizontal)
                                    
                                } else {
                                    Text("Not enough data to calculate WHOOP Age.")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .padding()
                                }
                            }
                        }
                        .padding(.vertical)
                    }
                    .scrollContentBackground(.hidden)
                }
                
                if viewModel.isLoading {
                    LoadingOverlay(message: "Analyzing your biological age...")
                }
            }
            .navigationTitle("HEALTHSPAN")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                if viewModel.modelContainer == nil {
                    viewModel.configure(container: modelContext.container)
                }
                await viewModel.analyzeData()
            }
            .refreshable {
                await viewModel.analyzeData()
            }
        }
        .sheet(isPresented: $showHealthspanDetails) {
            if let aging = viewModel.agingAssessment {
                NavigationStack {
                    ScrollView {
                        AgingAlphaCard(assessment: aging)
                            .padding()
                    }
                    .navigationTitle("Biological Aging")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showHealthspanDetails = false }
                        }
                    }
                }
                .presentationDetents([.medium, .large])
            }
        }
    }
}

#Preview {
    HealthspanTabView()
}
