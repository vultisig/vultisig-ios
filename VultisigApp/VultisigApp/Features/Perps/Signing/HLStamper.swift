//
//  HLStamper.swift
//  VultisigApp
//
//  Nonce and expiry are stamped when the user commits to signing, not when
//  the review is built. A review holds unsigned steps; the stamper turns the
//  next one into a request at that moment:
//    - nonce from the shared `HLNonceSource` (venue-corrected time),
//    - `expiresAfter = nonce + budget`: 60 s for Fast Vault, 180 s for a
//      paired ceremony (QR, join, DKLS),
//    - a market order re-quotes its IOC price from the mark read at that
//      moment, and refuses when the mark moved past the slippage setting.
//  Steps are stamped one at a time: step 2 is never stamped while step 1 is
//  still being signed or posted.
//

import Foundation

enum HLSigningMode: Sendable, Equatable {
    case fastVault
    case paired

    var expiryBudgetMs: UInt64 {
        switch self {
        case .fastVault: return 60_000
        case .paired: return 180_000
        }
    }
}

enum HLStampError: Error, Equatable {
    /// The mark moved more than the slippage setting since the review.
    case priceMoved
    /// Less than `HLStamper.postMarginMs` left before `expiresAfter`.
    case signatureExpired
    /// The previous step has not been posted yet.
    case previousStepPending
    /// Place-then-cancel: the new trigger is not confirmed resting, so the
    /// old one is never cancelled.
    case replacementNotConfirmed
    case noStepsLeft
}

/// One action of a review, not yet tied to a nonce.
struct HLUnsignedStep: Sendable {
    enum Build: Sendable {
        /// Builds the L1 action. The argument is the mark read at stamp time
        /// (nil when the step does not depend on price, or in previews).
        case l1(@Sendable (_ freshMid: Decimal?) throws -> HLValue)
        /// User-signed actions bind the nonce into the signed fields (`time`, `nonce`).
        case userSigned(@Sendable (_ nonce: UInt64) throws -> HLUserSignedAction)
    }

    let kind: HLExchangeRequest.Kind
    let build: Build

    static func l1(_ kind: HLExchangeRequest.Kind, action: HLValue) -> HLUnsignedStep {
        HLUnsignedStep(kind: kind, build: .l1 { _ in action })
    }

    var isUserSigned: Bool {
        if case .userSigned = build { return true }
        return false
    }

    func request(nonce: UInt64, expiryBudgetMs: UInt64, freshMid: Decimal?, isMainnet: Bool) throws -> HLExchangeRequest {
        switch build {
        case .l1(let make):
            return try .l1(kind, action: try make(freshMid), nonce: nonce, isMainnet: isMainnet, expiresAfter: nonce + expiryBudgetMs)
        case .userSigned(let make):
            return .userSigned(kind, try make(nonce))
        }
    }

    /// What the review renders and the dry run records: the steps at
    /// `firstNonce`, `firstNonce + 1`, ... with the Fast Vault budget. Never signed.
    static func preview(_ steps: [HLUnsignedStep], firstNonce: UInt64, isMainnet: Bool = PerpsConfig.isMainnet) throws -> [HLExchangeRequest] {
        try steps.enumerated().map { index, step in
            try step.request(nonce: firstNonce + UInt64(index), expiryBudgetMs: HLSigningMode.fastVault.expiryBudgetMs,
                             freshMid: nil, isMainnet: isMainnet)
        }
    }
}

struct HLStamper {
    /// HL charges 5x rate limit for an expired action; refuse to post one
    /// that would arrive with less than this left.
    static let postMarginMs: UInt64 = 3_000

    let nonces: HLNonceSource
    var isMainnet: Bool = PerpsConfig.isMainnet

    func stamp(_ step: HLUnsignedStep, mode: HLSigningMode, freshMid: Decimal? = nil) throws -> HLExchangeRequest {
        try step.request(nonce: nonces.next(), expiryBudgetMs: mode.expiryBudgetMs, freshMid: freshMid, isMainnet: isMainnet)
    }

    /// The last check before a POST. User-signed actions carry no expiry.
    static func checkPostable(_ request: HLExchangeRequest, nowMs: UInt64) throws {
        guard let expiresAfter = request.expiresAfter else { return }
        guard nowMs + postMarginMs < expiresAfter else { throw HLStampError.signatureExpired }
    }
}

/// The steps of one review, stamped strictly in order.
struct HLStepSequence: Sendable {
    let steps: [HLUnsignedStep]
    /// Place-then-cancel exit edits: the cancel step waits for `confirmReplacement`.
    let cancelGate: PerpsExitCancelGate?
    private(set) var nextIndex = 0
    private var awaitingPost = false
    private var replacementConfirmed = false

    init(steps: [HLUnsignedStep], cancelGate: PerpsExitCancelGate? = nil) {
        self.steps = steps
        self.cancelGate = cancelGate
    }

    init(document: PerpsReviewDocument) {
        self.init(steps: document.steps, cancelGate: document.cancelGate)
    }

    var isFinished: Bool { nextIndex >= steps.count && !awaitingPost }

    mutating func stampNext(with stamper: HLStamper, mode: HLSigningMode, freshMid: Decimal? = nil) throws -> HLExchangeRequest {
        guard !awaitingPost else { throw HLStampError.previousStepPending }
        guard nextIndex < steps.count else { throw HLStampError.noStepsLeft }
        if cancelGate != nil, steps[nextIndex].kind == .cancel, !replacementConfirmed {
            throw HLStampError.replacementNotConfirmed
        }
        let request = try stamper.stamp(steps[nextIndex], mode: mode, freshMid: freshMid)
        awaitingPost = true
        return request
    }

    /// The stamped step was posted (or definitively failed): the next may be stamped.
    mutating func markPosted() {
        guard awaitingPost else { return }
        awaitingPost = false
        nextIndex += 1
    }

    /// Feeds the place step's resting oids and a fresh `frontendOpenOrders`
    /// read into the gate. Only `.cancelOld` unlocks the cancel step.
    @discardableResult
    mutating func confirmReplacement(placed: [Int64]?, openOrders: [HLFrontendOrder]) -> PerpsExitCancelGate.Decision? {
        guard let cancelGate else { return nil }
        let decision = cancelGate.decide(placed: placed, openOrders: openOrders)
        replacementConfirmed = decision == .cancelOld
        return decision
    }

    /// Signing or posting failed before the venue saw it: the same step is
    /// stamped again, with a fresh nonce and expiry.
    mutating func discardStamp() {
        awaitingPost = false
    }
}

enum HLRequote {
    /// Refuses when the fresh mark moved more than `slippage` from the
    /// review's reference, as a fraction of the reference.
    static func check(reviewMid: Decimal, freshMid: Decimal, slippage: Decimal) throws {
        guard reviewMid > 0, freshMid > 0 else { throw HLStampError.priceMoved }
        let moved = abs(freshMid - reviewMid) / reviewMid
        guard moved <= slippage else { throw HLStampError.priceMoved }
    }

    /// The IOC price at stamp time: from `freshMid` once it passes the check,
    /// or the review's price when no fresh mark is given.
    static func marketPrice(reviewMid: Decimal, freshMid: Decimal?, isBuy: Bool, slippage: Decimal, szDecimals: Int) throws -> Decimal {
        guard let freshMid else {
            return HLWireFormat.marketPrice(mid: reviewMid, isBuy: isBuy, slippage: slippage, szDecimals: szDecimals)
        }
        try check(reviewMid: reviewMid, freshMid: freshMid, slippage: slippage)
        return HLWireFormat.marketPrice(mid: freshMid, isBuy: isBuy, slippage: slippage, szDecimals: szDecimals)
    }
}

/// Device time corrected by the venue's clock, from the `Date` header of
/// /info responses. Expiry is checked against venue time, so a phone whose
/// clock is a few minutes off would otherwise stamp signatures that are
/// already dead, or live longer than intended.
final class HLVenueClock: @unchecked Sendable {
    static let shared = HLVenueClock()

    /// The header has 1 s resolution; smaller differences are noise.
    static let minimumOffset: TimeInterval = 2

    private let lock = NSLock()
    private var offset: TimeInterval = 0
    private let device: () -> Date

    init(device: @escaping () -> Date = Date.init) {
        self.device = device
    }

    func now() -> Date {
        device().addingTimeInterval(lock.withLock { offset })
    }

    var nowMs: UInt64 { UInt64(max(0, now().timeIntervalSince1970) * 1000) }

    func record(serverDate: Date, receivedAt: Date? = nil) {
        let difference = serverDate.timeIntervalSince(receivedAt ?? device())
        lock.withLock { offset = abs(difference) >= Self.minimumOffset ? difference : 0 }
    }

    func record(_ response: HTTPURLResponse) {
        guard let header = response.value(forHTTPHeaderField: "Date"), let date = Self.parse(header) else { return }
        record(serverDate: date)
    }

    /// RFC 7231 IMF-fixdate: "Fri, 13 Nov 2026 10:00:00 GMT".
    static func parse(_ header: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: header)
    }
}
