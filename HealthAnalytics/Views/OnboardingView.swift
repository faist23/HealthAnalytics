//
//  OnboardingView.swift
//  HealthAnalytics
//
//  Created by Craig Faist on 1/25/26.
//


import SwiftUI

enum OnboardingStep {
    case welcome
    case healthKit
    case strava
    case syncing
    case featureTour
}

struct OnboardingView: View {
    @StateObject private var healthKitManager = HealthKitManager.shared
    @StateObject private var stravaManager = StravaManager.shared
    @ObservedObject private var syncManager = SyncManager.shared
    @Binding var isOnboardingComplete: Bool
    
    @State private var currentStep: OnboardingStep = .welcome
    @State private var hasRequestedHealthKit = false
    @State private var skipStrava = false
    @State private var showFeatureTour = false
    @AppStorage("hasCompletedFeatureTour") private var hasCompletedFeatureTour = false
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [Color.blue.opacity(0.1), Color.purple.opacity(0.1)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            switch currentStep {
            case .welcome:
                WelcomeStep(onContinue: { currentStep = .healthKit })
            case .healthKit:
                HealthKitStep(
                    healthKitManager: healthKitManager,
                    hasRequestedAuth: $hasRequestedHealthKit,
                    onContinue: { currentStep = .strava }
                )
            case .strava:
                StravaStep(
                    stravaManager: stravaManager,
                    onContinue: { skip in
                        skipStrava = skip
                        startInitialSync()
                    }
                )
            case .syncing:
                SyncingStep(
                    syncManager: syncManager,
                    onComplete: {
                        if !hasCompletedFeatureTour {
                            currentStep = .featureTour
                        } else {
                            completeOnboarding()
                        }
                    }
                )
            case .featureTour:
                FeatureTourStep(
                    onComplete: {
                        hasCompletedFeatureTour = true
                        completeOnboarding()
                    }
                )
            }
        }
    }
    
    private func startInitialSync() {
        currentStep = .syncing
        Task {
            await syncManager.performSmartSync()
        }
    }
    
    private func completeOnboarding() {
        withAnimation {
            isOnboardingComplete = true
        }
    }
}

// MARK: - Welcome Step

struct WelcomeStep: View {
    let onContinue: () -> Void
    
    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            
            // App Icon/Logo
            Image(systemName: "heart.text.square.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 120, height: 120)
                .foregroundStyle(.red.gradient)
                .shadow(color: .red.opacity(0.3), radius: 20)
            
            // Title
            Text("HealthAnalytics")
                .font(.system(size: 42, weight: .bold, design: .rounded))
            
            // Subtitle
            Text("Your personal health performance coach")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Spacer()
            
            // Value propositions
            VStack(alignment: .leading, spacing: 24) {
                ValuePropRow(
                    icon: "chart.line.uptrend.xyaxis",
                    color: .blue,
                    title: "Performance Trends",
                    description: "Track how your fitness evolves over time"
                )
                ValuePropRow(
                    icon: "brain.head.profile",
                    color: .purple,
                    title: "Smart Insights",
                    description: "Discover what impacts your recovery and performance"
                )
                ValuePropRow(
                    icon: "bolt.heart.fill",
                    color: .orange,
                    title: "Readiness Scores",
                    description: "Know when to push hard or take it easy"
                )
            }
            .padding(.horizontal, 24)
            
            Spacer()
            
            // Continue button
            Button(action: onContinue) {
                Text("Get Started")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(16)
                    .shadow(color: .blue.opacity(0.3), radius: 10, y: 5)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
    }
}

// MARK: - HealthKit Step

struct HealthKitStep: View {
    @ObservedObject var healthKitManager: HealthKitManager
    @Binding var hasRequestedAuth: Bool
    let onContinue: () -> Void
    
    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            
            // Icon
            Image(systemName: "heart.circle.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 100, height: 100)
                .foregroundStyle(.red.gradient)
            
            // Title
            Text("Connect HealthKit")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            // Description
            Text("We'll analyze your health data to provide personalized insights")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Spacer()
            
            // What we access
            VStack(alignment: .leading, spacing: 16) {
                Text("We'll access:")
                    .font(.headline)
                    .padding(.bottom, 4)
                
                DataAccessRow(icon: "heart.fill", text: "Heart rate & HRV")
                DataAccessRow(icon: "bed.double.fill", text: "Sleep duration")
                DataAccessRow(icon: "figure.run", text: "Workouts & activity")
                DataAccessRow(icon: "fork.knife", text: "Nutrition (optional)")
            }
            .padding(20)
            .background(Color.white.opacity(0.1))
            .cornerRadius(16)
            .padding(.horizontal, 24)
            
            Spacer()
            
            // Authorization button
            if !hasRequestedAuth || !healthKitManager.isAuthorized {
                Button(action: {
                    hasRequestedAuth = true
                    Task {
                        await healthKitManager.requestAuthorization()
                    }
                }) {
                    Text("Allow Access")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(16)
                }
                .padding(.horizontal, 24)
            }
            
            // Continue button (after authorization)
            if healthKitManager.isAuthorized {
                Button(action: onContinue) {
                    HStack {
                        Text("Continue")
                        Image(systemName: "arrow.right")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(16)
                }
                .padding(.horizontal, 24)
            }
            
            // Error message
            if let error = healthKitManager.authorizationError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal, 24)
            }
            
            Spacer()
        }
    }
}

// MARK: - Strava Step

struct StravaStep: View {
    @ObservedObject var stravaManager: StravaManager
    let onContinue: (Bool) -> Void
    @State private var isConnecting = false
    @Environment(\.openURL) private var openURL
    
    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            
            // Icon
            Image(systemName: "bicycle.circle.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 100, height: 100)
                .foregroundStyle(.orange.gradient)
            
            // Title
            Text("Connect Strava")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            // Description
            Text("Sync your Strava activities for more detailed workout analytics")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Spacer()
            
            // Benefits
            VStack(alignment: .leading, spacing: 16) {
                Text("Why connect Strava?")
                    .font(.headline)
                    .padding(.bottom, 4)
                
                BenefitRow(icon: "gauge.high", text: "Power & pace metrics")
                BenefitRow(icon: "map.fill", text: "Route & elevation data")
                BenefitRow(icon: "chart.bar.fill", text: "Detailed activity stats")
            }
            .padding(20)
            .background(Color.white.opacity(0.1))
            .cornerRadius(16)
            .padding(.horizontal, 24)
            
            Spacer()
            
            VStack(spacing: 12) {
                // Connect button
                if !stravaManager.isAuthenticated {
                    Button(action: {
                        connectToStrava()
                    }) {
                        HStack {
                            if isConnecting {
                                ProgressView()
                                    .tint(.white)
                            }
                            Text(isConnecting ? "Connecting..." : "Connect Strava")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.orange)
                        .cornerRadius(16)
                    }
                    .disabled(isConnecting)
                } else {
                    // Connected state
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Strava Connected")
                            .fontWeight(.semibold)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.green.opacity(0.2))
                    .cornerRadius(16)
                    
                    Button(action: { onContinue(false) }) {
                        HStack {
                            Text("Continue")
                            Image(systemName: "arrow.right")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(16)
                    }
                }
                
                // Skip button
                if !stravaManager.isAuthenticated {
                    Button(action: { onContinue(true) }) {
                        Text("Skip for now")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 8)
                }
            }
            .padding(.horizontal, 24)
            
            Text("You can always connect Strava later in Settings")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Spacer()
        }
    }
    
    private func connectToStrava() {
        guard let authURL = stravaManager.authorizationURL else {
            return
        }
        
        isConnecting = true
        openURL(authURL)
    }
}

// MARK: - Syncing Step

struct SyncingStep: View {
    @ObservedObject var syncManager: SyncManager
    let onComplete: () -> Void
    
    @State private var hasCompletedSync = false
    
    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            
            if !hasCompletedSync {
                // Loading state
                VStack(spacing: 24) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.blue)
                    
                    if syncManager.isBackfillingHistory {
                        VStack(spacing: 12) {
                            Text("Building Your Baseline")
                                .font(.title2)
                                .fontWeight(.bold)
                            
                            Text("Analyzing your historical health data to establish personalized trends")
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                            
                            if syncManager.backfillProgress > 0 {
                                ProgressView(value: syncManager.backfillProgress)
                                    .padding(.horizontal, 40)
                                    .padding(.top, 8)
                            }
                        }
                    } else {
                        VStack(spacing: 12) {
                            Text("Syncing Your Data")
                                .font(.title2)
                                .fontWeight(.bold)
                            
                            Text(syncManager.syncProgress.isEmpty ? "Loading your health data..." : syncManager.syncProgress)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                        }
                    }
                }
            } else {
                // Success state
                VStack(spacing: 24) {
                    Image(systemName: "checkmark.circle.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 80, height: 80)
                        .foregroundStyle(.green)
                    
                    Text("All Set!")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text("Your data has been synced successfully")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                
                Button(action: onComplete) {
                    HStack {
                        Text("Continue")
                        Image(systemName: "arrow.right")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(16)
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
            }
            
            Spacer()
        }
        .onChange(of: syncManager.isSyncing) { _, newValue in
            if !newValue && !hasCompletedSync {
                // Sync completed
                hasCompletedSync = true
            }
        }
    }
}

// MARK: - Feature Tour Step

struct FeatureTourStep: View {
    let onComplete: () -> Void
    @State private var currentPage = 0
    
    let features: [(icon: String, color: Color, title: String, description: String)] = [
        (
            "chart.line.uptrend.xyaxis",
            .blue,
            "Dashboard",
            "View your key health metrics and performance trends at a glance"
        ),
        (
            "bolt.heart.fill",
            .orange,
            "Readiness Score",
            "Get personalized recommendations on when to train hard or recover"
        ),
        (
            "lightbulb.fill",
            .yellow,
            "Insights",
            "Discover patterns and correlations in your health data"
        ),
        (
            "fork.knife",
            .green,
            "Nutrition Tracking",
            "See how your nutrition affects your performance and recovery"
        )
    ]
    
    var body: some View {
        VStack(spacing: 30) {
            HStack {
                Spacer()
                Button(action: onComplete) {
                    Text("Skip")
                        .foregroundStyle(.secondary)
                }
                .padding(.trailing, 24)
                .padding(.top, 20)
            }
            
            TabView(selection: $currentPage) {
                ForEach(features.indices, id: \.self) { index in
                    TourPageView(
                        icon: features[index].icon,
                        color: features[index].color,
                        title: features[index].title,
                        description: features[index].description
                    )
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            
            if currentPage == features.count - 1 {
                Button(action: onComplete) {
                    Text("Get Started")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(16)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
                .transition(.opacity)
            } else {
                Spacer()
                    .frame(height: 80)
            }
        }
    }
}

// MARK: - Supporting Views

struct ValuePropRow: View {
    let icon: String
    let color: Color
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color.gradient)
                .frame(width: 40, height: 40)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct DataAccessRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(.blue)
                .frame(width: 24)
            
            Text(text)
                .font(.body)
        }
    }
}

struct BenefitRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(.orange)
                .frame(width: 24)
            
            Text(text)
                .font(.body)
        }
    }
}

struct TourPageView: View {
    let icon: String
    let color: Color
    let title: String
    let description: String
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: icon)
                .resizable()
                .scaledToFit()
                .frame(width: 100, height: 100)
                .foregroundStyle(color.gradient)
                .shadow(color: color.opacity(0.3), radius: 20)
            
            VStack(spacing: 12) {
                Text(title)
                    .font(.title)
                    .fontWeight(.bold)
                
                Text(description)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            
            Spacer()
        }
    }
}

#Preview {
    OnboardingView(isOnboardingComplete: .constant(false))
}
