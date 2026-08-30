import Foundation

struct AllowedApplication: Codable, Hashable, Identifiable, Sendable {
    let bundleIdentifier: String
    let name: String
    let bundleURLPath: String?

    var id: String { bundleIdentifier }
}
