//
//  LoadingIndicators.swift
//  HealthAnalytics
//
//  Reusable loading indicators for better UX during data operations
//

import SwiftUI

// MARK: - Full Screen Loading Overlay

struct LoadingOverlay: View {
    let message: String
    let showProgress: Bool
    let progress: Double?
    
    init(
        message: String = "Loading...",
        showProgress: Bool = false,
        progress: Double? = nil
    ) {
        self.message = message
        self.showProgress = showProgress
        self.progress = progress
    }
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                if showProgress, let progress = progress {
                    // Progress ring with percentage
                    ZStack {
                        Circle()
                            .stroke(Color.gray.opacity(0.2), lineWidth: 8)
                            .frame(width: 80, height: 80)
                        
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(
                                LinearGradient(
                                    colors: [.blue, .cyan],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                style: StrokeStyle(lineWidth: 8, lineCap: .round)
                            )
                            .frame(width: 80, height: 80)
                            .rotationEffect(.degrees(-90))
                            .animation(.easeInOut(duration: 0.3), value: progress)
                        
                        Text("\(Int(progress * 100))%")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary)
                    }
                } else {
                    // Spinner
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.blue)
                }
                
                VStack(spacing: 8) {
                    Text(message)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                    
                    if showProgress {
                        Text("Please wait...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(40)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThickMaterial)
                    .shadow(color: .black.opacity(0.2), radius: 30, y: 10)
            )
            .padding(.horizontal, 40)
        }
    }
}

// MARK: - Inline Loading View

struct InlineLoadingView: View {
    let message: String
    let compact: Bool
    
    init(message: String = "Loading...", compact: Bool = false) {
        self.message = message
        self.compact = compact
    }
    
    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .scaleEffect(compact ? 0.8 : 1.0)
            
            Text(message)
                .font(compact ? .caption : .subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(compact ? 12 : 20)
    }
}

// MARK: - Sync Progress Card

struct SyncProgressCard: View {
    let title: String
    let message: String
    let progress: Double?
    let details: String?
    
    init(
        title: String = "Syncing Data",
        message: String,
        progress: Double? = nil,
        details: String? = nil
    ) {
        self.title = title
        self.message = message
        self.progress = progress
        self.details = details
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(.blue.opacity(0.1))
                        .frame(width: 40, height: 40)
                    
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(Color.blue)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
            }
            
            if let progress = progress {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: progress, total: 1.0)
                        .tint(.blue)
                    
                    HStack {
                        Text("\(Int(progress * 100))% complete")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                        
                        if let details = details {
                            Text(details)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } else if let details = details {
                Text(details)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        )
    }
}

// MARK: - Settings Loading Button

struct SettingsLoadingButton: View {
    let title: String
    let isLoading: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: {
            if !isLoading {
                action()
            }
        }) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                }
                
                Text(title)
                    .foregroundStyle(isLoading ? Color.secondary : Color.blue)
            }
        }
        .disabled(isLoading)
    }
}

// MARK: - Shimmer Loading Effect

struct ShimmerLoadingView: View {
    @State private var phase: CGFloat = 0
    let height: CGFloat
    
    init(height: CGFloat = 100) {
        self.height = height
    }
    
    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(
                LinearGradient(
                    colors: [
                        Color.gray.opacity(0.1),
                        Color.gray.opacity(0.2),
                        Color.gray.opacity(0.1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: height)
            .mask(
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.clear, .white, .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .offset(x: phase)
            )
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    phase = 400
                }
            }
    }
}

// MARK: - Preview

#Preview("Loading Overlay") {
    ZStack {
        Color.blue.opacity(0.3)
            .ignoresSafeArea()
        
        LoadingOverlay(message: "Analyzing readiness...")
    }
}

#Preview("Loading Overlay Progress") {
    ZStack {
        Color.blue.opacity(0.3)
            .ignoresSafeArea()
        
        LoadingOverlay(
            message: "Syncing HealthKit data",
            showProgress: true,
            progress: 0.65
        )
    }
}

#Preview("Inline Loading") {
    VStack(spacing: 20) {
        InlineLoadingView(message: "Loading workouts...")
        InlineLoadingView(message: "Syncing...", compact: true)
    }
    .padding()
}

#Preview("Sync Progress Card") {
    VStack(spacing: 16) {
        SyncProgressCard(
            message: "Fetching HealthKit workouts",
            progress: 0.45,
            details: "245 of 500 workouts"
        )
        
        SyncProgressCard(
            title: "Processing",
            message: "Analyzing performance patterns",
            details: "This may take a few moments..."
        )
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}

#Preview("Shimmer Loading") {
    VStack(spacing: 16) {
        ShimmerLoadingView(height: 100)
        ShimmerLoadingView(height: 60)
        ShimmerLoadingView(height: 80)
    }
    .padding()
}
