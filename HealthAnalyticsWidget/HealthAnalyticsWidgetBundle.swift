//
//  HealthAnalyticsWidgetBundle.swift
//  HealthAnalyticsWidget
//
//  Created by Craig Faist on 2/2/26.
//

import WidgetKit
import SwiftUI

@main
struct HealthAnalyticsWidgetBundle: WidgetBundle {
    var body: some Widget {
        HealthAnalyticsWidget()
        HealthAnalyticsWidgetControl()
    }
}
