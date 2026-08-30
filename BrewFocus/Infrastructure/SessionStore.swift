import Foundation

protocol SessionStoring {
    func load() throws -> FocusSnapshot
    func save(_ snapshot: FocusSnapshot) throws
}
enum SessionStoreError: LocalizedError {
    case unsupportedVersion(Int)

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            return "BrewFocus cannot read storage version \(version)."
        }
    }
}

final class JSONSessionStore: SessionStoring {
    private let fileManager: FileManager
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        fileManager: FileManager = .default,
        fileURL: URL? = nil
    ) {
        self.fileManager = fileManager

        if let fileURL {
            self.fileURL = fileURL
        } else {
            let applicationSupport = fileManager.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            )[0]
            self.fileURL = applicationSupport
                .appendingPathComponent("BrewFocus", isDirectory: true)
                .appendingPathComponent("sessions.json", isDirectory: false)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func load() throws -> FocusSnapshot {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return FocusSnapshot()
        }

        let data = try Data(contentsOf: fileURL)
        let snapshot = try decoder.decode(FocusSnapshot.self, from: data)

        guard snapshot.version == FocusSnapshot.currentVersion else {
            throw SessionStoreError.unsupportedVersion(snapshot.version)
        }

        return snapshot
    }

    func save(_ snapshot: FocusSnapshot) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL, options: .atomic)
    }
}
