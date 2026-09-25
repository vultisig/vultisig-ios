//
//  NativeSwapPollerTests.swift
//  VultisigAppTests
//
//  The done screen's view of a native THORChain/Maya market swap: which
//  poller drives it on each device, and what each tracker status looks like.
//  The deposit confirming is not success — only the payout is — and a refund
//  must read as a failure, never as "Transaction successful".
//

import XCTest
@testable import VultisigApp

@MainActor
final class NativeSwapPollerTests: XCTestCase {

    private typealias Fixture = NativeSwapFixtures

    private let estimatedTime = "~15-30 sec"
    private let txHash = "0xabc"

    // MARK: - Status mapping

    func testNoTrackerStatusYetIsBroadcasted() {
        XCTAssertEqual(
            NativeSwapPoller.mapNativeSwapStatus(nil, failureReason: nil, estimatedTime: estimatedTime),
            .broadcasted(estimatedTime: estimatedTime)
        )
    }

    func testEverythingInFlightIsPending() {
        for ui in [SwapTrackingUiStatus.pending, .swapping, .unknownPendingExtended] {
            XCTAssertEqual(
                NativeSwapPoller.mapNativeSwapStatus(ui, failureReason: nil, estimatedTime: estimatedTime),
                .pending,
                "\(ui)"
            )
        }
    }

    func testOnlyThePayoutIsConfirmed() {
        XCTAssertEqual(
            NativeSwapPoller.mapNativeSwapStatus(.completed, failureReason: nil, estimatedTime: estimatedTime),
            .confirmed
        )
    }

    func testRefundIsAFailureSayingTheFundsCameBack() {
        XCTAssertEqual(
            NativeSwapPoller.mapNativeSwapStatus(.refunded, failureReason: "ignored", estimatedTime: estimatedTime),
            .failed(reason: "swapKitStatusRefundedReason".localized)
        )
    }

    func testFailureCarriesTheChainsReasonOrAGenericOne() {
        XCTAssertEqual(
            NativeSwapPoller.mapNativeSwapStatus(.failed, failureReason: "execution reverted", estimatedTime: estimatedTime),
            .failed(reason: "execution reverted")
        )
        for reason in [nil, "  "] {
            XCTAssertEqual(
                NativeSwapPoller.mapNativeSwapStatus(.failed, failureReason: reason, estimatedTime: estimatedTime),
                .failed(reason: "transactionFailedDescription".localized)
            )
        }
    }

    func testLimitOrderStatesNeverClaimAnOutcome() {
        for ui in [SwapTrackingUiStatus.resting, .expired, .cancelled, .cancelling] {
            XCTAssertEqual(
                NativeSwapPoller.mapNativeSwapStatus(ui, failureReason: nil, estimatedTime: estimatedTime),
                .pending,
                "\(ui)"
            )
        }
    }

    // MARK: - Initiator dispatch

    func testInitiatorNativeMarketSwapIsDrivenByTheNativeSwapPoller() {
        for quote in [
            SwapQuote.thorchain(Fixture.makeQuote(memo: Fixture.swapMemo)),
            .thorchainChainnet(Fixture.makeQuote(memo: Fixture.swapMemo)),
            .thorchainStagenet(Fixture.makeQuote(memo: Fixture.swapMemo)),
            .mayachain(Fixture.makeQuote(memo: Fixture.swapMemo))
        ] {
            let service = DoneStatusServiceFactory.swap(
                txHash: txHash,
                transaction: Fixture.makeTransaction(kind: .market(quote)),
                vault: .example
            )
            XCTAssertTrue(service.pollerForTesting is NativeSwapPoller)
            XCTAssertEqual(service.status, .broadcasted(estimatedTime: ChainStatusConfig.config(for: .ethereum).estimatedTime))
        }
    }

    func testInitiatorLimitOrderKeepsTheLimitPoller() {
        let service = DoneStatusServiceFactory.swap(
            txHash: txHash,
            transaction: Fixture.makeLimitTransaction(),
            vault: .example
        )
        XCTAssertTrue(service.pollerForTesting is LimitOrderPoller)
    }

    func testInitiatorAggregatorAndSecuredMintKeepTheChainPoller() {
        var securedMint = Fixture.makeTransaction(kind: .market(
            SwapCryptoLogic.securedMintQuote(fromAmount: 1, toCoin: Fixture.makeCoin(.thorChain, ticker: "BTC"))
        ))
        securedMint.mode = .securedMint
        for transaction in [Fixture.makeTransaction(kind: .market(.oneinch(Fixture.makeEVMQuote(), fee: nil))), securedMint] {
            let service = DoneStatusServiceFactory.swap(txHash: txHash, transaction: transaction, vault: .example)
            XCTAssertTrue(service.pollerForTesting is ChainPoller)
        }
    }

    // MARK: - Co-signer dispatch

    func testCosignerNativeMarketSwapIsDrivenByTheNativeSwapPoller() {
        for payload in [
            SwapPayload.thorchain(Fixture.makeThorchainPayload()),
            .thorchainChainnet(Fixture.makeThorchainPayload()),
            .thorchainStagenet(Fixture.makeThorchainPayload()),
            .mayachain(Fixture.makeThorchainPayload())
        ] {
            let service = DoneStatusServiceFactory.cosigner(
                keysignPayload: Fixture.makeKeysignPayload(memo: Fixture.swapMemo, swapPayload: payload),
                txHash: txHash,
                vault: .example
            )
            XCTAssertTrue(service.pollerForTesting is NativeSwapPoller)
        }
    }

    func testCosignerLimitOrderKeepsTheLimitPoller() {
        let service = DoneStatusServiceFactory.cosigner(
            keysignPayload: Fixture.makeKeysignPayload(
                memo: "=<:BTC.BTC:bc1qexample:1e6:va:50",
                swapPayload: .thorchain(Fixture.makeThorchainPayload())
            ),
            txHash: txHash,
            vault: .example
        )
        XCTAssertTrue(service.pollerForTesting is LimitOrderPoller)
    }

    func testCosignerRouterDepositsAndSendsKeepTheChainPoller() {
        let payloads = [
            Fixture.makeKeysignPayload(memo: "SECURE+:thor1vault", swapPayload: .thorchain(Fixture.makeThorchainPayload())),
            Fixture.makeKeysignPayload(memo: "+:ETH.USDC-0XA0B8:thor1lp", swapPayload: .thorchain(Fixture.makeThorchainPayload())),
            Fixture.makeKeysignPayload(memo: nil, swapPayload: nil)
        ]
        for keysignPayload in payloads {
            let service = DoneStatusServiceFactory.cosigner(keysignPayload: keysignPayload, txHash: txHash, vault: .example)
            XCTAssertTrue(service.pollerForTesting is ChainPoller, keysignPayload.memo ?? "nil")
        }
    }
}
