import SwiftUI
import Foundation

// MARK: - View Modifiers

extension View {
    func apexCard(padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .background(ApexColor.cardBg)
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    func apexCard2(padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .background(ApexColor.cardBg2)
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Date

extension Date {
    var isToday: Bool { Calendar.current.isDateInToday(self) }
    var isYesterday: Bool { Calendar.current.isDateInYesterday(self) }

    var shortTime: String {
        let f = DateFormatter()
        f.timeStyle = .short
        return f.string(from: self)
    }

    var mediumDate: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: self)
    }

    var dayAndMonth: String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: self)
    }

    var weekdayName: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        return f.string(from: self)
    }

    func isSameDay(as other: Date) -> Bool {
        Calendar.current.isDate(self, inSameDayAs: other)
    }

    var startOfDay: Date { Calendar.current.startOfDay(for: self) }
}

// MARK: - Int / Double formatting

extension Int {
    var xpString: String { "\(self) XP" }
    var caloriesString: String { "\(self) kcal" }
    var minutesString: String { "\(self) min" }
    func nonZeroOr(_ fallback: Int) -> Int { self == 0 ? fallback : self }
}

extension Double {
    var gramsString: String { String(format: "%.0fg", self) }
    var hoursString: String { String(format: "%.1fh", self) }
    var bpmString: String { String(format: "%.0f bpm", self) }
}

// MARK: - Color helpers

extension Color {
    static func workoutTypeColor(_ type: WorkoutType) -> Color {
        switch type {
        case .tennis: return ApexColor.tennis
        case .gym:    return ApexColor.accent
        case .run:    return ApexColor.accentCyan
        case .other:  return ApexColor.textSecondary
        }
    }
}

// MARK: - String

extension String {
    var isNotEmpty: Bool { !isEmpty }
}

// MARK: - Color interpolation

extension Color {
    static func lerp(_ a: Color, _ b: Color, _ t: Double) -> Color {
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        UIColor(a).getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        UIColor(b).getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        let clamped = max(0, min(1, t))
        return Color(
            red: Double(ar) + (Double(br) - Double(ar)) * clamped,
            green: Double(ag) + (Double(bg) - Double(ag)) * clamped,
            blue: Double(ab) + (Double(bb) - Double(ab)) * clamped
        )
    }
}
