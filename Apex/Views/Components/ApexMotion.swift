import SwiftUI

/// Immediate, interruptible press feedback: the surface answers the finger at once and
/// springs back from wherever it is, even if released mid-press.
struct PressableStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.72), value: configuration.isPressed)
    }
}

/// Flat dashboard tile: small label, one big thing.
struct ApexTile<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: systemImage).foregroundStyle(ApexColor.accent)
                Text(title).apexLabel()
            }
            content()
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        .padding(16)
        .background(ApexColor.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

/// Picks which block of the day plan comes next.
enum PlanTiming {
    /// Minutes since midnight for "HH:MM", or nil if it is not a time.
    static func minutes(_ time: String) -> Int? {
        let parts = time.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]),
              (0..<24).contains(h), (0..<60).contains(m) else { return nil }
        return h * 60 + m
    }

    /// Index of the first block at or after `now` (minutes since midnight). If the day is over, the last block with a valid time.
    static func nextIndex(times: [String], now: Int) -> Int? {
        let valid = times.enumerated().compactMap { index, time in minutes(time).map { (index, $0) } }
        guard !valid.isEmpty else { return nil }
        return valid.first(where: { $0.1 >= now })?.0 ?? valid.last?.0
    }
}
