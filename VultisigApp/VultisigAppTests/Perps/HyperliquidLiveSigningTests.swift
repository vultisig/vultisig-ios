//
//  HyperliquidLiveSigningTests.swift
//  VultisigAppTests
//
//  Groundwork for live signing, all offline:
//    - stamping nonce + expiry at sign time, re-quote, expiry guard, ordering,
//    - one-action stop loss / take profit edits and the place-then-cancel gate,
//    - batchModify / noop parity with the Python SDK,
//    - withdraw3 sign-once, resend-the-same-body, ledger reconcile.
//

import WalletCore
import XCTest
@testable import VultisigApp

final class HyperliquidLiveSigningTests: XCTestCase {
    private static let nonce: UInt64 = 1_731_400_000_000
    private static let sdkTestKey = "0123456789012345678901234567890123456789012345678901234567890123"

    private func market(mid: Decimal = 66_969) -> PerpsMarket {
        PerpsMarket(assetIndex: 0, coin: "BTC", szDecimals: 5, maxLeverage: 40, onlyIsolated: false, markPrice: mid,
                    midPrice: mid, previousDayPrice: 66_000, hourlyFunding: 0, openInterest: 1, dayVolume: 1, marginTiers: [])
    }

    private func ticket(leverage: Int = 2) -> PerpsTicket {
        PerpsTicket(side: .long, margin: 100, leverage: leverage, marginMode: .isolated, limitPrice: nil, takeProfit: nil, stopLoss: 62_000)
    }

    private func position() throws -> HLPosition {
        let json = #"{"coin":"BTC","szi":"0.002","leverage":{"type":"isolated","value":2},"entryPx":"66000","#
            + #""positionValue":"133.9","unrealizedPnl":"1.94","returnOnEquity":"0.03","liquidationPx":"33500","marginUsed":"67.9","maxLeverage":40}"#
        return try JSONDecoder().decode(HLPosition.self, from: Data(json.utf8))
    }

    private func trigger(oid: Int64, price: String, stop: Bool) throws -> HLFrontendOrder {
        let json = #"{"coin":"BTC","oid":\#(oid),"side":"A","sz":"0.0","limitPx":"\#(price)","triggerPx":"\#(price)","isTrigger":true,"#
            + #""isPositionTpsl":true,"reduceOnly":true,"orderType":"\#(stop ? "Stop Market" : "Take Profit Market")","timestamp":1}"#
        return try JSONDecoder().decode(HLFrontendOrder.self, from: Data(json.utf8))
    }

    private func stamper(at ms: UInt64) -> HLStamper {
        HLStamper(nonces: HLNonceSource(clock: { Date(timeIntervalSince1970: TimeInterval(ms) / 1000) }), isMainnet: true)
    }

    // MARK: - Stamping (B2)

    func testBudgetsPerSigningMode() {
        XCTAssertEqual(HLSigningMode.fastVault.expiryBudgetMs, 60_000)
        XCTAssertEqual(HLSigningMode.paired.expiryBudgetMs, 180_000)
    }

    func testNonceAndExpiryAreStampedAtSignTimeNotReviewTime() throws {
        let plan = try PerpsOrderPlanner.plan(market: market(), ticket: ticket(), nonce: 0, builder: PerpsConfig.builderFee(tier: nil))
        XCTAssertEqual(plan.requests.map(\.nonce), [0, 1], "the review holds a placeholder nonce")
        let signAt = Self.nonce + 95_000
        let request = try stamper(at: signAt).stamp(plan.unsignedSteps[0], mode: .paired)
        XCTAssertEqual(request.nonce, signAt)
        XCTAssertEqual(request.expiresAfter, signAt + 180_000)
        XCTAssertEqual(request.kind, .updateLeverage)
        let fast = try stamper(at: signAt).stamp(plan.unsignedSteps[0], mode: .fastVault)
        XCTAssertEqual(fast.expiresAfter, signAt + 60_000)
    }

    func testWithdrawStampBindsTimeToTheNonceWithoutExpiry() throws {
        let account = PerpsAccountSnapshot(address: "0x1", accountValue: 100, withdrawable: 100, marginUsed: 0, totalNotional: 0,
                                           positions: [], openOrders: [], fills: [])
        let vault = PerpsVaultContext(name: "Main", address: "0x9d7c000000000000000000000000000000003003", arbitrumUsdcBalance: nil)
        let document = try PerpsFlows.withdraw(amount: 10, account: account, vault: vault, nonce: 0)
        let step = try XCTUnwrap(document.steps.first)
        XCTAssertTrue(step.isUserSigned)
        let request = try stamper(at: Self.nonce).stamp(step, mode: .paired)
        XCTAssertEqual(request.action["time"], .uint(Self.nonce))
        XCTAssertNil(request.expiresAfter)
        XCTAssertNoThrow(try HLStamper.checkPostable(request, nowMs: Self.nonce + 10 * 86_400_000))
    }

    func testExpiredSignatureIsNeverPosted() throws {
        let step = HLUnsignedStep.l1(.noop, action: HLActions.noop)
        let request = try stamper(at: Self.nonce).stamp(step, mode: .fastVault)
        let expires = try XCTUnwrap(request.expiresAfter)
        XCTAssertNoThrow(try HLStamper.checkPostable(request, nowMs: expires - 3_001))
        XCTAssertThrowsError(try HLStamper.checkPostable(request, nowMs: expires - 3_000)) {
            XCTAssertEqual($0 as? HLStampError, .signatureExpired)
        }
    }

    func testStepsAreStampedOneAtATime() throws {
        let plan = try PerpsOrderPlanner.plan(market: market(), ticket: ticket(), nonce: 0)
        var sequence = HLStepSequence(steps: plan.unsignedSteps)
        let stamper = stamper(at: Self.nonce)
        let first = try sequence.stampNext(with: stamper, mode: .paired)
        XCTAssertEqual(first.kind, .updateLeverage)
        XCTAssertThrowsError(try sequence.stampNext(with: stamper, mode: .paired)) {
            XCTAssertEqual($0 as? HLStampError, .previousStepPending, "step 2 is never pre-stamped while step 1 runs")
        }
        sequence.markPosted()
        let second = try sequence.stampNext(with: stamper, mode: .paired)
        XCTAssertEqual(second.kind, .order)
        XCTAssertGreaterThan(second.nonce, first.nonce)
        sequence.markPosted()
        XCTAssertTrue(sequence.isFinished)
        XCTAssertThrowsError(try sequence.stampNext(with: stamper, mode: .paired))
    }

    func testMarketOrderIsRequotedAtStampTime() throws {
        let plan = try PerpsOrderPlanner.plan(market: market(mid: 100_000), ticket: ticket(), nonce: 0)
        let order = try XCTUnwrap(plan.unsignedSteps.last)
        let stamper = stamper(at: Self.nonce)
        let requoted = try stamper.stamp(order, mode: .fastVault, freshMid: 100_500)
        guard case .array(let orders)? = requoted.action["orders"] else { return XCTFail("orders") }
        // mid 100,500 + 1% slippage; an integer price keeps every digit.
        XCTAssertEqual(orders[0]["p"], .string("101505"))
        guard case .array(let reviewed)? = plan.steps.last?.action["orders"] else { return XCTFail("reviewed orders") }
        XCTAssertEqual(orders[0]["s"], reviewed[0]["s"], "the reviewed size is kept")
        XCTAssertThrowsError(try stamper.stamp(order, mode: .fastVault, freshMid: 101_500)) {
            XCTAssertEqual($0 as? HLStampError, .priceMoved)
        }
        XCTAssertEqual(try stamper.stamp(order, mode: .fastVault).action, plan.steps.last?.action, "no fresh mark: the reviewed price")
    }

    func testUnchangedLeverageSkipsTheLeverageCeremony() throws {
        let same = HLLeverage(type: "isolated", value: 2)
        let plan = try PerpsOrderPlanner.plan(market: market(), ticket: ticket(), nonce: 7, currentLeverage: same)
        XCTAssertEqual(plan.steps.map(\.kind), [.order])
        XCTAssertEqual(plan.steps.map(\.nonce), [7])
        let changed = try PerpsOrderPlanner.plan(market: market(), ticket: ticket(leverage: 3), nonce: 7, currentLeverage: same)
        XCTAssertEqual(changed.steps.map(\.kind), [.updateLeverage, .order])
        let cross = try PerpsOrderPlanner.plan(market: market(), ticket: ticket(), nonce: 7, currentLeverage: HLLeverage(type: "cross", value: 2))
        XCTAssertEqual(cross.steps.map(\.kind), [.updateLeverage, .order])
    }

    func testVenueClockOffset() throws {
        let device = Date(timeIntervalSince1970: 1_800_000_000)
        let clock = HLVenueClock(device: { device })
        clock.record(serverDate: device.addingTimeInterval(30))
        XCTAssertEqual(clock.now(), device.addingTimeInterval(30))
        clock.record(serverDate: device.addingTimeInterval(1))
        XCTAssertEqual(clock.now(), device, "sub-2 s differences are header resolution, not skew")
        let parsed = try XCTUnwrap(HLVenueClock.parse("Fri, 13 Nov 2026 10:00:00 GMT"))
        XCTAssertEqual(parsed.timeIntervalSince1970, 1_794_564_000)
    }

    // MARK: - SDK parity (batchModify, noop)

    /// hyperliquid-python-sdk vectors (scratch/perps/vectors/gen_modify_sdk.py),
    /// nonce 1731400000000, expiresAfter nonce + 180 s, mainnet.
    func testBatchModifyAndNoopMatchTheSDK() throws {
        let stop = HLOrderWire(asset: 0, isBuy: false, price: "62000", size: "0.002", reduceOnly: true,
                               type: .trigger(isMarket: true, triggerPrice: "62000", kind: .stopLoss))
        let take = HLOrderWire(asset: 0, isBuy: false, price: "72000", size: "0.002", reduceOnly: true,
                               type: .trigger(isMarket: true, triggerPrice: "72000", kind: .takeProfit))
        let cases: [(HLValue, String, String)] = [
            (HLActions.batchModify([(77, stop)]), "2176c63056e7e95bca4b0c495adf25ceaa979570db37d1fde070897be2ecc297",
             "acb1e042f9a9c54ba9fcec7ab12bd8b1dcb13f7d02f5bdca8ac4599cdcf7475e"),
            (HLActions.batchModify([(77, stop), (78, take)]), "a97ef20425e83be1e6f38e0e2f3e7121ed4a8d7e36cfd747edd60ceff113b0c3",
             "9773971f14d17488433f6568e55dc2e2cca43103f2844d5deb945950a2486200"),
            (HLActions.noop, "6ab459062a53f09d52c5f93b0bd68afa74c641d1c5c8c7a53eefa543a2cdd6be",
             "bd7761f4f7ecf7a405136b11f9675756915923c0cdff5080ebc8ae0bc0695b72")
        ]
        for (action, connectionId, digest) in cases {
            let expires = Self.nonce + 180_000
            XCTAssertEqual(try HLActionHasher.connectionId(action: action, nonce: Self.nonce, vaultAddress: nil, expiresAfter: expires).hexString,
                           connectionId)
            XCTAssertEqual(try HLExchangeRequest.l1(.batchModify, action: action, nonce: Self.nonce, isMainnet: true,
                                                    expiresAfter: expires).digest.hexString, digest)
        }
    }

    // MARK: - Stop loss / take profit edits (M8)

    func testBothTriggersMovedIsOneSignature() throws {
        let document = try PerpsFlows.editExits(position: try position(), market: market(),
                                                existing: [try trigger(oid: 77, price: "60000", stop: true), try trigger(oid: 78, price: "70000", stop: false)],
                                                stopLoss: 62_000, takeProfit: 72_000, nonce: 0)
        XCTAssertEqual(document.steps.map(\.kind), [.batchModify])
        guard case .array(let modifies)? = document.requests[0].action["modifies"] else { return XCTFail("modifies") }
        XCTAssertEqual(modifies.compactMap { $0["oid"] }, [.int(77), .int(78)])
        XCTAssertNil(document.cancelGate)
    }

    func testOnlyARemovedTriggerIsCancelledAndAlwaysLast() throws {
        let stop = try trigger(oid: 77, price: "60000", stop: true)
        let take = try trigger(oid: 78, price: "70000", stop: false)
        let removeStop = try PerpsFlows.editExits(position: try position(), market: market(), existing: [stop, take],
                                                  stopLoss: nil, takeProfit: 70_000, nonce: 0)
        XCTAssertEqual(removeStop.steps.map(\.kind), [.cancel])
        let mixed = try PerpsFlows.editExits(position: try position(), market: market(), existing: [stop, take],
                                             stopLoss: nil, takeProfit: 71_000, nonce: 0)
        XCTAssertEqual(mixed.steps.map(\.kind), [.batchModify, .cancel])
        let add = try PerpsFlows.editExits(position: try position(), market: market(), existing: [],
                                           stopLoss: 62_000, takeProfit: nil, nonce: 0)
        XCTAssertEqual(add.steps.map(\.kind), [.order])
    }

    func testPlaceThenCancelFallbackNeverCancelsFirst() throws {
        let stop = try trigger(oid: 77, price: "60000", stop: true)
        let document = try PerpsFlows.editExits(position: try position(), market: market(), existing: [stop],
                                                stopLoss: 62_000, takeProfit: nil, nonce: 0, strategy: .placeThenCancel)
        XCTAssertEqual(document.steps.map(\.kind), [.order, .cancel])
        let gate = try XCTUnwrap(document.cancelGate)
        XCTAssertEqual(gate.replacedOids, [77])
        XCTAssertEqual(gate.decide(placed: nil, openOrders: [stop]), .keepOld)
        XCTAssertEqual(gate.decide(placed: [900], openOrders: [stop]), .waitForNewTrigger)
        XCTAssertEqual(gate.decide(placed: [900], openOrders: [stop, try trigger(oid: 900, price: "62000", stop: true)]), .cancelOld)
        XCTAssertEqual(gate.outcome(cancelSucceeded: false), .bothActive)
        XCTAssertEqual(gate.outcome(cancelSucceeded: true), .replaced)

        // The sequence itself refuses to stamp the cancel before the gate opens.
        var sequence = HLStepSequence(document: document)
        let stamper = stamper(at: Self.nonce)
        XCTAssertEqual(try sequence.stampNext(with: stamper, mode: .paired).kind, .order)
        sequence.markPosted()
        XCTAssertThrowsError(try sequence.stampNext(with: stamper, mode: .paired)) {
            XCTAssertEqual($0 as? HLStampError, .replacementNotConfirmed)
        }
        XCTAssertEqual(sequence.confirmReplacement(placed: [900], openOrders: [stop]), .waitForNewTrigger)
        XCTAssertThrowsError(try sequence.stampNext(with: stamper, mode: .paired))
        sequence.confirmReplacement(placed: [900], openOrders: [stop, try trigger(oid: 900, price: "62000", stop: true)])
        XCTAssertEqual(try sequence.stampNext(with: stamper, mode: .paired).kind, .cancel)
    }

    /// Both stops left live by a failed cancel: an edit retargets one and
    /// cancels the stale one last, so it cannot fire at the old price.
    func testDuplicateStopIsCancelledAfterTheEdit() throws {
        let document = try PerpsFlows.editExits(position: try position(), market: market(),
                                                existing: [try trigger(oid: 77, price: "60000", stop: true),
                                                           try trigger(oid: 79, price: "61000", stop: true)],
                                                stopLoss: 62_000, takeProfit: nil, nonce: 0)
        XCTAssertEqual(document.steps.map(\.kind), [.batchModify, .cancel])
        guard case .array(let cancels)? = document.requests[1].action["cancels"] else { return XCTFail("cancels") }
        XCTAssertEqual(cancels.compactMap { $0["o"] }, [.int(79)])
    }

    func testOrderStatusesParse() throws {
        let resting = #"{"status":"ok","response":{"type":"order","data":{"statuses":[{"resting":{"oid":77738308}}]}}}"#
        XCTAssertEqual(try JSONDecoder().decode(HLOrderStatuses.self, from: Data(resting.utf8)).restingOids, [77738308])
        let failed = #"{"status":"ok","response":{"type":"order","data":{"statuses":[{"error":"Order has invalid price."}]}}}"#
        XCTAssertNil(try JSONDecoder().decode(HLOrderStatuses.self, from: Data(failed.utf8)).restingOids)
        let err = #"{"status":"err","response":"User or API Wallet does not exist."}"#
        XCTAssertNil(try JSONDecoder().decode(HLOrderStatuses.self, from: Data(err.utf8)).restingOids)
    }

    // MARK: - withdraw3 idempotency

    private final class MemoryStore: HLPendingSubmissionStoring, @unchecked Sendable {
        private let lock = NSLock()
        private var records: [String: [HLPendingSubmission]] = [:]
        func load(signer: String) throws -> [HLPendingSubmission] { lock.withLock { records[signer.lowercased()] ?? [] } }
        func save(_ records: [HLPendingSubmission], signer: String) throws { lock.withLock { self.records[signer.lowercased()] = records } }
    }

    private final class FakePoster: HLExchangePosting, @unchecked Sendable {
        private let lock = NSLock()
        private var outcomes: [HLPostOutcome]
        private(set) var bodies: [String] = []
        init(_ outcomes: [HLPostOutcome]) { self.outcomes = outcomes }
        // swiftlint:disable:next async_without_await
        func post(body: String) async -> HLPostOutcome {
            lock.withLock {
                bodies.append(body)
                return outcomes.isEmpty ? .transportFailure : outcomes.removeFirst()
            }
        }
    }

    private struct FakeLedger: HLLedgerReading {
        var updates: [HLLedgerUpdate] = []
        // swiftlint:disable:next async_without_await
        func ledgerUpdates(user _: String, startTimeMs _: Int64) async throws -> [HLLedgerUpdate] { updates }
    }

    private final class Clock: @unchecked Sendable {
        var ms: UInt64 = HyperliquidLiveSigningTests.nonce
    }

    private func signedWithdraw(nonce: UInt64 = HyperliquidLiveSigningTests.nonce) throws -> (HLExchangeRequest, String) {
        let key = try XCTUnwrap(PrivateKey(data: try XCTUnwrap(Data(hexString: Self.sdkTestKey))))
        let signer = PerpsSignerGuard.address(of: key.getPublicKeySecp256k1(compressed: true))
        let request = HLExchangeRequest.userSigned(.withdraw3, try HLUserSignedAction.withdraw3(
            destination: "0x9d7c000000000000000000000000000000003003", amount: 49.5, nonce: nonce, isMainnet: true))
        let raw = try XCTUnwrap(key.sign(digest: request.digest, curve: .secp256k1))
        return (try request.signed(try XCTUnwrap(HLSignature(recoverable: raw)), expected: signer), signer)
    }

    private func ledgerWithdraw(nonce: UInt64?, usdc: String = "49.5") throws -> HLLedgerUpdate {
        let nonceField = nonce.map { #","nonce":\#($0)"# } ?? ""
        let json = #"{"time":\#(Self.nonce + 2_000),"hash":"0xabc","delta":{"type":"withdraw","usdc":"\#(usdc)"\#(nonceField),"fee":"1.0"}}"#
        return try JSONDecoder().decode(HLLedgerUpdate.self, from: Data(json.utf8))
    }

    private func submitter(_ poster: FakePoster, ledger: FakeLedger = FakeLedger(), store: MemoryStore = MemoryStore(),
                           clock: Clock = Clock()) -> HLWithdrawSubmitter {
        HLWithdrawSubmitter(store: store, poster: poster, ledger: ledger, nowMs: { clock.ms })
    }

    func testOnlyAGuardedSignatureIsRecorded() async throws {
        let unsigned = HLExchangeRequest.userSigned(.withdraw3, try HLUserSignedAction.withdraw3(
            destination: "0x9d7c000000000000000000000000000000003003", amount: 49.5, nonce: Self.nonce, isMainnet: true))
        let submitter = submitter(FakePoster([]))
        do {
            _ = try await submitter.record(unsigned, signer: "0x00", amount: "49.5")
            XCTFail("an unsigned body was recorded")
        } catch {
            XCTAssertEqual(error as? HLWithdrawSubmitterError, .notSigned)
        }
    }

    func testOkIsDone() async throws {
        let (request, signer) = try signedWithdraw()
        let submitter = submitter(FakePoster([.ok]))
        let record = try await submitter.record(request, signer: signer, amount: "49.5")
        let state = try await submitter.post(id: record.id, signer: signer)
        XCTAssertEqual(state, .done)
        let open = try await submitter.openRecord(signer: signer)
        XCTAssertNil(open)
    }

    /// A timeout leaves the record uncertain: no new withdrawal can be signed,
    /// and "try again" resends the same bytes. It never re-signs.
    func testUncertainResendsTheExactSameBody() async throws {
        let (request, signer) = try signedWithdraw()
        let poster = FakePoster([.transportFailure, .ok])
        let submitter = submitter(poster)
        let record = try await submitter.record(request, signer: signer, amount: "49.5")
        let first = try await submitter.post(id: record.id, signer: signer)
        XCTAssertEqual(first, .uncertain)
        let (another, _) = try signedWithdraw(nonce: Self.nonce + 5)
        do {
            _ = try await submitter.record(another, signer: signer, amount: "49.5")
            XCTFail("a second withdrawal was signed while one is uncertain")
        } catch {
            XCTAssertEqual(error as? HLWithdrawSubmitterError, .withdrawalPending)
        }
        let second = try await submitter.post(id: record.id, signer: signer)
        XCTAssertEqual(second, .done)
        XCTAssertEqual(poster.bodies.count, 2)
        XCTAssertEqual(poster.bodies[0], poster.bodies[1])
        XCTAssertEqual(poster.bodies[0], request.jsonBody)
    }

    func testDuplicateNonceReconcilesAgainstTheLedger() async throws {
        let (request, signer) = try signedWithdraw()
        let found = submitter(FakePoster([.nonceAlreadyUsed]), ledger: FakeLedger(updates: [try ledgerWithdraw(nonce: Self.nonce)]))
        let record = try await found.record(request, signer: signer, amount: "49.5")
        let state = try await found.post(id: record.id, signer: signer)
        XCTAssertEqual(state, .done)

        let clock = Clock()
        let missing = submitter(FakePoster([.nonceAlreadyUsed]), clock: clock)
        let pending = try await missing.record(request, signer: signer, amount: "49.5")
        let stillUncertain = try await missing.post(id: pending.id, signer: signer)
        XCTAssertEqual(stillUncertain, .uncertain, "not in the ledger yet: never assumed failed")
        clock.ms = Self.nonce + HLWithdrawSubmitter.nonceWindowMs + 1
        let expired = try await missing.reconcile(id: pending.id, signer: signer)
        XCTAssertEqual(expired, .rejected, "out of the venue's nonce window: it can never land")
        let (next, _) = try signedWithdraw(nonce: clock.ms)
        let fresh = try await missing.record(next, signer: signer, amount: "49.5")
        XCTAssertEqual(fresh.state, .signed)
    }

    func testDefinitiveRejectionAllowsANewSignature() async throws {
        let (request, signer) = try signedWithdraw()
        let submitter = submitter(FakePoster([.rejected("Insufficient balance for withdrawal")]))
        let record = try await submitter.record(request, signer: signer, amount: "49.5")
        let state = try await submitter.post(id: record.id, signer: signer)
        XCTAssertEqual(state, .rejected)
        let open = try await submitter.openRecord(signer: signer)
        XCTAssertNil(open)
        do {
            _ = try await submitter.post(id: record.id, signer: signer)
            XCTFail("a rejected body was posted again")
        } catch {
            XCTAssertEqual(error as? HLWithdrawSubmitterError, .notPostable(.rejected))
        }
    }

    func testAppKilledWhilePostingIsUncertainAtLaunch() async throws {
        let (request, signer) = try signedWithdraw()
        let store = MemoryStore()
        let submitter = submitter(FakePoster([]), store: store)
        var record = try await submitter.record(request, signer: signer, amount: "49.5")
        record.state = .posting
        try store.save([record], signer: signer)
        try await submitter.recoverAfterLaunch(signer: signer)
        let open = try await submitter.openRecord(signer: signer)
        XCTAssertEqual(open?.state, .uncertain)
    }

    /// Only the nonce settles a record: a same-amount withdrawal nearby is not proof.
    func testLedgerMatchesByNonceOnly() throws {
        let record = HLPendingSubmission(id: UUID(), kind: "withdraw3", nonce: Self.nonce, digest: "", body: "", signer: "0x1",
                                         amount: "49.5", createdAt: Date(), state: .uncertain)
        XCTAssertTrue(HLWithdrawSubmitter.matches(try ledgerWithdraw(nonce: Self.nonce), record))
        XCTAssertFalse(HLWithdrawSubmitter.matches(try ledgerWithdraw(nonce: nil), record))
        XCTAssertFalse(HLWithdrawSubmitter.matches(try ledgerWithdraw(nonce: Self.nonce + 1), record))
    }

    func testNoSecondCeremonyStartsWhileOneIsOpen() async throws {
        let (request, signer) = try signedWithdraw()
        let store = MemoryStore()
        let first = submitter(FakePoster([.transportFailure]), store: store)
        let second = submitter(FakePoster([]), store: store)
        try await first.ensureCanSign(signer: signer)
        let record = try await first.record(request, signer: signer, amount: "49.5")
        _ = try await first.post(id: record.id, signer: signer)
        do {
            try await second.ensureCanSign(signer: signer)
            XCTFail("a second ceremony could start")
        } catch {
            XCTAssertEqual(error as? HLWithdrawSubmitterError, .withdrawalPending)
        }
        let (other, _) = try signedWithdraw(nonce: Self.nonce + 9)
        do {
            _ = try await second.record(other, signer: signer, amount: "49.5")
            XCTFail("another submitter on the same store recorded a second withdrawal")
        } catch {
            XCTAssertEqual(error as? HLWithdrawSubmitterError, .withdrawalPending)
        }
    }

    func testPostOutcomeClassification() {
        XCTAssertEqual(HLPostOutcome.classify(statusCode: 200, body: Data(#"{"status":"ok","response":{"type":"default"}}"#.utf8)), .ok)
        XCTAssertEqual(HLPostOutcome.classify(statusCode: 200, body: Data(#"{"status":"err","response":"Invalid nonce"}"#.utf8)), .nonceAlreadyUsed)
        XCTAssertEqual(HLPostOutcome.classify(statusCode: 200, body: Data(#"{"status":"err","response":"Insufficient"}"#.utf8)),
                       .rejected("Insufficient"))
        XCTAssertEqual(HLPostOutcome.classify(statusCode: 502, body: nil), .transportFailure)
        XCTAssertEqual(HLPostOutcome.classify(statusCode: nil, body: nil), .transportFailure)
    }

    func testFileStoreRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = HLFilePendingSubmissionStore(directory: directory)
        XCTAssertEqual(try store.load(signer: "0xAB"), [])
        let record = HLPendingSubmission(id: UUID(), kind: "withdraw3", nonce: Self.nonce, digest: "0x01", body: "{}", signer: "0xab",
                                         amount: "1", createdAt: Date(timeIntervalSince1970: 1_800_000_000), state: .uncertain)
        try store.save([record], signer: "0xAB")
        XCTAssertEqual(try store.load(signer: "0xab"), [record])
    }
}
