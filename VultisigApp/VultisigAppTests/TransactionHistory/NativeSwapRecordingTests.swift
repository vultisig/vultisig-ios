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

import BigInt
import XCTest
@testable import VultisigApp

@MainActor
final class NativeSwapRecordingTests: XCTestCase {

    private let txHash = "0xabc"
    private let swapMemo = "=:BTC.BTC:bc1qexample:0/1/0:va:50"

    // MARK: - Initiator

    func testInitiatorNativeMarketSwapIsTrackedOnItsProtocolNetwork() {
        let cases: [(SwapQuote, Chain)] = [
            (.thorchain(makeQuote(memo: swapMemo)), .thorChain),
            (.thorchainChainnet(makeQuote(memo: swapMemo)), .thorChainChainnet),
            (.thorchainStagenet(makeQuote(memo: swapMemo)), .thorChainStagenet),
            (.mayachain(makeQuote(memo: swapMemo)), .mayaChain)
        ]
        for (quote, network) in cases {
            let tracking = SwapDoneScreen.swapTracking(for: makeTransaction(kind: .market(quote)), hash: txHash)
            XCTAssertEqual(tracking, NativeSwapTrackingService.metadata(broadcastHash: txHash, network: network))
        }
    }

    func testInitiatorLimitOrderKeepsLimitTracking() {
        let tracking = SwapDoneScreen.swapTracking(for: makeLimitTransaction(), hash: txHash)
        XCTAssertEqual(tracking?.providerKind, THORChainLimitTrackingService.providerKind)
    }

    func testInitiatorAggregatorRoutesAreNotNativeTracked() {
        for quote in [SwapQuote.oneinch(makeEVMQuote(), fee: nil), .lifi(makeEVMQuote(), fee: nil, integratorFee: nil)] {
            XCTAssertNil(SwapDoneScreen.swapTracking(for: makeTransaction(kind: .market(quote)), hash: txHash))
        }
        XCTAssertNil(SwapDoneScreen.swapTracking(for: makeTransaction(kind: .market(nil)), hash: txHash))
    }

    /// A SECURE+ mint rides a synthetic THORChain quote, and Midgard indexes the
    /// deposit as a mint, never as a swap.
    func testInitiatorSecuredMintIsNotNativeTracked() {
        let quote = SwapCryptoLogic.securedMintQuote(fromAmount: 1, toCoin: makeCoin(.thorChain, ticker: "BTC"))
        var transaction = makeTransaction(kind: .market(quote))
        transaction.mode = .securedMint
        XCTAssertNil(SwapDoneScreen.swapTracking(for: transaction, hash: txHash))
    }

    // MARK: - Co-signer

    func testCosignerNativeMarketSwapIsTrackedOnItsProtocolNetwork() {
        let cases: [(SwapPayload, Chain)] = [
            (.thorchain(makeThorchainPayload()), .thorChain),
            (.thorchainChainnet(makeThorchainPayload()), .thorChainChainnet),
            (.thorchainStagenet(makeThorchainPayload()), .thorChainStagenet),
            (.mayachain(makeThorchainPayload()), .mayaChain)
        ]
        for (payload, network) in cases {
            let tracking = TransactionHistoryRecorder.swapTracking(
                for: makeKeysignPayload(memo: swapMemo, swapPayload: payload),
                txHash: txHash
            )
            XCTAssertEqual(tracking, NativeSwapTrackingService.metadata(broadcastHash: txHash, network: network))
        }
    }

    func testCosignerErc20LimitOrderKeepsLimitTracking() {
        let tracking = TransactionHistoryRecorder.swapTracking(
            for: makeKeysignPayload(memo: "=<:BTC.BTC:bc1qexample:1e6:va:50", swapPayload: .thorchain(makeThorchainPayload())),
            txHash: txHash
        )
        XCTAssertEqual(tracking?.providerKind, THORChainLimitTrackingService.providerKind)
    }

    /// ERC20 SECURE+ mints and LP adds ride a THORChain payload for the router's
    /// `depositWithExpiry`; only the memo says they are not swaps.
    func testCosignerRouterDepositsThatAreNotSwapsAreNotNativeTracked() {
        for memo in ["SECURE+:thor1vault", "+:ETH.USDC-0XA0B8:thor1lp", "", nil] {
            let tracking = TransactionHistoryRecorder.swapTracking(
                for: makeKeysignPayload(memo: memo, swapPayload: .thorchain(makeThorchainPayload())),
                txHash: txHash
            )
            XCTAssertNil(tracking, "\(memo ?? "nil") is not a market swap")
        }
    }

    func testCosignerWithoutANativePayloadIsNotNativeTracked() {
        XCTAssertNil(TransactionHistoryRecorder.swapTracking(
            for: makeKeysignPayload(memo: swapMemo, swapPayload: nil),
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

    // MARK: - Fixtures

    private func makeCoin(_ chain: Chain, ticker: String) -> Coin {
        Coin(asset: CoinMeta.make(chain: chain, ticker: ticker, decimals: 18), address: "addr-\(ticker)", hexPublicKey: "")
    }

    private func makeTransaction(kind: SwapKind) -> SwapTransaction {
        let eth = makeCoin(.ethereum, ticker: "ETH")
        return SwapTransaction(
            fromCoin: eth,
            toCoin: makeCoin(.bitcoin, ticker: "BTC"),
            fromAmount: 1,
            kind: kind,
            gas: .zero,
            gasLimit: .zero,
            thorchainFee: .zero,
            vultDiscountBps: 0,
            referralDiscountBps: 0,
            feeCoin: eth,
            advancedSettings: .default
        )
    }

    private func makeLimitTransaction() -> SwapTransaction {
        makeTransaction(kind: .limit(LimitOrderRecord(
            inboundTxHash: "",
            sourceAsset: "ETH.ETH",
            sourceAmount: "1000000000000000000",
            sourceDecimals: 18,
            targetAsset: "BTC.BTC",
            destAddress: "addr-BTC",
            targetPrice: 1,
            expiryBlocks: 14_400
        )))
    }

    private func makeQuote(memo: String) -> ThorchainSwapQuote {
        ThorchainSwapQuote(
            dustThreshold: nil,
            expectedAmountOut: "0",
            expiry: 0,
            fees: Fees(affiliate: "0", asset: "BTC.BTC", outbound: "0", total: "0", liquidity: nil, slippageBps: nil, totalBps: nil),
            inboundAddress: nil,
            inboundConfirmationBlocks: nil,
            inboundConfirmationSeconds: nil,
            memo: memo,
            notes: "",
            outboundDelayBlocks: 0,
            outboundDelaySeconds: 0,
            recommendedMinAmountIn: "0",
            totalSwapSeconds: nil,
            warning: "",
            router: nil,
            maxStreamingQuantity: nil
        )
    }

    private func makeEVMQuote() -> EVMQuote {
        EVMQuote(
            dstAmount: "100000000",
            tx: EVMQuote.Transaction(from: "0xfrom", to: "0xrouter", data: "0xdeadbeef", value: "0", gasPrice: "0", gas: 0)
        )
    }

    private func makeThorchainPayload() -> THORChainSwapPayload {
        THORChainSwapPayload(
            fromAddress: "0xfrom",
            fromCoin: .example,
            toCoin: .example,
            vaultAddress: "0xvault",
            routerAddress: "0xrouter",
            fromAmount: BigInt(1000),
            toAmountDecimal: 1,
            toAmountLimit: "0",
            streamingInterval: "0",
            streamingQuantity: "0",
            expirationTime: 0,
            isAffiliate: false
        )
    }

    private func makeKeysignPayload(memo: String?, swapPayload: SwapPayload?) -> KeysignPayload {
        KeysignPayload(
            coin: .example,
            toAddress: "0xrouter",
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
