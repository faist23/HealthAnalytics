//
//  DailyNutrition.swift
//  HealthAnalytics
//
//  Created by Craig Faist on 1/26/26.
//


import Foundation

struct DailyNutrition: Identifiable {
    let id = UUID()
    let date: Date
    let totalCalories: Double
    let totalProtein: Double
    let totalCarbs: Double
    let totalFat: Double
    let totalFiber: Double?
    let totalSugar: Double?
    let totalWater: Double?
    
    // By meal
    let breakfast: MealNutrition?
    let lunch: MealNutrition?
    let dinner: MealNutrition?
    let snacks: MealNutrition?
    
    // Computed properties
    var proteinPercent: Double {
        guard totalCalories > 0 else { return 0 }
        return (totalProtein * 4) / totalCalories * 100
    }
    
    var carbsPercent: Double {
        guard totalCalories > 0 else { return 0 }
        return (totalCarbs * 4) / totalCalories * 100
    }
    
    var fatPercent: Double {
        guard totalCalories > 0 else { return 0 }
        return (totalFat * 9) / totalCalories * 100
    }
    
    var isComplete: Bool {
        // Consider complete if has reasonable calories and all macros
        totalCalories >= 1000 && totalProtein > 0 && totalCarbs > 0 && totalFat > 0
    }
    
    var formattedMacros: String {
        "\(Int(carbsPercent))% C / \(Int(fatPercent))% F / \(Int(proteinPercent))% P"
    }
}

struct MealNutrition {
    let calories: Double
    let protein: Double
    let carbs: Double
    let fat: Double
    let timestamp: Date
    
    var mealType: MealType {
        let hour = Calendar.current.component(.hour, from: timestamp)
        
        // Based on LoseIt's fixed times
        switch hour {
        case 6..<11: return .breakfast  // 9am
        case 11..<14: return .lunch     // noon
        case 14..<20: return .dinner    // 6pm
        default: return .snacks         // 10pm or other
        }
    }
    
    enum MealType: String {
        case breakfast = "Breakfast"
        case lunch = "Lunch"
        case dinner = "Dinner"
        case snacks = "Snacks"
    }
}