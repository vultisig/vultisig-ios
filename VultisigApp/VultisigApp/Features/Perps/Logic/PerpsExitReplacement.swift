//
//  PerpsExitReplacement.swift
//  VultisigApp
//
//  The place-then-cancel fallback for stop loss / take profit edits. The old
//  trigger is cancelled only after the venue confirmed the new one resting
//  and it shows in `frontendOpenOrders`. If the cancel then fails, both
//  triggers stay: two reduce-only stops on one position are safe (the second
//  to fire finds no position to reduce), a position with none is not.
//

import Foundation

enum PerpsExitEditStrategy: Sendable, Equatable {
    /// One `batchModify` per edit.
    case modify
    /// Place the new trigger, confirm it rests, then cancel the old one.
    case placeThenCancel
}

struct PerpsExitCancelGate: Sendable, Equatable {
    enum Decision: Equatable, Sendable {
        /// Every new trigger is resting: the cancel step may be stamped.
        case cancelOld
        /// Not listed yet: poll `frontendOpenOrders` again.
        case waitForNewTrigger
        /// The place step did not leave a resting trigger: keep the old one,
        /// never cancel it.
        case keepOld
    }

    enum Outcome: Equatable, Sendable {
        case replaced
        /// The cancel failed after the new trigger rested: both are live
        /// ("Old stop still active · Remove").
        case bothActive
    }

    /// The triggers the cancel step removes.
    let replacedOids: [Int64]

    /// `placed`: the oids the place step's response reported resting
    /// (`HLOrderStatuses.restingOids`), nil when no response was parsed.
    func decide(placed: [Int64]?, openOrders: [HLFrontendOrder]) -> Decision {
        guard let placed, !placed.isEmpty else { return .keepOld }
        let listed = Set(openOrders.map(\.oid))
        return placed.allSatisfy(listed.contains) ? .cancelOld : .waitForNewTrigger
    }

    func outcome(cancelSucceeded: Bool) -> Outcome {
        cancelSucceeded ? .replaced : .bothActive
    }
}

/// The `statuses` of an /exchange `order` response:
/// `{"status":"ok","response":{"type":"order","data":{"statuses":[{"resting":{"oid":1}},{"error":"..."}]}}}`.
struct HLOrderStatuses: Decodable, Equatable, Sendable {
    struct Status: Decodable, Equatable, Sendable {
        struct Resting: Decodable, Equatable, Sendable { let oid: Int64 }
        struct Filled: Decodable, Equatable, Sendable { let oid: Int64 }
        let resting: Resting?
        let filled: Filled?
        let error: String?
    }

    private struct Response: Decodable {
        struct DataField: Decodable { let statuses: [Status] }
        let data: DataField?
    }

    private enum CodingKeys: String, CodingKey { case status, response }

    let isOk: Bool
    let statuses: [Status]

    init(isOk: Bool, statuses: [Status]) {
        self.isOk = isOk
        self.statuses = statuses
    }

    /// An error answer carries a plain string in `response`: no statuses.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isOk = try container.decode(String.self, forKey: .status) == "ok"
        statuses = (try? container.decode(Response.self, forKey: .response))?.data?.statuses ?? []
    }

    /// Resting trigger oids; nil unless the whole response is `ok` and every
    /// status rests (a trigger order never fills on placement).
    var restingOids: [Int64]? {
        guard isOk, !statuses.isEmpty else { return nil }
        let oids = statuses.compactMap { $0.resting?.oid }
        return oids.count == statuses.count ? oids : nil
    }
}
