import SwiftUI
import Foundation

// MARK: - View Modifiers

extension View {
    /// Heavy condensed face for big numbers and screen titles.
    func apexDisplay(_ size: CGFloat) -> some View {
        self.font(.system(size: size, weight: .heavy)).fontWidth(.condensed)
    }

    /// Small uppercase section label.
    func apexLabel() -> some View {
        self.font(.caption.weight(.heavy))
            .tracking(1.2)
            .textCase(.uppercase)
            .foregroundStyle(ApexColor.textSecondary)
    }

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
    /// "today only" → "Today only"
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
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

// MARK: - Coach replies

/// Shows a model's markdown (bold, italics, code, links) instead of literal asterisks.
/// Headings become bold lines and list markers become bullets, since SwiftUI's Text only renders inline markdown.
enum CoachMarkdown {
    static func attributed(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: normalizedBlocks(text), options: options)) ?? AttributedString(text)
    }

    static func normalizedBlocks(_ text: String) -> String {
        text.components(separatedBy: "\n").map { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let heading = trimmed.range(of: #"^#{1,6}\s+"#, options: .regularExpression) {
                let title = trimmed[heading.upperBound...].trimmingCharacters(in: CharacterSet(charactersIn: "* "))
                return title.isEmpty ? "" : "**\(title)**"
            }
            if let bullet = trimmed.range(of: #"^[-*+]\s+"#, options: .regularExpression) {
                return "• " + trimmed[bullet.upperBound...]
            }
            return line
        }.joined(separator: "\n")
    }
}
