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
    /// The previous step has no venue answer yet.
    case previousStepPending
    /// A step was rejected: the steps after it never run.
    case sequenceAborted
    /// The venue clock offset is beyond `HLVenueClock.maxTrustedOffset`.
    case clockUntrusted
    /// Place-then-cancel: the new trigger is not confirmed resting, so the
    /// old one is never cancelled.
    case replacementNotConfirmed
    case noStepsLeft
    case missingClientOrderId
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
    /// The entry order's `cloid`, fixed when the review is built so every
    /// stamp of this step carries the same one: an ambiguous POST can be
    /// looked up with `orderStatus` by cloid instead of guessed at.
    var clientOrderId: String?
    /// Set on entry and close orders: stamping refuses without a cloid (the
    /// random source failed) rather than sign an order it could not look up.
    var requiresClientOrderId = false

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
            var action = try make(freshMid)
            if requiresClientOrderId && clientOrderId == nil { throw HLStampError.missingClientOrderId }
            if kind == .order, let clientOrderId { action = HLActions.settingClientOrderId(clientOrderId, on: action) }
            return try .l1(kind, action: action, nonce: nonce, isMainnet: isMainnet, expiresAfter: nonce + expiryBudgetMs)
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
    var clock: HLVenueClock = .shared

    func stamp(_ step: HLUnsignedStep, mode: HLSigningMode, freshMid: Decimal? = nil) throws -> HLExchangeRequest {
        // A wild Date header would move every nonce: HL accepts nonces up to
        // T+1d, so a forward clock would keep a signature live for a day.
        guard clock.isTrusted else { throw HLStampError.clockUntrusted }
        return try step.request(nonce: nonces.next(), expiryBudgetMs: mode.expiryBudgetMs, freshMid: freshMid, isMainnet: isMainnet)
    }

    /// The last check before a POST. User-signed actions carry no expiry.
    static func checkPostable(_ request: HLExchangeRequest, nowMs: UInt64) throws {
        guard let expiresAfter = request.expiresAfter else { return }
        guard nowMs + postMarginMs < expiresAfter else { throw HLStampError.signatureExpired }
    }
}

/// The steps of one review, stamped strictly in order. A step advances
/// only on a venue-confirmed success; a definitive failure aborts the rest
/// (an order must never run after its `updateLeverage` failed); an ambiguous
/// failure keeps the stamped request so the caller resends the same signed
/// body, never a new nonce.
struct HLStepSequence: Sendable {
    let steps: [HLUnsignedStep]
    /// Place-then-cancel exit edits: the cancel step waits for `confirmReplacement`.
    let cancelGate: PerpsExitCancelGate?
    private(set) var nextIndex = 0
    /// The stamped request of the current step, until the venue answers.
    private(set) var inFlight: HLExchangeRequest?
    private(set) var isAborted = false
    private var replacementConfirmed = false

    init(steps: [HLUnsignedStep], cancelGate: PerpsExitCancelGate? = nil) {
        self.steps = steps
        self.cancelGate = cancelGate
    }

    init(document: PerpsReviewDocument) {
        self.init(steps: document.steps, cancelGate: document.cancelGate)
    }

    var isFinished: Bool { isAborted || (nextIndex >= steps.count && inFlight == nil) }

    mutating func stampNext(with stamper: HLStamper, mode: HLSigningMode, freshMid: Decimal? = nil) throws -> HLExchangeRequest {
        guard !isAborted else { throw HLStampError.sequenceAborted }
        guard inFlight == nil else { throw HLStampError.previousStepPending }
        guard nextIndex < steps.count else { throw HLStampError.noStepsLeft }
        if cancelGate != nil, steps[nextIndex].kind == .cancel, !replacementConfirmed {
            throw HLStampError.replacementNotConfirmed
        }
        let request = try stamper.stamp(steps[nextIndex], mode: mode, freshMid: freshMid)
        inFlight = request
        return request
    }

    /// The venue answered `ok` for the in-flight step: the next may be stamped.
    mutating func markConfirmed() {
        guard inFlight != nil else { return }
        inFlight = nil
        nextIndex += 1
    }

    /// A definitive venue error for the in-flight step: nothing after it runs.
    mutating func markRejected() {
        inFlight = nil
        isAborted = true
    }

    /// Only when the request provably never left the device (signing was
    /// cancelled or failed before any POST): the step may be stamped again.
    /// After a POST whose outcome is unknown, resend `inFlight` instead.
    mutating func markNeverSent() {
        inFlight = nil
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
}

enum HLRequote {
    /// Refuses when the fresh mark moved more than `slippage` from the
    /// review's reference, as a fraction of the reference.
    static func check(reviewMid: Decimal, freshMid: Decimal, slippage: Decimal) throws {
        guard reviewMid > 0, freshMid > 0 else { throw HLStampError.priceMoved }
        let moved = abs(freshMid - reviewMid) / reviewMid
        guard moved <= slippage else { throw HLStampError.priceMoved }
    }

    /// The IOC price at stamp time, from `freshMid`. It is never worse than
    /// the worst price the review showed: a buy never signs a higher limit,
    /// a sell never a lower one, so a move against the user refuses instead.
    /// Without a fresh mark, the review's price.
    static func marketPrice(reviewMid: Decimal, freshMid: Decimal?, isBuy: Bool, slippage: Decimal, szDecimals: Int) throws -> Decimal {
        let reviewed = HLWireFormat.marketPrice(mid: reviewMid, isBuy: isBuy, slippage: slippage, szDecimals: szDecimals)
        guard let freshMid else { return reviewed }
        try check(reviewMid: reviewMid, freshMid: freshMid, slippage: slippage)
        let fresh = HLWireFormat.marketPrice(mid: freshMid, isBuy: isBuy, slippage: slippage, szDecimals: szDecimals)
        guard isBuy ? fresh <= reviewed : fresh >= reviewed else { throw HLStampError.priceMoved }
        return fresh
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
    /// Beyond this the header is not believed (a bad edge, a TLS-intercepting
    /// proxy): `now()` stays on device time and stamping refuses.
    static let maxTrustedOffset: TimeInterval = 300

    private let lock = NSLock()
    private var offset: TimeInterval = 0
    private let device: () -> Date

    init(device: @escaping () -> Date = Date.init) {
        self.device = device
    }

    /// Device time plus the offset, which is never more than
    /// `maxTrustedOffset`: an untrusted offset is not applied.
    func now() -> Date {
        let offset = lock.withLock { self.offset }
        return device().addingTimeInterval(abs(offset) <= Self.maxTrustedOffset ? offset : 0)
    }

    var isTrusted: Bool { abs(lock.withLock { offset }) <= Self.maxTrustedOffset }

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
