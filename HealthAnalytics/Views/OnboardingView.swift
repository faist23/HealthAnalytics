//
//  OnboardingView.swift
//  HealthAnalytics
//
//  Created by Craig Faist on 1/25/26.
//


import SwiftUI

struct OnboardingView: View {
    @StateObject private var healthKitManager = HealthKitManager.shared
    @Binding var isOnboardingComplete: Bool
    
    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            
            // App Icon/Logo
            Image(systemName: "heart.text.square.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 100, height: 100)
                .foregroundStyle(.red.gradient)
            
            // Title
            Text("HealthAnalytics")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            // Subtitle
            Text("Unlock insights from your health data")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Spacer()
            
            // Features list
            VStack(alignment: .leading, spacing: 20) {
                FeatureRow(icon: "chart.line.uptrend.xyaxis", 
                          text: "Track performance trends over time")
                FeatureRow(icon: "brain.head.profile", 
                          text: "Discover correlations in your data")
                FeatureRow(icon: "figure.run", 
                          text: "Optimize training and recovery")
            }
            .padding()
            
            Spacer()
            
            // Authorization button
            Button(action: {
                Task {
                    await healthKitManager.requestAuthorization()
                    if healthKitManager.isAuthorized {
                        isOnboardingComplete = true
                    }
                }
            }) {
                Text("Connect HealthKit")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(12)
            }
            .padding(.horizontal)
            
            // Error message
            if let error = healthKitManager.authorizationError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal)
            }
            
            Spacer()
        }
        .padding()
    }
}

struct FeatureRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 15) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 30)
            
            Text(text)
                .font(.body)
        }
    }
}

#Preview {
    OnboardingView(isOnboardingComplete: .constant(false))
}