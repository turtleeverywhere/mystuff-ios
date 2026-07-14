import Foundation
@preconcurrency import CoreNFC

/// Item universal-link helpers used by the NFC read/write path.
/// Delegates to `AppLink` so the host and URL shape live in one place.
enum NFCLink {
    static func url(forItemId id: String) -> String {
        AppLink.url(for: .item(id)).absoluteString
    }

    /// Extract item UUID from any URL we recognize as an NFC payload.
    static func itemId(from url: URL) -> String? {
        if case .item(let id)? = AppLink.parse(url) { return id }
        return nil
    }
}

struct NFCScanResult: Sendable {
    /// Parsed item UUID if the tag's NDEF contains a `https://<host>/item/<uuid>` URI record.
    /// After a successful write, this is the newly written ID.
    let itemId: String?
    /// For write operations: the item UUID that was on the tag before overwriting (if any).
    /// For pure reads or fresh writes (blank tag), nil.
    let previousItemId: String?
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
    /// Tag carries a different item UUID; surface to UI so user can confirm overwrite.
    case existingPairing(itemId: String, tagSerial: String)

    var errorDescription: String? {
        switch self {
        case .unavailable: return "NFC is not available on this device."
        case .userCancelled: return "Scan cancelled."
        case .sessionInvalidated(let msg): return msg
        case .readOnlyTag: return "This tag is read-only and cannot be written."
        case .writeFailed(let msg): return "Write failed: \(msg)"
        case .unsupportedTag: return "Tag type is not supported."
        case .existingPairing: return "Tag is paired to another item."
        }
    }
}

protocol NFCService: AnyObject, Sendable {
    var isAvailable: Bool { get }
    func scan() async throws -> NFCScanResult
    func writeItem(id: String, allowOverwrite: Bool) async throws -> NFCScanResult
}

// MARK: - CoreNFC implementation

final class CoreNFCService: NSObject, NFCService, @unchecked Sendable {

    /// Device-level NFC capability; false on iPad and other NFC-less devices.
    static var readingAvailable: Bool { NFCTagReaderSession.readingAvailable }

    var isAvailable: Bool { Self.readingAvailable }

    private enum Mode {
        case read
        case write(payload: String, allowOverwrite: Bool)
    }

    private let queue = DispatchQueue(label: "com.flyingturtle.mystuff.nfc")
    private var continuation: CheckedContinuation<NFCScanResult, Error>?
    private var session: NFCTagReaderSession?
    private var mode: Mode = .read

    func scan() async throws -> NFCScanResult {
        try await begin(mode: .read, alert: "Hold your iPhone near the tag")
    }

    func writeItem(id: String, allowOverwrite: Bool) async throws -> NFCScanResult {
        try await begin(
            mode: .write(payload: id, allowOverwrite: allowOverwrite),
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

    private func handleConnected(tag: NFCTag, session: NFCTagReaderSession) {
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
                        let existingId = Self.extractItemId(from: unsafeMessage)
                        self.afterRead(
                            serial: serial,
                            existingId: existingId,
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
        existingId: String?,
        status: NFCNDEFStatus,
        ndefTag: NFCNDEFTag,
        session: NFCTagReaderSession
    ) {
        switch mode {
        case .read:
            session.alertMessage = "Tag scanned"
            session.invalidate()
            finish(.success(NFCScanResult(itemId: existingId, previousItemId: nil, tagSerial: serial)))

        case .write(let payload, let allowOverwrite):
            if let existing = existingId, existing != payload, !allowOverwrite {
                session.invalidate(errorMessage: "Tag paired to another item")
                finish(.failure(NFCError.existingPairing(itemId: existing, tagSerial: serial)))
                return
            }
            guard status == .readWrite else {
                session.invalidate(errorMessage: "Tag is read-only")
                finish(.failure(NFCError.readOnlyTag))
                return
            }
            let uri = NFCLink.url(forItemId: payload)
            guard let urlPayload = NFCNDEFPayload.wellKnownTypeURIPayload(string: uri) else {
                session.invalidate(errorMessage: "Failed to encode payload")
                finish(.failure(NFCError.writeFailed("payload encoding")))
                return
            }
            let message = NFCNDEFMessage(records: [urlPayload])
            let previousId = (existingId != payload) ? existingId : nil
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
                        self.finish(.success(NFCScanResult(itemId: payload, previousItemId: previousId, tagSerial: serial)))
                    }
                }
            }
        }
    }

    private static func extractItemId(from message: NFCNDEFMessage?) -> String? {
        guard let records = message?.records else { return nil }
        for record in records {
            if let url = record.wellKnownTypeURIPayload(),
               let id = NFCLink.itemId(from: url) {
                return id
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

    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
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
    var stubItemId: String?
    var stubSerial: String = "MOCK01020304"

    func scan() async throws -> NFCScanResult {
        try? await Task.sleep(nanoseconds: 300_000_000)
        return NFCScanResult(itemId: stubItemId, previousItemId: nil, tagSerial: stubSerial)
    }

    func writeItem(id: String, allowOverwrite: Bool) async throws -> NFCScanResult {
        try? await Task.sleep(nanoseconds: 300_000_000)
        if let existing = stubItemId, existing != id, !allowOverwrite {
            throw NFCError.existingPairing(itemId: existing, tagSerial: stubSerial)
        }
        let previous = (stubItemId != id) ? stubItemId : nil
        stubItemId = id
        return NFCScanResult(itemId: id, previousItemId: previous, tagSerial: stubSerial)
    }
}
