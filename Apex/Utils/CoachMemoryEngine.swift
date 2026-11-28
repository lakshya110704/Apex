import Foundation

/// Pure logic behind coach memory: what goes into the prompt, and what the coach asked to remember.
enum CoachMemoryEngine {

    struct Item: Equatable {
        let kind: CoachMemoryKind
        let text: String
        var createdAt: Date = Date()
        /// First and last day this applies, for things like "furniture shopping today at 13:30". Nil means no limit.
        var validFrom: Date? = nil
        var validUntil: Date? = nil

        func isActive(on date: Date, calendar: Calendar = .current) -> Bool {
            let day = calendar.startOfDay(for: date)
            if let validFrom, calendar.startOfDay(for: validFrom) > day { return false }
            if let validUntil, calendar.startOfDay(for: validUntil) < day { return false }
            return true
        }

        /// Past its last day, so it can be forgotten.
        func isExpired(now: Date = Date(), calendar: Calendar = .current) -> Bool {
            guard let validUntil else { return false }
            return calendar.startOfDay(for: validUntil) < calendar.startOfDay(for: now)
        }

        func isSingleDay(calendar: Calendar = .current) -> Bool {
            guard let validFrom, let validUntil else { return false }
            return calendar.isDate(validFrom, inSameDayAs: validUntil)
        }

        /// "today only", "Tue 18 Nov only", "until Sun 30 Nov", "from Wed 18 Nov", or empty.
        func scopeLabel(now: Date = Date(), calendar: Calendar = .current) -> String {
            if isSingleDay(calendar: calendar), let validFrom {
                return calendar.isDate(validFrom, inSameDayAs: now) ? "today only" : "\(CoachMemoryEngine.shortDate(validFrom)) only"
            }
            var parts: [String] = []
            if let validFrom { parts.append("from \(CoachMemoryEngine.shortDate(validFrom))") }
            if let validUntil { parts.append("until \(CoachMemoryEngine.shortDate(validUntil))") }
            return parts.joined(separator: " ")
        }

        /// "note: Furniture shopping at 13:30 (today only)", for the chip under a coach reply.
        var savedLabel: String {
            let scope = scopeLabel()
            return "\(kind.label.lowercased()): \(text)" + (scope.isEmpty ? "" : " (\(scope))")
        }
    }

    /// Most memories sent with a chat. Goals first, then the newest notes.
    static let maxMemoriesInPrompt = 25
    /// Earlier days of chat summarised in the prompt.
    static let maxPastSessions = 3
    /// Exchanges (question + answer) kept per earlier day.
    static let maxExchangesPerSession = 4
    /// Messages from today's conversation sent as real chat turns.
    static let maxCurrentMessages = 20
    /// Longest memory the coach can save.
    static let maxMemoryLength = 200

    // MARK: Prompt

    /// Tells the model how to save something. Kept short so it costs few tokens on every call.
    static func saveInstructions(today: Date = Date()) -> String {
        """
        MEMORY: Today is \(shortDate(today)) (\(isoDay(today))). If the athlete states a lasting goal, injury, limitation or preference \
        that is not already in COACH MEMORY, add it on its own line at the very end of your reply as [remember goal: ...] or [remember note: ...] \
        (one short sentence, their words). For something that matters on one day only (an appointment, feeling ill, a request to change \
        today's plan), use [remember note for YYYY-MM-DD: ...] and keep any time they gave in 24-hour form; for a temporary limit use \
        [remember note until YYYY-MM-DD: ...]. If they change their regular weekly training, add \
        [schedule tennis|gym|run|other: mon tue wed thu fri HH:MM from YYYY-MM-DD] (days required; time and start date only if they gave them). \
        To drop a session from their week, tell them to change it in Workouts, Edit plan. At most two such lines per reply. \
        Never save one-off questions or today's numbers. The app hides these lines, saves them and rebuilds today's plan.
        """
    }

    /// The block added to the system prompt. Empty when there is nothing to remember yet.
    static func promptSection(memories: [Item], history: [ChatMessage], now: Date = Date()) -> String {
        var parts: [String] = []

        let chosen = selectForPrompt(memories.filter { !$0.isExpired(now: now) })
        if !chosen.isEmpty {
            var lines = ["COACH MEMORY (from earlier conversations; hold them to their goals, respect their notes):"]
            for item in chosen {
                let scope = item.scopeLabel(now: now)
                lines.append("- \(item.kind.label): \(item.text) (\(scope.isEmpty ? "since \(shortDate(item.createdAt))" : scope))")
            }
            parts.append(lines.joined(separator: "\n"))
        }

        let recaps = pastSessionRecaps(history, now: now)
        if !recaps.isEmpty {
            parts.append("EARLIER CONVERSATIONS (most recent first; refer back when relevant, do not repeat them unprompted):\n" + recaps.joined(separator: "\n"))
        }

        return parts.joined(separator: "\n\n")
    }

    static func selectForPrompt(_ memories: [Item]) -> [Item] {
        let goals = memories.filter { $0.kind == .goal }.sorted { $0.createdAt > $1.createdAt }
        let notes = memories.filter { $0.kind == .note }.sorted { $0.createdAt > $1.createdAt }
        return Array((goals + notes).prefix(maxMemoriesInPrompt))
    }

    /// One line per earlier exchange, grouped by day, for the last few days that had a chat.
    static func pastSessionRecaps(_ history: [ChatMessage], now: Date = Date(), calendar: Calendar = .current) -> [String] {
        let today = calendar.startOfDay(for: now)
        let earlier = history
            .filter { $0.role != .system && $0.timestamp < today }
            .sorted { $0.timestamp < $1.timestamp }
        let byDay = Dictionary(grouping: earlier) { calendar.startOfDay(for: $0.timestamp) }
        let days = byDay.keys.sorted(by: >).prefix(maxPastSessions)

        return days.map { day in
            let messages = byDay[day] ?? []
            var exchanges: [String] = []
            var pendingQuestion: String?
            for message in messages {
                if message.role == .user {
                    if let q = pendingQuestion { exchanges.append("asked \"\(q)\"") }
                    pendingQuestion = clip(message.content, 120)
                } else if let q = pendingQuestion {
                    exchanges.append("asked \"\(q)\" → coach: \"\(clip(firstSentence(message.content), 160))\"")
                    pendingQuestion = nil
                }
            }
            if let q = pendingQuestion { exchanges.append("asked \"\(q)\"") }
            let kept = exchanges.suffix(maxExchangesPerSession)
            return "\(shortDate(day)): " + kept.joined(separator: "; ")
        }
    }

    /// Today's messages, newest last, capped so a long chat doesn't blow the request size.
    static func currentSession(_ history: [ChatMessage], now: Date = Date(), calendar: Calendar = .current) -> [ChatMessage] {
        let today = calendar.startOfDay(for: now)
        let todays = history.filter { $0.timestamp >= today }.sorted { $0.timestamp < $1.timestamp }
        var capped = Array(todays.filter { $0.role != .system }.suffix(maxCurrentMessages))
        // A chat must open with the user; drop a leading reply left over from the cap.
        while capped.first?.role == .assistant { capped.removeFirst() }
        // Some providers reject two turns in a row from the same side (e.g. a question whose reply failed).
        var merged: [ChatMessage] = []
        for message in capped {
            if let last = merged.last, last.role == message.role {
                merged[merged.count - 1] = ChatMessage(id: last.id, role: last.role,
                                                       content: last.content + "\n\n" + message.content,
                                                       timestamp: message.timestamp)
            } else {
                merged.append(message)
            }
        }
        return merged
    }

    // MARK: Reading the reply

    /// Splits a coach reply into the text to show and any `[remember goal|note: ...]` lines.
    /// A note can be limited in time: `[remember note for 2026-11-16: ...]`, `until ...` or `from ...`.
    static func extract(from reply: String, now: Date = Date(), calendar: Calendar = .current) -> (text: String, saves: [Item]) {
        // Lenient about what real models write: "goals", a dash instead of a colon, markdown around the line.
        let pattern = #"(?:\*\*|__|[*_`])?\[\s*remember\s+(goal|note)s?(?:\s+(for|on|until|from)\s+(\d{4}-\d{2}-\d{2}))?\s*[:\-–—]\s*([^\]]+?)\s*\](?:\*\*|__|[*_`])?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return (reply, [])
        }
        let ns = reply as NSString
        var saves: [Item] = []
        for match in regex.matches(in: reply, range: NSRange(location: 0, length: ns.length)) {
            let kind = CoachMemoryKind(rawValue: ns.substring(with: match.range(at: 1)).lowercased()) ?? .note
            let text = clip(ns.substring(with: match.range(at: 4)), maxMemoryLength)
            guard text.isNotEmpty else { continue }
            var item = Item(kind: kind, text: text, createdAt: now)
            if match.range(at: 2).location != NSNotFound,
               let date = parseDay(ns.substring(with: match.range(at: 3)), calendar: calendar) {
                switch ns.substring(with: match.range(at: 2)).lowercased() {
                case "until": item.validUntil = date
                case "from":  item.validFrom = date
                default:      item.validFrom = date; item.validUntil = date
                }
            }
            saves.append(item)
        }
        let stripped = regex.stringByReplacingMatches(in: reply, range: NSRange(location: 0, length: ns.length), withTemplate: "")
        return (tidy(stripped), saves)
    }

    /// Trims lines and collapses the gaps left where hidden tags were removed.
    static func tidy(_ text: String) -> String {
        text
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// True when `text` says the same as something already saved (case, punctuation and spacing ignored).
    static func isDuplicate(_ text: String, of existing: [String]) -> Bool {
        let key = normalized(text)
        guard key.isNotEmpty else { return true }
        return existing.contains { normalized($0) == key }
    }

    // MARK: Helpers

    static func normalized(_ text: String) -> String {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    static func clip(_ text: String, _ limit: Int) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard flat.count > limit else { return flat }
        return String(flat.prefix(limit - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }

    static func firstSentence(_ text: String) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ")
        if let end = flat.range(of: #"[.!?](\s|$)"#, options: .regularExpression) {
            return String(flat[..<end.upperBound]).trimmingCharacters(in: .whitespaces)
        }
        return flat
    }

    static func shortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE d MMM"
        return f.string(from: date)
    }

    static func isoDay(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// "2026-11-18" → the start of that day in `calendar`'s time zone.
    static func parseDay(_ text: String, calendar: Calendar = .current) -> Date? {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}
