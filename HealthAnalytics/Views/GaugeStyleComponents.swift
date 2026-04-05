//
//  WhoopStyleComponents.swift
//  HealthAnalytics
//

import SwiftUI

struct CircularGauge: View {
    let title: String
    let value: String
    let subtitle: String
    let progress: Double
    let color: Color
    
    @State private var animatedProgress: Double = 0
    
    var body: some View {
        ZStack {
            // Background track
            Circle()
                .stroke(Color.white.opacity(0.1), lineWidth: 24)
                .frame(width: 250, height: 250)
            
            // Foreground progress
            Circle()
                .trim(from: 0, to: animatedProgress)
                .stroke(
                    color,
                    style: StrokeStyle(lineWidth: 24, lineCap: .round)
                )
                .frame(width: 250, height: 250)
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 1.5, dampingFraction: 0.8), value: animatedProgress)
            
            // Inner text
            VStack(spacing: 4) {
                Text(title.uppercased())
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(.secondary)
                
                Text(value)
                    .font(.system(size: 80, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                
                Text(subtitle.uppercased())
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(.primary)
            }
        }
        .padding(.vertical, 30)
        .onAppear {
            animatedProgress = progress
        }
        .onChange(of: progress) { _, newValue in
            animatedProgress = newValue
        }
    }
}

struct GaugeMetricRow: View {
    let icon: String
    let title: String
    let value: String
    let trendIcon: String? // e.g., "arrowtriangle.up.fill"
    let trendColor: Color
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(.secondary)
                .frame(width: 24)
            
            Text(title.uppercased())
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .tracking(1)
                .foregroundStyle(.primary)
            
            Spacer()
            
            HStack(spacing: 6) {
                Text(value)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                
                if let trendIcon = trendIcon {
                    Image(systemName: trendIcon)
                        .font(.system(size: 10))
                        .foregroundStyle(trendColor)
                }
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 20)
    }
}

struct MetricList<Content: View>: View {
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(white: 0.1).opacity(0.8))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }
}

struct InsightBox: View {
    let text: String
    let actionText: String?
    var action: (() -> Void)? = nil
    
    var body: some View {
        Group {
            if let action = action {
                Button(action: action) {
                    content
                }
                .buttonStyle(.plain)
            } else {
                content
            }
        }
    }
    
    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(text)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.primary)
                .lineSpacing(4)
                .multilineTextAlignment(.leading)
            
            if let actionText = actionText {
                HStack(spacing: 4) {
                    Text(actionText.uppercased())
                        .font(.system(size: 13, weight: .bold))
                        .tracking(1)
                    
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(Color(red: 0.6, green: 0.6, blue: 1.0)) // Purplish accent
                .padding(.top, 4)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(white: 0.1).opacity(0.8))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color(red: 0.6, green: 0.4, blue: 1.0), Color(red: 0.4, green: 0.8, blue: 1.0)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }
}
