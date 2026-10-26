//
//  BackfillProgressView.swift
//  HealthAnalytics
//
//  Progress shown while the historical baseline backfill runs.
//

import SwiftUI

struct BackfillProgressView: View {
    let progress: Double
    let message: String
    
    var body: some View {
        VStack(spacing: 20) {
            ProgressView(value: progress, total: 1.0)
                .progressViewStyle(.linear)
                .scaleEffect(x: 1, y: 2)
                .padding(.horizontal, 40)
            
            Text("Establishing 10-Year Baseline")
                .font(.headline)
            
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Text("\(Int(progress * 100))% complete")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding()
    }
}

