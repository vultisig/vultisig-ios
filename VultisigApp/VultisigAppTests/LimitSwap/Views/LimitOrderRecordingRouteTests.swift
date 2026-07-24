//
//  LimitOrderRecordingRouteTests.swift
//  VultisigAppTests
//
//  Pins which cosigner payloads reach `recordFromKeysignPayload`.
//
//  Regression: the dispatch used to require `swapPayload != nil`. A
//  NATIVE-source limit order (RUNE/BTC/…) is a plain deposit whose `=<` memo is
//  the entire order and carries no swap payload, so it fell through to
//  `recordSend` — producing a send row with no tracking metadata. That row was
//  missing from the Limit Orders tab AND left to the native poller, which
//  reports the order Successful the moment the inbound deposit confirms. Both
//  halves of the bug this feature exists to kill, on the co-signing device.
//

import BigInt
import XCTest
@testable import VultisigApp

final class LimitOrderRecordingRouteTests: XCTestCase {

    private let limitMemo = "=<:BTC.BTC:bc1qexample:1e6:va:50"

    // MARK: - The regression

    func testNativeSourceLimitOrderRoutesToTheKeysignRecorderDespiteNoSwapPayload() {
        let payload = makePayload(memo: limitMemo, swapPayload: nil)

        XCTAssertTrue(
            TransactionHistoryRecording.routesThroughKeysignRecorder(payload),
            "A native-source limit order carries no swap payload — the memo is the only evidence it's an order"
        )
    }

    // MARK: - Everything else keeps its route

    func testPlainSendDoesNotRouteToTheKeysignRecorder() {
        let payload = makePayload(memo: nil, swapPayload: nil)
        XCTAssertFalse(TransactionHistoryRecording.routesThroughKeysignRecorder(payload))
    }

    func testSendWithANonLimitMemoDoesNotRouteToTheKeysignRecorder() {
        // A memo alone must not reroute an ordinary send.
        for memo in ["SWAP:BTC.BTC:bc1qexample", "=:BTC.BTC:bc1qexample", "+:BTC.BTC", "hello"] {
            let payload = makePayload(memo: memo, swapPayload: nil)
            XCTAssertFalse(
                TransactionHistoryRecording.routesThroughKeysignRecorder(payload),
                "\(memo) is not a limit-order memo"
            )
        }
    }

    func testSwapStillRoutesToTheKeysignRecorder() {
        let payload = makePayload(memo: nil, swapPayload: .thorchain(makeThorchainPayload()))
        XCTAssertTrue(TransactionHistoryRecording.routesThroughKeysignRecorder(payload))
    }

    /// An ERC20-source limit order rides a swap payload (for the router's
    /// `depositWithExpiry`), so it already routed correctly — and must continue
    /// to.
    func testErc20SourceLimitOrderStillRoutesToTheKeysignRecorder() {
        let payload = makePayload(memo: limitMemo, swapPayload: .thorchain(makeThorchainPayload()))
        XCTAssertTrue(TransactionHistoryRecording.routesThroughKeysignRecorder(payload))
    }

    // MARK: - A cancel gets no row of its own

    /// ⚠️ A cancel is a step in an order's life, not a transfer. Recorded, it
    /// becomes a standalone "Send 0 RUNE" — or a send of dust on the L1 route —
    /// with nothing connecting it to the order it closes, while the order's own
    /// row already narrates the whole lifecycle.
    func testACancelIsNotRecordedAsItsOwnRow() {
        XCTAssertTrue(TransactionHistoryRecording.isLimitOrderCancel(makeDonePayload(memo: cancelMemo)))
    }

    /// A CO-SIGNER has only the payload, so the memo has to be read from there
    /// too — the done screen's own `memo` can be empty before it resolves.
    func testACosignersCancelIsRecognisedFromTheKeysignPayload() {
        let payload = makeDonePayload(
            memo: "",
            keysignPayload: makePayload(memo: cancelMemo, swapPayload: nil)
        )

        XCTAssertTrue(TransactionHistoryRecording.isLimitOrderCancel(payload))
    }

    /// ⚠️ The two prefixes are disjoint and mean opposite things. A PLACEMENT
    /// (`=<:`) must keep its row — that row IS the order.
    func testAPlacementIsStillRecorded() {
        XCTAssertFalse(TransactionHistoryRecording.isLimitOrderCancel(makeDonePayload(memo: limitMemo)))
        XCTAssertFalse(
            TransactionHistoryRecording.isLimitOrderCancel(
                makeDonePayload(memo: "", keysignPayload: makePayload(memo: limitMemo, swapPayload: nil))
            )
        )
    }

    /// ⚠️ `m=<` also covers RE-TARGETING a resting order, which moves the order
    /// rather than closing it and has every reason to appear in history. Only a
    /// modified target of zero is a cancel — THORNode branches on exactly that.
    ///
    /// This app builds only the cancel form today, so the loose and the exact
    /// predicate coincide. That is precisely why keying behaviour on the loose
    /// one is not good enough: the day modify exists, a retarget would vanish
    /// from history somewhere nobody thought to look.
    func testARetargetIsNotACancelAndKeepsItsRow() {
        let retarget = "m=<:100000000THOR.RUNE:15979057441BTC.BTC:16000000000"

        XCTAssertFalse(TransactionHistoryRecording.isLimitOrderCancel(makeDonePayload(memo: retarget)))
        XCTAssertFalse(isCancelLimitSwapMemo(retarget))
        XCTAssertTrue(isModifyLimitSwapMemo(retarget), "it IS a modification — just not a cancel")
        XCTAssertTrue(isCancelLimitSwapMemo(cancelMemo))
    }

    func testOrdinarySendsAreStillRecorded() {
        for memo in ["", "SWAP:BTC.BTC:bc1qexample", "=:BTC.BTC:bc1qexample", "+:BTC.BTC", "hello"] {
            XCTAssertFalse(
                TransactionHistoryRecording.isLimitOrderCancel(makeDonePayload(memo: memo)),
                "\(memo) is not a cancel"
            )
        }
    }

    // MARK: - Fixtures

    private let cancelMemo = "m=<:100000000THOR.RUNE:15979057441BTC.BTC:0"

    private func makeDonePayload(memo: String, keysignPayload: KeysignPayload? = nil) -> TransactionDonePayload {
        TransactionDonePayload(
            coin: .example,
            amountCrypto: "0 RUNE",
            amountFiat: "",
            hash: "CANCELTX",
            explorerLink: "",
            memo: memo,
            isSend: true,
            fromAddress: "thor1from",
            toAddress: "",
            fee: FeeDisplay(crypto: "", fiat: ""),
            keysignPayload: keysignPayload,
            pubKeyECDSA: "pub"
        )
    }

    private func makeThorchainPayload() -> THORChainSwapPayload {
        THORChainSwapPayload(
            fromAddress: "thor1from",
            fromCoin: .example,
            toCoin: .example,
            vaultAddress: "thor1vault",
            routerAddress: nil,
            fromAmount: BigInt(1000),
            toAmountDecimal: 1,
            toAmountLimit: "0",
            streamingInterval: "0",
            streamingQuantity: "0",
            expirationTime: 0,
            isAffiliate: false
        )
    }

    private func makePayload(memo: String?, swapPayload: SwapPayload?) -> KeysignPayload {
        KeysignPayload(
            coin: .example,
            toAddress: "thor1to",
            toAmount: BigInt(1000),
            chainSpecific: .THORChain(
                accountNumber: 1,
                sequence: 1,
                fee: 0,
                isDeposit: true,
                transactionType: 0
            ),
            utxos: [],
            memo: memo,
            swapPayload: swapPayload,
            approvePayload: nil,
            vaultPubKeyECDSA: "pub",
            vaultLocalPartyID: "party",
            libType: LibType.DKLS.toString(),
            wasmExecuteContractPayload: nil,
            tronTransferContractPayload: nil,
            tronTriggerSmartContractPayload: nil,
            tronTransferAssetContractPayload: nil,
            qbtcClaimPayload: nil,
            isQbtcClaim: false,
            skipBroadcast: false,
            signData: nil
        )
    }
}
