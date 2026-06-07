//
//  ErrorView.swift
//  HealthAnalytics
//
//  Extracted from the deleted ContentView.swift during the Phase 1.4 cleanup.
//  Still consumed by RecoveryTabView, StrainTabView, InsightsView,
//  HealthspanTabView, TrainingView, and ReadinessView.
//

import SwiftUI

struct ErrorView: View {
    let message: String
    var retryAction: (() -> Void)?

    var body: some View {
        VStack(spacing: .spacingMd) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 60))
                .foregroundStyle(Color.statusWarning)

            Text("Error")
                .font(.title3)
                .fontWeight(.semibold)

            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            if let retry = retryAction {
                Button(action: retry) {
                    Label("Try Again", systemImage: "arrow.clockwise")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .padding(.horizontal, .spacingLg)
                        .padding(.vertical, .spacingSm)
                        .background(Color.accent, in: Capsule())
                        .foregroundStyle(.white)
                }
                .padding(.top, .spacingXs)
            }
        }
        .padding(.spacingLg)
    }
}
