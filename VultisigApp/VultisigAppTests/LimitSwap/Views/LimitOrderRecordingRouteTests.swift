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

    // MARK: - Fixtures

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
