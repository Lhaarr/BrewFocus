@preconcurrency import CoreNFC
import Foundation

enum FocusTagCompatibility {
    static func accepts(_ family: NFCMiFareFamily, identifier: Data) -> Bool {
        // Core NFC's `unknown` means a compatible ISO14443 Type A tag,
        // not an unreadable tag. This feature needs its UID, not chip-specific commands.
        !identifier.isEmpty && (family == .ultralight || family == .unknown)
    }

    static func name(of family: NFCMiFareFamily) -> String {
        switch family {
        case .unknown: "ISO14443-A (unspecified family)"
        case .ultralight: "MIFARE Ultralight / NTAG-compatible"
        case .plus: "MIFARE Plus"
        case .desfire: "MIFARE DESFire"
        @unknown default: "MIFARE family \(family.rawValue)"
        }
    }

    static func name(of tag: NFCTag) -> String {
        switch tag {
        case .miFare(let tag): name(of: tag.mifareFamily)
        case .iso7816: "ISO7816"
        case .iso15693: "ISO15693"
        case .feliCa: "FeliCa"
        @unknown default: "Unrecognized NFC technology"
        }
    }
}

@MainActor
final class FocusTagReader: NSObject, ObservableObject, NFCTagReaderSessionDelegate {
    @Published private(set) var isScanning = false
    @Published var errorMessage: String?
    @Published private(set) var lastDetectedTagType: String?

    static var isAvailable: Bool { NFCTagReaderSession.readingAvailable }
    private var session: NFCTagReaderSession?
    private var onTag: ((Data) throws -> String)?
    private var isProcessing = false
    private var handledResult = false
    private var scanID = UUID()

    func scan(message: String, onTag: @escaping (Data) throws -> String) {
        guard !isScanning else { return }
        guard Self.isAvailable else {
            errorMessage = "NFC scanning needs a supported physical iPhone. It is unavailable in the simulator."
            return
        }
        errorMessage = nil
        lastDetectedTagType = nil
        handledResult = false
        scanID = UUID()
        isProcessing = false
        self.onTag = onTag
        let reader = NFCTagReaderSession(pollingOption: .iso14443, delegate: self, queue: .main)
        session = reader
        isScanning = reader != nil
        reader?.alertMessage = message
        reader?.begin()
    }

    func cancel() {
        handledResult = true
        onTag = nil
        session?.invalidate()
    }

    nonisolated func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {}

    nonisolated func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        Task { @MainActor in
            guard self.session === session else { return }
            let cancelled = (error as? NFCReaderError)?.code == .readerSessionInvalidationErrorUserCanceled
            if !self.handledResult && !cancelled {
                self.errorMessage = error.localizedDescription
            }
            self.session = nil
            self.onTag = nil
            self.isScanning = false
            self.isProcessing = false
        }
    }

    nonisolated func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        Task { @MainActor in
            guard self.session === session, !self.isProcessing, !self.handledResult else { return }
            guard tags.count == 1, let tag = tags.first else {
                session.alertMessage = "Move the other tags away. Scan just one Focus Tag."
                session.restartPolling()
                return
            }
            let detectedType = FocusTagCompatibility.name(of: tag)
            self.lastDetectedTagType = detectedType
            guard case let .miFare(mifare) = tag,
                  FocusTagCompatibility.accepts(mifare.mifareFamily, identifier: mifare.identifier) else {
                self.handledResult = true
                session.invalidate(errorMessage: "Detected: \(detectedType). This tag type or its identifier is unsupported. Use your NTAG sticker.")
                return
            }
            self.isProcessing = true
            let currentScanID = self.scanID
            let identifier = mifare.identifier
            session.connect(to: tag) { error in
                Task { @MainActor in
                    guard self.scanID == currentScanID, let currentSession = self.session,
                          !self.handledResult else { return }
                    self.handledResult = true
                    if let error {
                        currentSession.invalidate(errorMessage: error.localizedDescription)
                        return
                    }
                    do {
                        guard let action = self.onTag else { return }
                        currentSession.alertMessage = try action(identifier)
                        self.onTag = nil
                        currentSession.invalidate()
                    } catch {
                        currentSession.invalidate(errorMessage: error.localizedDescription)
                    }
                }
            }
        }
    }
}
