import SwiftUI

enum BrewFocusStyle {
    static let espresso = Color(red: 0.55, green: 0.30, blue: 0.16)
    static let latte = Color(red: 0.69, green: 0.50, blue: 0.30)
    static let cappuccino = Color(red: 0.67, green: 0.36, blue: 0.22)
    static let americano = Color(red: 0.35, green: 0.23, blue: 0.17)
    static let crema = Color(red: 0.91, green: 0.70, blue: 0.42)
    static let warmSurface = Color(red: 0.96, green: 0.93, blue: 0.88)
}

extension CoffeeKind {
    var accentColor: Color {
        switch self {
        case .latte: BrewFocusStyle.latte
        case .cappuccino: BrewFocusStyle.cappuccino
        case .americano: BrewFocusStyle.americano
        case .espresso: BrewFocusStyle.espresso
        }
    }
}

enum DurationFormatting {
    static func timerText(seconds: Int) -> String {
        let safeSeconds = max(0, seconds)
        return String(format: "%02d:%02d", safeSeconds / 60, safeSeconds % 60)
    }

    static func shortDuration(seconds: TimeInterval) -> String {
        let totalMinutes = Int(seconds.rounded()) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0, minutes > 0 {
            return "\(hours)h \(minutes)m"
        }
        if hours > 0 {
            return "\(hours)h"
        }
        return "\(minutes)m"
    }
}
