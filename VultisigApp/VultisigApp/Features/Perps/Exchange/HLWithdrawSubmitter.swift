//
//  HLWithdrawSubmitter.swift
//  VultisigApp
//
//  withdraw3 is user-signed, has no `expiresAfter`, and its `time` is the
//  nonce. Re-signing after a timeout would sign a NEW nonce, and both
//  withdrawals could land. So a withdrawal is signed once:
//    reserved -> signed -> posting -> done | rejected | uncertain
//  - the signed body is persisted before the first POST,
//  - "try again" while uncertain resends that exact body (the venue applies
//    a nonce at most once, so a duplicate is refused, never paid twice),
//  - an uncertain record is reconciled against the ledger (by nonce only), and only a
//    definitive answer (`rejected`, or the nonce out of HL's window) lets a
//    new withdrawal be signed. `reserve` persists a reservation BEFORE the
//    ceremony, and `record` only accepts a signature against it, so a second
//    ceremony can never start while one is open on this device.
//  The body carries a signature: it is never logged.
//

import Foundation

struct HLPendingSubmission: Codable, Equatable, Sendable, Identifiable {
    enum State: String, Codable, Sendable {
        /// A ceremony is about to run; nothing is signed yet.
        case reserved
        case signed, posting, done, rejected, uncertain

        /// Blocks a new ceremony for the same signer.
        var isOpen: Bool { self == .reserved || self == .signed || self == .posting || self == .uncertain }
    }

    let id: UUID
    let kind: String
    let nonce: UInt64
    let digest: String
    /// The exact JSON posted, signature included.
    let body: String
    let signer: String
    /// USDC, as on the wire ("49.5").
    let amount: String
    let createdAt: Date
    var state: State
}

enum HLPostOutcome: Equatable, Sendable {
    case ok
    /// A definitive venue error for this body (insufficient withdrawable, ...):
    /// the nonce was never applied.
    case rejected(String)
    /// The venue already applied this nonce: this body, or nothing, landed.
    case nonceAlreadyUsed
    /// Timeout, dropped connection, 5xx: the venue may or may not have it.
    case transportFailure

    /// The /exchange answer: `{"status":"ok",...}` or `{"status":"err","response":"..."}`.
    static func classify(statusCode: Int?, body: Data?) -> HLPostOutcome {
        guard let statusCode, (200..<300).contains(statusCode), let body,
              let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let status = object["status"] as? String else { return .transportFailure }
        if status == "ok" { return .ok }
        let message = object["response"] as? String ?? ""
        return message.lowercased().contains("nonce") ? .nonceAlreadyUsed : .rejected(message)
    }
}

protocol HLExchangePosting: Sendable {
    func post(body: String) async -> HLPostOutcome
}

protocol HLLedgerReading: Sendable {
    func ledgerUpdates(user: String, startTimeMs: Int64) async throws -> [HLLedgerUpdate]
}

protocol HLPendingSubmissionStoring: Sendable {
    func load(signer: String) throws -> [HLPendingSubmission]
    func save(_ records: [HLPendingSubmission], signer: String) throws
}

/// One JSON file per signer under Application Support, written atomically
/// with complete file protection (unreadable while the device is locked).
struct HLFilePendingSubmissionStore: HLPendingSubmissionStoring {
    let directory: URL

    init(directory: URL? = nil) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.directory = directory ?? base.appendingPathComponent("PerpsPendingSubmissions", isDirectory: true)
    }

    private func file(for signer: String) -> URL {
        directory.appendingPathComponent(signer.lowercased() + ".json")
    }

    func load(signer: String) throws -> [HLPendingSubmission] {
        let url = file(for: signer)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode([HLPendingSubmission].self, from: Data(contentsOf: url))
    }

    func save(_ records: [HLPendingSubmission], signer: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let data = try encoder.encode(records)
        #if os(iOS)
        try data.write(to: file(for: signer), options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: file(for: signer), options: [.atomic])
        #endif
    }
}

enum HLWithdrawSubmitterError: Error, Equatable {
    case notWithdraw
    case notSigned
    /// A withdrawal for this signer is not settled yet.
    case withdrawalPending
    /// `record` without a live reservation from `reserve`.
    case noReservation
    case unknownRecord
    /// Only a signed or uncertain record is (re)posted.
    case notPostable(HLPendingSubmission.State)
}

actor HLWithdrawSubmitter {
    /// HL accepts nonces within (now - 2d, now + 1d): past that, a body that
    /// never landed can never land.
    static let nonceWindowMs: UInt64 = 2 * 86_400_000
    /// Extra wait past the window before a record is called rejected, on top
    /// of the venue-clock bound (`HLVenueClock.maxTrustedOffset`).
    static let windowMarginMs: UInt64 = 86_400_000
    /// The ledger query starts a little before the nonce.
    static let ledgerLookbackMs: UInt64 = 60_000

    private let store: HLPendingSubmissionStoring
    private let poster: HLExchangePosting
    private let ledger: HLLedgerReading
    private let nowMs: @Sendable () -> UInt64

    init(store: HLPendingSubmissionStoring, poster: HLExchangePosting, ledger: HLLedgerReading,
         nowMs: @escaping @Sendable () -> UInt64 = { HLVenueClock.shared.nowMs }) {
        self.store = store
        self.poster = poster
        self.ledger = ledger
        self.nowMs = nowMs
    }

    /// One lock for every submitter in the process, so the check for an
    /// open record and the append of a new one are a single step even if
    /// two instances share the store.
    private static let storeLock = NSLock()

    /// The record that blocks a new withdrawal, if any.
    func openRecord(signer: String) throws -> HLPendingSubmission? {
        try Self.storeLock.withLock { try store.load(signer: signer).first { $0.state.isOpen } }
    }

    /// Persisted BEFORE the signing ceremony starts: refused while any
    /// withdrawal for this signer is open, so two flows can never both reach
    /// a signature. Returns the id `record` must be given.
    func reserve(signer: String) throws -> UUID {
        let reservation = HLPendingSubmission(
            id: UUID(), kind: HLExchangeRequest.Kind.withdraw3.rawValue, nonce: 0, digest: "", body: "",
            signer: signer.lowercased(), amount: "", createdAt: Date(timeIntervalSince1970: TimeInterval(nowMs()) / 1000), state: .reserved
        )
        try mutate(signer: signer) { records in
            guard !records.contains(where: { $0.state.isOpen }) else { throw HLWithdrawSubmitterError.withdrawalPending }
            records.append(reservation)
        }
        return reservation.id
    }

    /// The ceremony ended without a signature (cancelled, failed): the
    /// reservation goes. A signed record is never released this way.
    func releaseReservation(_ id: UUID, signer: String) throws {
        try mutate(signer: signer) { records in
            records.removeAll { $0.id == id && $0.state == .reserved }
        }
    }

    /// At launch: a record left `posting` (the app died mid-request) is
    /// uncertain. A reservation never got a persisted signature, and no
    /// signature lives anywhere but that record, so it is released.
    func recoverAfterLaunch(signer: String) throws {
        try mutate(signer: signer) { records in
            records.removeAll { $0.state == .reserved }
            for index in records.indices where records[index].state == .posting { records[index].state = .uncertain }
        }
    }

    /// Persists the guarded signature, against the reservation made before
    /// the ceremony, before anything is posted.
    func record(_ request: HLExchangeRequest, signer: String, amount: String, reservation: UUID) throws -> HLPendingSubmission {
        guard request.kind == .withdraw3 else { throw HLWithdrawSubmitterError.notWithdraw }
        guard case .signed = request.signature else { throw HLWithdrawSubmitterError.notSigned }
        try request.verifySigner(expected: signer)
        let record = HLPendingSubmission(
            id: reservation, kind: request.kind.rawValue, nonce: request.nonce, digest: "0x" + request.digest.hexString,
            body: request.jsonBody, signer: signer.lowercased(), amount: amount,
            createdAt: Date(timeIntervalSince1970: TimeInterval(nowMs()) / 1000), state: .signed
        )
        try mutate(signer: signer) { records in
            guard let index = records.firstIndex(where: { $0.id == reservation && $0.state == .reserved }) else {
                throw HLWithdrawSubmitterError.noReservation
            }
            records[index] = record
        }
        return record
    }

    /// Posts a signed record, or resends an uncertain one byte for byte.
    /// Never builds, stamps or signs anything.
    func post(id: UUID, signer: String) async throws -> HLPendingSubmission.State {
        let record = try find(id, signer: signer)
        guard record.state == .signed || record.state == .uncertain else { throw HLWithdrawSubmitterError.notPostable(record.state) }
        try setState(.posting, id: id, signer: signer)
        switch await poster.post(body: record.body) {
        case .ok:
            try setState(.done, id: id, signer: signer)
        case .rejected:
            try setState(.rejected, id: id, signer: signer)
        case .transportFailure:
            try setState(.uncertain, id: id, signer: signer)
        case .nonceAlreadyUsed:
            try setState(.uncertain, id: id, signer: signer)
            return try await reconcile(id: id, signer: signer)
        }
        return try find(id, signer: signer).state
    }

    /// Looks the withdrawal up in the ledger. Found: done. Not found and the
    /// nonce is out of the venue's window: rejected, a new one may be signed.
    /// Otherwise it stays uncertain; it never times out into rejected early.
    func reconcile(id: UUID, signer: String) async throws -> HLPendingSubmission.State {
        let record = try find(id, signer: signer)
        guard record.state.isOpen, record.state != .reserved else { return record.state }
        let start = Int64(record.nonce > Self.ledgerLookbackMs ? record.nonce - Self.ledgerLookbackMs : 0)
        let updates = try await ledger.ledgerUpdates(user: signer, startTimeMs: start)
        let state: HLPendingSubmission.State
        if updates.contains(where: { Self.matches($0, record) }) {
            state = .done
        } else if nowMs() > record.nonce + Self.nonceWindowMs + Self.windowMarginMs {
            state = .rejected
        } else {
            state = .uncertain
        }
        try setState(state, id: id, signer: signer)
        return state
    }

    /// The ledger's `withdraw` entry for this record, by nonce only. An
    /// amount-and-time match could settle the record on an unrelated
    /// withdrawal of the same size and let a second one be signed while this
    /// body is still live, so an entry without a nonce never matches.
    static func matches(_ update: HLLedgerUpdate, _ record: HLPendingSubmission) -> Bool {
        update.delta.type.lowercased() == "withdraw" && update.delta.nonce == record.nonce
    }

    private func find(_ id: UUID, signer: String) throws -> HLPendingSubmission {
        guard let record = try Self.storeLock.withLock({ try store.load(signer: signer).first(where: { $0.id == id }) }) else {
            throw HLWithdrawSubmitterError.unknownRecord
        }
        return record
    }

    private func setState(_ state: HLPendingSubmission.State, id: UUID, signer: String) throws {
        try mutate(signer: signer) { records in
            guard let index = records.firstIndex(where: { $0.id == id }) else { return }
            records[index].state = state
        }
    }

    private func mutate(signer: String, _ change: (inout [HLPendingSubmission]) throws -> Void) throws {
        try Self.storeLock.withLock {
            var records = try store.load(signer: signer)
            try change(&records)
            try store.save(records, signer: signer)
        }
    }
}
