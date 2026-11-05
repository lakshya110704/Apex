import Foundation
import SwiftData

enum MealType: String, Codable, CaseIterable {
    case breakfast = "Breakfast"
    case lunch     = "Lunch"
    case dinner    = "Dinner"
    case snack     = "Snack"

    var systemImage: String {
        switch self {
        case .breakfast: return "sun.rise.fill"
        case .lunch:     return "sun.max.fill"
        case .dinner:    return "moon.fill"
        case .snack:     return "leaf.fill"
        }
    }

    var defaultHour: Int {
        switch self {
        case .breakfast: return 8
        case .lunch:     return 13
        case .dinner:    return 19
        case .snack:     return 16
        }
    }
}

@Model
final class MealEntry {
    var id: UUID
    var date: Date
    var mealType: MealType
    var photoData: Data?
    var mealDescription: String
    var estimatedCalories: Int
    var proteinGrams: Double
    var carbsGrams: Double
    var fatGrams: Double
    var claudeAnalysis: String
    var xpEarned: Int

    init(
        date: Date = Date(),
        mealType: MealType = .lunch,
        photoData: Data? = nil,
        mealDescription: String = "",
        estimatedCalories: Int = 0,
        proteinGrams: Double = 0,
        carbsGrams: Double = 0,
        fatGrams: Double = 0,
        claudeAnalysis: String = "",
        xpEarned: Int = 0
    ) {
        self.id = UUID()
        self.date = date
        self.mealType = mealType
        self.photoData = photoData
        self.mealDescription = mealDescription
        self.estimatedCalories = estimatedCalories
        self.proteinGrams = proteinGrams
        self.carbsGrams = carbsGrams
        self.fatGrams = fatGrams
        self.claudeAnalysis = claudeAnalysis
        self.xpEarned = xpEarned
    }

    var macrosSummary: String {
        "P: \(Int(proteinGrams))g  C: \(Int(carbsGrams))g  F: \(Int(fatGrams))g"
    }
}
