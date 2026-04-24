//
//  TrainingView.swift
//  HealthAnalytics
//
//  New Training tab showing activity, balance, and load
//

import SwiftUI
import SwiftData

struct TrainingView: View {
    @StateObject private var viewModel = TrainingViewModel()
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.modelContext) private var modelContext
    @ObservedObject var syncManager = SyncManager.shared
    
    var body: some View {
        ZStack {
            TabBackgroundColor.recovery(for: colorScheme)
                .ignoresSafeArea()
            
            Group {
                if syncManager.isBackfillingHistory {
                    LoadingOverlay(message: syncManager.syncProgress)
                } else if viewModel.isLoading {
                    LoadingOverlay(message: "Analyzing training...")
                } else if let error = viewModel.errorMessage {
                    ErrorView(message: error)
                        .cardStyle(for: .error)
                        .padding()
                } else {
                    trainingContent
                }
            }
        }
        .navigationTitle("Training")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        await viewModel.loadTrainingData(modelContext: modelContext)
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(viewModel.isLoading)
            }
        }
        .task {
            if viewModel.modelContainer == nil {
                viewModel.configure(container: modelContext.container)
            }
            await viewModel.loadTrainingData(modelContext: modelContext)
        }
        .onChange(of: modelContext) { _, _ in
            if viewModel.modelContainer == nil {
                viewModel.configure(container: modelContext.container)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("DataSyncCompleted"))) { _ in
            Task {
                await viewModel.loadTrainingData(modelContext: modelContext)
            }
        }
    }
    
    // MARK: - Training Content
    
    @ViewBuilder
    private var trainingContent: some View {
        ScrollView {
            VStack(spacing: .spacingLg) {
                // Section 1: Activity Overview
                VStack(alignment: .leading, spacing: .spacingMd) {
                    Text("Activity")
                        .font(.title2)
                        .fontWeight(.bold)
                        .padding(.horizontal)
                    
                    // MET Activity Card
                    if let metSummary = viewModel.metSummary {
                        METActivityCard(summary: metSummary)
                            .padding(.horizontal)
                    } else {
                        EmptyActivityCard()
                            .padding(.horizontal)
                    }
                    
                    // Balanced Training Card
                    if let balance = viewModel.trainingBalance {
                        BalancedTrainingCard(balance: balance)
                            .padding(.horizontal)
                    } else {
                        EmptyBalanceCard()
                            .padding(.horizontal)
                    }
                    
                    // Cycling Compound Score Card
                    if let powerAnalysis = viewModel.compoundScoreAnalysis {
                        CyclingCompoundScoreCard(analysis: powerAnalysis)
                            .padding(.horizontal)
                    }
                }
                
                // Section 2: Load Management
                VStack(alignment: .leading, spacing: .spacingMd) {
                    Text("Load Management")
                        .font(.title2)
                        .fontWeight(.bold)
                        .padding(.horizontal)
                    
                    // Training Load Summary
                    if let load = viewModel.trainingLoad {
                        TrainingLoadSummaryCard(load: load)
                            .padding(.horizontal)
                    } else {
                        EmptyLoadCard()
                            .padding(.horizontal)
                    }
                    
                    // Note: Add navigation links to detailed views when needed
                    // NavigationLink to TrainingLoadVisualizationView (requires data)
                    // NavigationLink to UnifiedWorkoutsView
                }
                
                Spacer(minLength: 40)
            }
            .padding(.vertical)
        }
    }
}

// MARK: - Training Load Summary Card

struct TrainingLoadSummaryCard: View {
    let load: TrainingLoadCalculator.TrainingLoadSummary
    
    var body: some View {
        VStack(alignment: .leading, spacing: .spacingMd) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: .spacingXs) {
                    Text("Training Load")
                        .font(.headline)
                    Text(load.status.emoji + " " + statusLabel)
                        .font(.subheadline)
                        .foregroundStyle(load.status.color)
                }
                
                Spacer()
                
                // ACWR
                VStack(spacing: .spacingXs) {
                    Text(String(format: "%.2f", load.acuteChronicRatio))
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundStyle(load.status.color)
                    Text("ACWR")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            // Load bars
            VStack(spacing: 12) {
                LoadBar(label: "Acute (7d)", value: load.acuteLoad, color: .blue)
                LoadBar(label: "Chronic (28d)", value: load.chronicLoad, color: .purple)
            }
            
            // Weekly TSS
            HStack {
                Text("Weekly TSS:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.0f", load.weeklyTSS))
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            
            // Recommendation
            Text(load.recommendation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, .spacingSm)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: .radiusMd)
                .fill(Color(uiColor: .systemBackground))
                .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
        )
    }
    
    private var statusLabel: String {
        switch load.status {
        case .fresh: return "Fresh"
        case .optimal: return "Optimal"
        case .fatigued: return "Fatigued"
        case .overreaching: return "Overreaching"
        }
    }
}

struct LoadBar: View {
    let label: String
    let value: Double
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: .spacingXs) {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.1f", value))
                    .font(.caption)
                    .fontWeight(.semibold)
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.textTertiary.opacity(0.15))

                    RoundedRectangle(cornerRadius: 3)
                        .fill(color)
                        .frame(width: min(geometry.size.width, geometry.size.width * (value / 100)))
                }
            }
            .frame(height: 6)
        }
    }
}

// MARK: - Empty State Cards

struct EmptyActivityCard: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "figure.run")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No Activity Data")
                .font(.headline)
            Text("Complete workouts to see your weekly MET activity")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.spacingXl)
        .background(
            RoundedRectangle(cornerRadius: .radiusMd)
                .fill(Color(uiColor: .systemBackground))
                .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
        )
    }
}

struct EmptyBalanceCard: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "figure.mixed.cardio")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No Balance Data")
                .font(.headline)
            Text("Track endurance and strength training to see your balance")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.spacingXl)
        .background(
            RoundedRectangle(cornerRadius: .radiusMd)
                .fill(Color(uiColor: .systemBackground))
                .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
        )
    }
}

struct EmptyLoadCard: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "gauge")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No Load Data")
                .font(.headline)
            Text("Complete workouts to track your training load")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.spacingXl)
        .background(
            RoundedRectangle(cornerRadius: .radiusMd)
                .fill(Color(uiColor: .systemBackground))
                .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
        )
    }
}

#Preview {
    NavigationStack {
        TrainingView()
    }
}
