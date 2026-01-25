//
//  Item.swift
//  HealthAnalytics
//
//  Created by Craig Faist on 1/25/26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
