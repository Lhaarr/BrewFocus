import Foundation

enum CoffeeKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case latte
    case cappuccino
    case americano
    case espresso

    var id: String { rawValue }

    var name: String {
        switch self {
        case .latte: "Latte"
        case .cappuccino: "Cappuccino"
        case .americano: "Americano"
        case .espresso: "Espresso"
        }
    }

    var focusLabel: String {
        switch self {
        case .latte: "Light focus"
        case .cappuccino: "Normal focus"
        case .americano: "Strong focus"
        case .espresso: "Deep focus"
        }
    }

    var duration: TimeInterval {
        switch self {
        case .latte: 25 * 60
        case .cappuccino: 30 * 60
        case .americano: 45 * 60
        case .espresso: 30 * 60
        }
    }

    var restrictionMode: ApplicationRestrictionMode {
        switch self {
        case .latte: .none
        case .cappuccino: .blockList
        case .americano, .espresso: .allowList
        }
    }

    var applicationSelectionRange: ClosedRange<Int> {
        switch self {
        case .latte: 0...0
        case .cappuccino: 1...4
        case .americano: 1...8
        case .espresso: 1...4
        }
    }
}

enum ApplicationRestrictionMode: String, Codable, Sendable {
    case none
    case blockList
    case allowList
}

struct ApplicationRestriction: Equatable, Sendable {
    let mode: ApplicationRestrictionMode
    let bundleIdentifiers: Set<String>

    func restricts(bundleIdentifier: String) -> Bool {
        switch mode {
        case .none:
            false
        case .blockList:
            bundleIdentifiers.contains(bundleIdentifier)
        case .allowList:
            !bundleIdentifiers.contains(bundleIdentifier)
        }
    }
}
