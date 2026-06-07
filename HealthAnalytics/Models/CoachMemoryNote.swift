//
//  CoachMemoryNote.swift
//  HealthAnalytics
//
//  Represents a persistent memory or constraint provided by the user to the AI Coach.
//  Used to give context to workout generation and readiness advice.
//

import Foundation
import SwiftData

@Model
class CoachMemoryNote {
    var id: UUID
    var context: String      // e.g., "Injured right knee", "Prefer morning workouts"
    var category: String     // e.g., "Injury", "Preference", "Goal", "Equipment"
    var dateAdded: Date
    var isActive: Bool       // Allows users to "resolve" an injury or change a preference without deleting it
    var expiresAt: Date?     // Phase 3: Time-To-Live (TTL)
    
    // Phase 4: Structured Ontology
    var anatomicalRegion: String? // e.g., "Lower Body: Knee", "Upper Body: Shoulder"

    init(id: UUID = UUID(), context: String, category: String, dateAdded: Date = Date(), isActive: Bool = true, expiresAt: Date? = nil, anatomicalRegion: String? = nil) {
        self.id = id
        self.context = context
        self.category = category
        self.dateAdded = dateAdded
        self.isActive = isActive
        self.expiresAt = expiresAt
        self.anatomicalRegion = anatomicalRegion
    }
    
    @Transient
    var isCurrentlyActive: Bool {
        guard isActive else { return false }
        if let expiration = expiresAt {
            return Date() < expiration
        }
        return true
    }
}
