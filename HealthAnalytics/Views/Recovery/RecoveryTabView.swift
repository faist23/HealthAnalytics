//
//  RecoveryTabView.swift
//  HealthAnalytics
//
//  Created by Craig Faist on 1/28/26.
//

import SwiftUI

struct RecoveryTabView: View {
    @State private var selectedView: RecoverySection = .dashboard
    
    enum RecoverySection: String, CaseIterable, Identifiable {
        case dashboard = "Dashboard"
        case calendar = "Calendar"
        case timeline = "Timeline"
        case workouts = "Workouts"
        
        var id: String { rawValue }
        
        var icon: String {
            switch self {
            case .dashboard: return "gauge.with.dots.needle.67percent"
            case .calendar: return "calendar"
            case .timeline: return "chart.xyaxis.line"
            case .workouts: return "figure.run"
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Custom segmented control
                RecoverySegmentedControl(selection: $selectedView)
                    .padding()
                    .background(Color(.systemBackground))
                
                // Content views
                TabView(selection: $selectedView) {
                    RecoveryDashboardView()
                        .tag(RecoverySection.dashboard)
                    
                    PerformanceCalendarView()
                        .tag(RecoverySection.calendar)
                    
                    TimelineView()
                        .tag(RecoverySection.timeline)
                    
                    UnifiedWorkoutsView()
                        .tag(RecoverySection.workouts)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .navigationTitle("Recovery")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

// MARK: - Custom Segmented Control

struct RecoverySegmentedControl: View {
    @Binding var selection: RecoveryTabView.RecoverySection
    @Namespace private var animation
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(RecoveryTabView.RecoverySection.allCases) { section in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selection = section
                    }
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: section.icon)
                            .font(.title3)
                        
                        Text(section.rawValue)
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundStyle(selection == section ? .white : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background {
                        if selection == section {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.blue.gradient)
                                .matchedGeometryEffect(id: "selection", in: animation)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.systemGray6))
        )
    }
}

#Preview {
    RecoveryTabView()
}
