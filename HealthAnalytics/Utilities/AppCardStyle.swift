//
//  AppCardStyle.swift
//  HealthAnalytics
//
//  Created by Craig Faist on 1/28/26.
//


import SwiftUI

struct AppCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 5)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color(.separator).opacity(0.5), lineWidth: 0.5)
            )
    }
}

extension View {
    func appCardStyle() -> some View {
        self.modifier(AppCardStyle())
    }
}