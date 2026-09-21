//
//  NativeSwapRecordingTests.swift
//  VultisigAppTests
//
//  Pins which swap rows are recorded with native-swap tracking metadata, on
//  both devices. A native market swap recorded untracked is confirmed by the
//  source-chain poller the moment its deposit lands, refund or not; a limit
//  order, a SECURE+ mint or an LP add recorded AS a native swap would wait
//  forever for a swap action Midgard never indexes.
//

import XCTest
@testable import VultisigApp

@MainActor
final class NativeSwapRecordingTests: XCTestCase {

    private typealias Fixture = NativeSwapFixtures

    private let txHash = "0xabc"
    private let swapMemo = Fixture.swapMemo

    // MARK: - Initiator

    func testInitiatorNativeMarketSwapIsTrackedOnItsProtocolNetwork() {
        let cases: [(SwapQuote, Chain)] = [
            (.thorchain(Fixture.makeQuote(memo: swapMemo)), .thorChain),
            (.thorchainChainnet(Fixture.makeQuote(memo: swapMemo)), .thorChainChainnet),
            (.thorchainStagenet(Fixture.makeQuote(memo: swapMemo)), .thorChainStagenet),
            (.mayachain(Fixture.makeQuote(memo: swapMemo)), .mayaChain)
        ]
        for (quote, network) in cases {
            let tracking = SwapDoneScreen.swapTracking(for: Fixture.makeTransaction(kind: .market(quote)), hash: txHash)
            XCTAssertEqual(tracking, NativeSwapTrackingService.metadata(broadcastHash: txHash, network: network))
        }
    }

    func testInitiatorLimitOrderKeepsLimitTracking() {
        let tracking = SwapDoneScreen.swapTracking(for: Fixture.makeLimitTransaction(), hash: txHash)
        XCTAssertEqual(tracking?.providerKind, THORChainLimitTrackingService.providerKind)
    }

    func testInitiatorAggregatorRoutesAreNotNativeTracked() {
        for quote in [SwapQuote.oneinch(Fixture.makeEVMQuote(), fee: nil), .lifi(Fixture.makeEVMQuote(), fee: nil, integratorFee: nil)] {
            XCTAssertNil(SwapDoneScreen.swapTracking(for: Fixture.makeTransaction(kind: .market(quote)), hash: txHash))
        }
        XCTAssertNil(SwapDoneScreen.swapTracking(for: Fixture.makeTransaction(kind: .market(nil)), hash: txHash))
    }

    /// A SECURE+ mint rides a synthetic THORChain quote, and Midgard indexes the
    /// deposit as a mint, never as a swap.
    func testInitiatorSecuredMintIsNotNativeTracked() {
        let quote = SwapCryptoLogic.securedMintQuote(fromAmount: 1, toCoin: Fixture.makeCoin(.thorChain, ticker: "BTC"))
        var transaction = Fixture.makeTransaction(kind: .market(quote))
        transaction.mode = .securedMint
        XCTAssertNil(SwapDoneScreen.swapTracking(for: transaction, hash: txHash))
    }

    // MARK: - Co-signer

    func testCosignerNativeMarketSwapIsTrackedOnItsProtocolNetwork() {
        let cases: [(SwapPayload, Chain)] = [
            (.thorchain(Fixture.makeThorchainPayload()), .thorChain),
            (.thorchainChainnet(Fixture.makeThorchainPayload()), .thorChainChainnet),
            (.thorchainStagenet(Fixture.makeThorchainPayload()), .thorChainStagenet),
            (.mayachain(Fixture.makeThorchainPayload()), .mayaChain)
        ]
        for (payload, network) in cases {
            let tracking = TransactionHistoryRecorder.swapTracking(
                for: Fixture.makeKeysignPayload(memo: swapMemo, swapPayload: payload),
                txHash: txHash
            )
            XCTAssertEqual(tracking, NativeSwapTrackingService.metadata(broadcastHash: txHash, network: network))
        }
    }

    func testCosignerErc20LimitOrderKeepsLimitTracking() {
        let tracking = TransactionHistoryRecorder.swapTracking(
            for: Fixture.makeKeysignPayload(memo: "=<:BTC.BTC:bc1qexample:1e6:va:50", swapPayload: .thorchain(Fixture.makeThorchainPayload())),
            txHash: txHash
        )
        XCTAssertEqual(tracking?.providerKind, THORChainLimitTrackingService.providerKind)
    }

    /// ERC20 SECURE+ mints and LP adds ride a THORChain payload for the router's
    /// `depositWithExpiry`; only the memo says they are not swaps.
    func testCosignerRouterDepositsThatAreNotSwapsAreNotNativeTracked() {
        for memo in ["SECURE+:thor1vault", "+:ETH.USDC-0XA0B8:thor1lp", "", nil] {
            let tracking = TransactionHistoryRecorder.swapTracking(
                for: Fixture.makeKeysignPayload(memo: memo, swapPayload: .thorchain(Fixture.makeThorchainPayload())),
                txHash: txHash
            )
            XCTAssertNil(tracking, "\(memo ?? "nil") is not a market swap")
        }
    }

    func testCosignerWithoutANativePayloadIsNotNativeTracked() {
        XCTAssertNil(TransactionHistoryRecorder.swapTracking(
            for: Fixture.makeKeysignPayload(memo: swapMemo, swapPayload: nil),
            txHash: txHash
        ))
    }

    // MARK: - Memo

    func testMarketSwapMemoPrefixes() {
        for memo in ["=:BTC.BTC:bc1q", "SWAP:BTC.BTC:bc1q", "swap:BTC.BTC:bc1q", "s:BTC.BTC:bc1q", "S:BTC.BTC"] {
            XCTAssertTrue(NativeSwapTrackingService.isMarketSwapMemo(memo), memo)
        }
        for memo in ["=<:BTC.BTC:bc1q", "m=<:1RUNE:2BTC:0", "SECURE+:thor1", "+:BTC.BTC", "-:BTC.BTC:10000", "=", "", nil] {
            XCTAssertFalse(NativeSwapTrackingService.isMarketSwapMemo(memo), memo ?? "nil")
        }
    }
}
