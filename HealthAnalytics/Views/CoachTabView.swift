//
//  CoachTabView.swift
//  HealthAnalytics
//

import SwiftUI
import SwiftData

struct CoachTabView: View {
    @StateObject private var viewModel = DashboardViewModel()
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.modelContext) private var modelContext
    @ObservedObject var syncManager = SyncManager.shared
    @State private var isFirstLoad = true
    
    var body: some View {
        NavigationStack {
            ZStack {
                TabBackgroundColor.dashboard(for: colorScheme)
                    .ignoresSafeArea()
                
                ScrollView {
                    refreshableContent
                }
                .refreshable {
                    await SyncManager.shared.performSmartSync(force: true)
                    await ReadinessRepository.shared.forceRefresh(
                        modelContext: HealthDataContainer.shared.mainContext
                    )
                }

                if viewModel.isLoading || isFirstLoad {
                    LoadingOverlay(message: "Analyzing your readiness...")
                }
            }
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Task {
                            await SyncManager.shared.performSmartSync(force: true)
                            await ReadinessRepository.shared.forceRefresh(
                                modelContext: HealthDataContainer.shared.mainContext
                            )
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .onAppear { isFirstLoad = false }
        }
    }

    @ViewBuilder
    private var refreshableContent: some View {
        VStack(spacing: 20) {
            // 1. The Master Coach Insight
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "sparkles")
                        .foregroundStyle(Color.accent)
                    Text("Master Coach")
                        .font(.headline)
                }

                Text(viewModel.readinessRecommendation.isEmpty ? "Gathering data to provide coaching insights..." : viewModel.readinessRecommendation)
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.medium)
                    .lineSpacing(4)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(colorScheme == .dark ? Color.surface : Color.white)
                    .shadow(color: .black.opacity(0.05), radius: 10, y: 5)
            )
            .padding(.horizontal)

            // 2. Quick Context Input (Coach Check-in)
            CoachCheckInView()
                .padding(.horizontal)

            // 3. Readiness Hero Card
            HeroReadinessCard(
                score: viewModel.readinessScore,
                level: viewModel.readinessLevel,
                recommendation: "", // We moved the recommendation to the top
                intraDay: viewModel.intraDayReadiness
            )
            .cardStyle(for: .recovery)
            .padding(.horizontal)

            if let metrics = viewModel.holisticMetrics {
                SupportingMetricsCard(metrics: metrics)
                    .padding(.horizontal)
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 30)
    }
}

struct CoachCheckInView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var memories: [CoachMemoryNote]
    
    @State private var showingCustomNote = false
    @State private var customNoteText = ""
    @State private var showingInjurySheet = false
    @State private var selectedAnatomicalRegion = "Lower Body: Knee"
    
    let anatomicalRegions = [
        "Upper Body: Shoulder",
        "Upper Body: Arm",
        "Lower Body: Knee",
        "Lower Body: Ankle",
        "Lower Body: Hip",
        "Core: Back",
        "Core: Abdomen",
        "General"
    ]
    
    private var activeCategories: Set<String> {
        Set(memories.filter { $0.isCurrentlyActive }.map { $0.category })
    }
    
    private func isCategoryActive(_ category: String) -> Bool {
        activeCategories.contains(category)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Anything I should know today?")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ContextChip(icon: "🤕", title: "Injury", isSelected: isCategoryActive("Injury"), action: { showingInjurySheet = true })
                    ContextChip(icon: "😫", title: "High Stress", isSelected: isCategoryActive("Stress"), action: { addContext("High life stress", category: "Stress") })
                    ContextChip(icon: "✈️", title: "Travel", isSelected: isCategoryActive("Travel"), action: { addContext("Traveling today", category: "Travel") })
                    ContextChip(icon: "✍️", title: "Custom...", isSelected: false, action: { showingCustomNote = true })
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
            }
        }
        .sheet(isPresented: $showingCustomNote) {
            NavigationView {
                Form {
                    TextField("E.g. Bad sleep environment", text: $customNoteText)
                }
                .navigationTitle("Add Context")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showingCustomNote = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            addContext(customNoteText, category: "Other")
                            customNoteText = ""
                            showingCustomNote = false
                        }
                        .disabled(customNoteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showingInjurySheet) {
            NavigationView {
                Form {
                    Picker("Affected Region", selection: $selectedAnatomicalRegion) {
                        ForEach(anatomicalRegions, id: \.self) {
                            Text($0)
                        }
                    }
                }
                .navigationTitle("Log Injury")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showingInjurySheet = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            addContext("Injured \(selectedAnatomicalRegion.lowercased())", category: "Injury", region: selectedAnatomicalRegion)
                            showingInjurySheet = false
                        }
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }
    
    private func addContext(_ text: String, category: String, region: String? = nil) {
        var expiresAt: Date? = nil
        let calendar = Calendar.current
        let now = Date()
        
        switch category {
        case "Travel":
            expiresAt = calendar.date(byAdding: .hour, value: 24, to: now)
        case "Stress":
            expiresAt = calendar.date(byAdding: .hour, value: 72, to: now)
        case "Injury":
            expiresAt = calendar.date(byAdding: .day, value: 7, to: now)
        default:
            expiresAt = nil // Custom notes or others persist until manually toggled
        }
        
        let note = CoachMemoryNote(context: text, category: category, expiresAt: expiresAt, anatomicalRegion: region)
        modelContext.insert(note)
        // Trigger a recalculation immediately
        Task {
            await ReadinessRepository.shared.forceRefresh(modelContext: modelContext)
        }
    }
}

struct ContextChip: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(icon)
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.gray.opacity(0.15) : Color.accent.opacity(0.15))
            .foregroundStyle(isSelected ? Color.gray : Color.accent)
            .clipShape(Capsule())
        }
        .disabled(isSelected)
    }
}

#Preview {
    CoachTabView()
}
