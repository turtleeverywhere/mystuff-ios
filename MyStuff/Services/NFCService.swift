import Foundation
@preconcurrency import CoreNFC

struct NFCScanResult: Sendable {
    /// Parsed target if the tag's NDEF holds a universal link we recognize.
    /// After a successful write, this is the newly written target.
    let target: AppLink.Target?
    /// For writes: what the tag pointed at before being overwritten, if different.
    /// nil for pure reads and fresh writes onto a blank tag.
    let previousTarget: AppLink.Target?
    /// Hex-encoded tag serial (UID).
    let tagSerial: String
}

enum NFCError: LocalizedError {
    case unavailable
    case userCancelled
    case sessionInvalidated(String)
    case readOnlyTag
    case writeFailed(String)
    case unsupportedTag
    /// Tag carries a different target; surface to UI so the user can confirm overwrite.
    case existingPairing(target: AppLink.Target, tagSerial: String)

    var errorDescription: String? {
        switch self {
        case .unavailable: return "NFC is not available on this device."
        case .userCancelled: return "Scan cancelled."
        case .sessionInvalidated(let msg): return msg
        case .readOnlyTag: return "This tag is read-only and cannot be written."
        case .writeFailed(let msg): return "Write failed: \(msg)"
        case .unsupportedTag: return "Tag type is not supported."
        case .existingPairing: return "Tag is paired to something else."
        }
    }
}

protocol NFCService: AnyObject, Sendable {
    var isAvailable: Bool { get }
    func scan() async throws -> NFCScanResult
    func write(target: AppLink.Target, allowOverwrite: Bool) async throws -> NFCScanResult
}

// MARK: - CoreNFC implementation

final class CoreNFCService: NSObject, NFCService, @unchecked Sendable {

    /// Device-level NFC capability; false on iPad and other NFC-less devices.
    static var readingAvailable: Bool { NFCTagReaderSession.readingAvailable }

    var isAvailable: Bool { Self.readingAvailable }

    private enum Mode {
        case read
        case write(target: AppLink.Target, allowOverwrite: Bool)
    }

    private let queue = DispatchQueue(label: "com.flyingturtle.mystuff.nfc")
    private var continuation: CheckedContinuation<NFCScanResult, Error>?
    private var session: NFCTagReaderSession?
    private var mode: Mode = .read

    func scan() async throws -> NFCScanResult {
        try await begin(mode: .read, alert: "Hold your iPhone near the tag")
    }

    func write(target: AppLink.Target, allowOverwrite: Bool) async throws -> NFCScanResult {
        try await begin(
            mode: .write(target: target, allowOverwrite: allowOverwrite),
            alert: "Hold your iPhone near the tag to pair"
        )
    }

    private func begin(mode: Mode, alert: String) async throws -> NFCScanResult {
        guard NFCTagReaderSession.readingAvailable else { throw NFCError.unavailable }
        return try await withCheckedThrowingContinuation { cont in
            queue.async {
                if self.continuation != nil {
                    cont.resume(throwing: NFCError.sessionInvalidated("Session already in progress"))
                    return
                }
                self.continuation = cont
                self.mode = mode
                let s = NFCTagReaderSession(
                    pollingOption: [.iso14443, .iso15693],
                    delegate: self,
                    queue: self.queue
                )
                s?.alertMessage = alert
                self.session = s
                if let s {
                    s.begin()
                } else {
                    self.continuation = nil
                    cont.resume(throwing: NFCError.unavailable)
                }
            }
        }
    }

    private func finish(_ result: Result<NFCScanResult, Error>) {
        let cont = continuation
        continuation = nil
        session = nil
        switch result {
        case .success(let r): cont?.resume(returning: r)
        case .failure(let e): cont?.resume(throwing: e)
        }
    }

    private func handleConnected(tag: CoreNFC.NFCTag, session: NFCTagReaderSession) {
        let serial: String
        let ndefTag: NFCNDEFTag
        switch tag {
        case .miFare(let mf):
            serial = mf.identifier.hexString
            ndefTag = mf
        case .iso15693(let iso):
            serial = iso.identifier.hexString
            ndefTag = iso
        case .iso7816(let iso):
            serial = iso.identifier.hexString
            ndefTag = iso
        case .feliCa(let f):
            serial = f.currentIDm.hexString
            ndefTag = f
        @unknown default:
            session.invalidate(errorMessage: "Unsupported tag")
            finish(.failure(NFCError.unsupportedTag))
            return
        }

        nonisolated(unsafe) let unsafeTag = ndefTag
        nonisolated(unsafe) let unsafeSession = session
        unsafeTag.queryNDEFStatus { [weak self] status, _, error in
            guard let self else { return }
            self.queue.async {
                if let error {
                    unsafeSession.invalidate(errorMessage: error.localizedDescription)
                    self.finish(.failure(NFCError.sessionInvalidated(error.localizedDescription)))
                    return
                }
                guard status != .notSupported else {
                    unsafeSession.invalidate(errorMessage: "Tag does not support NDEF")
                    self.finish(.failure(NFCError.unsupportedTag))
                    return
                }
                unsafeTag.readNDEF { [weak self] message, _ in
                    guard let self else { return }
                    nonisolated(unsafe) let unsafeMessage = message
                    self.queue.async {
                        let existingTarget = Self.extractTarget(from: unsafeMessage)
                        self.afterRead(
                            serial: serial,
                            existingTarget: existingTarget,
                            status: status,
                            ndefTag: unsafeTag,
                            session: unsafeSession
                        )
                    }
                }
            }
        }
    }

    private func afterRead(
        serial: String,
        existingTarget: AppLink.Target?,
        status: NFCNDEFStatus,
        ndefTag: NFCNDEFTag,
        session: NFCTagReaderSession
    ) {
        switch mode {
        case .read:
            session.alertMessage = "Tag scanned"
            session.invalidate()
            finish(.success(NFCScanResult(target: existingTarget, previousTarget: nil, tagSerial: serial)))

        case .write(let target, let allowOverwrite):
            if let existing = existingTarget, existing != target, !allowOverwrite {
                session.invalidate(errorMessage: "Tag paired to something else")
                finish(.failure(NFCError.existingPairing(target: existing, tagSerial: serial)))
                return
            }
            guard status == .readWrite else {
                session.invalidate(errorMessage: "Tag is read-only")
                finish(.failure(NFCError.readOnlyTag))
                return
            }
            let uri = AppLink.url(for: target).absoluteString
            guard let urlPayload = NFCNDEFPayload.wellKnownTypeURIPayload(string: uri) else {
                session.invalidate(errorMessage: "Failed to encode payload")
                finish(.failure(NFCError.writeFailed("payload encoding")))
                return
            }
            let message = NFCNDEFMessage(records: [urlPayload])
            let previousTarget = (existingTarget != target) ? existingTarget : nil
            nonisolated(unsafe) let unsafeSession = session
            ndefTag.writeNDEF(message) { [weak self] error in
                guard let self else { return }
                self.queue.async {
                    if let error {
                        unsafeSession.invalidate(errorMessage: error.localizedDescription)
                        self.finish(.failure(NFCError.writeFailed(error.localizedDescription)))
                    } else {
                        unsafeSession.alertMessage = "Tag paired"
                        unsafeSession.invalidate()
                        self.finish(.success(NFCScanResult(target: target, previousTarget: previousTarget, tagSerial: serial)))
                    }
                }
            }
        }
    }

    private static func extractTarget(from message: NFCNDEFMessage?) -> AppLink.Target? {
        guard let records = message?.records else { return nil }
        for record in records {
            if let url = record.wellKnownTypeURIPayload(),
               let target = AppLink.parse(url) {
                return target
            }
        }
        return nil
    }
}

// MARK: - Delegate

extension CoreNFCService: NFCTagReaderSessionDelegate {

    func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {}

    func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        queue.async {
            guard self.continuation != nil else { return }
            if let nfcError = error as? NFCReaderError {
                switch nfcError.code {
                case .readerSessionInvalidationErrorUserCanceled,
                     .readerSessionInvalidationErrorSessionTimeout,
                     .readerSessionInvalidationErrorFirstNDEFTagRead:
                    self.finish(.failure(NFCError.userCancelled))
                    return
                default:
                    break
                }
            }
            self.finish(.failure(NFCError.sessionInvalidated(error.localizedDescription)))
        }
    }

    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [CoreNFC.NFCTag]) {
        guard let first = tags.first else {
            session.invalidate(errorMessage: "No tag detected")
            return
        }
        nonisolated(unsafe) let unsafeFirst = first
        nonisolated(unsafe) let unsafeSession = session
        session.connect(to: first) { [weak self] error in
            guard let self else { return }
            self.queue.async {
                if let error {
                    unsafeSession.invalidate(errorMessage: error.localizedDescription)
                    self.finish(.failure(NFCError.sessionInvalidated(error.localizedDescription)))
                    return
                }
                self.handleConnected(tag: unsafeFirst, session: unsafeSession)
            }
        }
    }
}

// MARK: - Helpers

private extension Data {
    var hexString: String {
        map { String(format: "%02hhX", $0) }.joined()
    }
}

// MARK: - Mock

final class MockNFCService: NFCService, @unchecked Sendable {
    var isAvailable: Bool { true }

    /// Configure for previews: nil = blank tag, set = paired tag.
    var stubTarget: AppLink.Target?
    var stubSerial: String = "MOCK01020304"

    func scan() async throws -> NFCScanResult {
        try? await Task.sleep(nanoseconds: 300_000_000)
        return NFCScanResult(target: stubTarget, previousTarget: nil, tagSerial: stubSerial)
    }

    func write(target: AppLink.Target, allowOverwrite: Bool) async throws -> NFCScanResult {
        try? await Task.sleep(nanoseconds: 300_000_000)
        if let existing = stubTarget, existing != target, !allowOverwrite {
            throw NFCError.existingPairing(target: existing, tagSerial: stubSerial)
        }
        let previous = (stubTarget != target) ? stubTarget : nil
        stubTarget = target
        return NFCScanResult(target: target, previousTarget: previous, tagSerial: stubSerial)
    }
}
