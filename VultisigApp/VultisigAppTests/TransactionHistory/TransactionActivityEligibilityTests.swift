import BigInt
import XCTest
@testable import VultisigApp

@MainActor
final class TransactionActivityEligibilityTests: XCTestCase {
    func testEveryBroadcastShapeIsEligibleButSigningOnlyIsNot() throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }
        XCTAssertTrue(TransactionActivityPolicy.isEligible(payload()))
        XCTAssertTrue(TransactionActivityPolicy.isEligible(payload(memo: "0xa9059cbb")))
        XCTAssertFalse(TransactionActivityPolicy.isEligible(payload(skipBroadcast: true)))
        XCTAssertTrue(TransactionActivityPolicy.isEligible(payload(qbtc: true)))
        XCTAssertTrue(TransactionActivityPolicy.isEligible(payload(maxSend: true)))
        XCTAssertTrue(TransactionActivityPolicy.isEligible(payload(memo: "=<:ETH.ETH:recipient:100")))
        XCTAssertTrue(TransactionActivityPolicy.isEligible(payload(memo: "m=<:hash:0")))
    }

    func testNativeMarketSwapsAndApprovalsAreEligible() throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }
        let approval = ERC20ApprovePayload(amount: BigInt(1), spender: "contract")
        XCTAssertTrue(TransactionActivityPolicy.isEligible(payload(approve: approval)))
        let coin = SendFormFixture.makeBTC()
        let nativeSwap = THORChainSwapPayload(fromAddress: "from", fromCoin: coin, toCoin: SendFormFixture.makeETH(),
                                              vaultAddress: "vault", routerAddress: nil, fromAmount: 1,
                                              toAmountDecimal: 1, toAmountLimit: "1", streamingInterval: "0",
                                              streamingQuantity: "0", expirationTime: 1, isAffiliate: false)
        let eligible = TransactionActivityPolicy.isEligible(payload(swap: .thorchain(nativeSwap)))
        XCTAssertTrue(eligible, "A broadcast THORChain swap must be eligible for a Live Activity")
        let swapKit = SwapKitSwapPayload(fromCoin: coin, toCoin: SendFormFixture.makeETH(), fromAmount: 1,
                                         toAmountDecimal: 1, txType: "PSBT", txPayload: Data(), targetAddress: "target",
                                         inboundAddress: nil, memo: nil, subProvider: "CHAINFLIP", swapID: "fixture")
        XCTAssertTrue(TransactionActivityPolicy.isEligible(payload(swap: .swapkit(swapKit))))
    }

    func testNativeReceiptsRouteToProtocolNetworkForExternalInbounds() throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }
        let native = THORChainSwapPayload(fromAddress: "from", fromCoin: SendFormFixture.makeBTC(),
            toCoin: SendFormFixture.makeETH(), vaultAddress: "vault", routerAddress: nil, fromAmount: 1,
            toAmountDecimal: 1, toAmountLimit: "1", streamingInterval: "0", streamingQuantity: "0",
            expirationTime: 1, isAffiliate: false)
        let routes: [(SwapPayload, Chain)] = [(.thorchain(native), .thorChain), (.mayachain(native), .mayaChain),
            (.thorchainChainnet(native), .thorChainChainnet), (.thorchainStagenet(native), .thorChainStagenet)]
        for (swap, network) in routes {
            let row = try XCTUnwrap(TransactionBroadcastReceipt.rows(hash: "inbound", approveHash: nil,
                payload: payload(swap: swap), pubKey: "vault").first)
            XCTAssertEqual(row.type, .swap)
            XCTAssertEqual(row.chainRawValue, Chain.bitcoin.rawValue)
            XCTAssertEqual(row.swapTracking?.providerKind, NativeSwapTrackingService.providerKind)
            XCTAssertEqual(row.swapTracking?.subProvider, network.rawValue)
            XCTAssertEqual(row.swapTracking?.broadcastHash, "inbound")
        }
    }

    func testGenericOperationsAndMaximumSendsDoNotInventTransferredAmounts() throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }
        for input in [payload(memo: "0xcontract"), payload(qbtc: true), payload(memo: "m=<:hash:0")] {
            let row = try XCTUnwrap(TransactionBroadcastReceipt.rows(hash: "accepted", approveHash: nil,
                payload: input, pubKey: "vault").first)
            XCTAssertEqual(row.type, .transaction)
            XCTAssertTrue(row.amountCrypto.isEmpty)
            XCTAssertTrue(row.amountFiat.isEmpty)
        }
        let maxSend = try XCTUnwrap(TransactionBroadcastReceipt.rows(hash: "max", approveHash: nil,
            payload: payload(maxSend: true), pubKey: "vault").first)
        XCTAssertEqual(maxSend.type, .send)
        XCTAssertTrue(maxSend.amountCrypto.isEmpty)
        XCTAssertTrue(TransactionBroadcastReceipt.rows(hash: "", approveHash: nil, payload: payload(), pubKey: "vault").isEmpty)
        XCTAssertTrue(TransactionBroadcastReceipt.rows(hash: "signed", approveHash: nil,
            payload: payload(skipBroadcast: true), pubKey: "vault").isEmpty)
    }

    func testApprovalCanBeRecordedBeforeTheMainBroadcastSucceeds() throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }
        let input = payload(approve: ERC20ApprovePayload(amount: BigInt(1_000_000), spender: "spender"))
        let approval = try XCTUnwrap(TransactionBroadcastReceipt.approval(hash: "approval", payload: input, pubKey: "vault"))
        XCTAssertEqual(approval.type, .approve)
        XCTAssertEqual(approval.txHash, "approval")
        XCTAssertEqual(approval.toAddress, "spender")
        XCTAssertTrue(approval.amountCrypto.isEmpty)
        let receipts = TransactionBroadcastReceipt.rows(hash: "main", approveHash: "approval", payload: input, pubKey: "vault")
        XCTAssertEqual(receipts.map(\.txHash), ["main", "approval"])
        XCTAssertNil(TransactionBroadcastReceipt.approval(hash: "", payload: input, pubKey: "vault"))
    }

    func testLimitReceiptUsesOrderTrackerBeforeSwapRoute() throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }
        let row = try XCTUnwrap(TransactionBroadcastReceipt.rows(hash: "order", approveHash: nil,
            payload: payload(memo: "=<:ETH.ETH:recipient:100"), pubKey: "vault").first)
        XCTAssertEqual(row.type, .limit)
        XCTAssertEqual(row.swapTracking?.providerKind, THORChainLimitTrackingService.providerKind)
    }

    func testOrdinaryTransfersRemainSendsWithoutASignedContentDecoder() throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }
        for chain in [Chain.ripple, .sui, .polkadot, .bittensor, .cardano, .bitcoin, .ethereum] {
            let coin = Coin(asset: CoinMeta(chain: chain, ticker: "COIN", logo: "", decimals: 8,
                priceProviderId: "", contractAddress: "", isNativeToken: true), address: "source", hexPublicKey: "")
            let row = try XCTUnwrap(TransactionBroadcastReceipt.rows(hash: "accepted", approveHash: nil,
                payload: payload(coin: coin, memo: "payment note"), pubKey: "vault").first)
            XCTAssertEqual(row.type, .send, chain.rawValue)
            XCTAssertFalse(row.amountCrypto.isEmpty, chain.rawValue)
        }
    }

    func testApprovalPlaceholdersCannotBecomeTransactionReceipts() throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }
        let input = payload(approve: ERC20ApprovePayload(amount: BigInt(1), spender: "spender"))
        let sentinel = SubstrateBroadcast.alreadyBroadcastedSentinel
        XCTAssertNil(TransactionBroadcastReceipt.approval(hash: sentinel, payload: input, pubKey: "vault"))
        XCTAssertTrue(TransactionBroadcastReceipt.rows(hash: sentinel, approveHash: nil, payload: input, pubKey: "vault").isEmpty)
    }

    func testGenericSwapReceiptsDistinguishAtomicRoutesFromSourceOnlyTracking() throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }
        let source = SendFormFixture.makeETH()
        let quote = EVMQuote(dstAmount: "1", tx: .init(from: "from", to: "router", data: "0x", value: "0", gasPrice: "1", gas: 200_000))
        for (chain, provider, expected) in [(Chain.ethereum, SwapProviderId.oneInch, "atomic"),
            (.ethereum, .kyberSwap, "atomic"), (.ethereum, .lifi, "atomic"), (.base, .lifi, "sourceOnly"),
            (.ethereum, .unknown("future"), "sourceOnly")] {
            let destination = Coin(asset: CoinMeta(chain: chain, ticker: "USDC", logo: "usdc", decimals: 6,
                priceProviderId: "", contractAddress: "token", isNativeToken: false), address: "destination", hexPublicKey: "")
            let swap = GenericSwapPayload(fromCoin: source, toCoin: destination, fromAmount: 1,
                toAmountDecimal: 1, quote: quote, provider: provider)
            let row = try XCTUnwrap(TransactionBroadcastReceipt.rows(hash: "accepted", approveHash: nil,
                payload: payload(swap: .generic(swap)), pubKey: "vault").first)
            XCTAssertEqual(row.type, .swap)
            XCTAssertEqual(row.swapTracking?.providerKind, TransactionActivityPolicy.nativeSourceProviderKind)
            XCTAssertEqual(row.swapTracking?.subProvider, expected)
        }
    }

    private func payload(coin: Coin? = nil, memo: String? = nil, skipBroadcast: Bool = false, qbtc: Bool = false,
                         approve: ERC20ApprovePayload? = nil, swap: SwapPayload? = nil, maxSend: Bool = false) -> KeysignPayload {
        KeysignPayload(
            coin: coin ?? swap?.fromCoin ?? SendFormFixture.makeETH(), toAddress: "0x1234567890123456789012345678901234567890",
            toAmount: BigInt(1_000_000_000_000_000_000),
            chainSpecific: maxSend ? .UTXO(byteFee: 1, sendMaxAmount: true)
                : .Ethereum(maxFeePerGasWei: 1, priorityFeeWei: 1, nonce: 0, gasLimit: 21_000),
            utxos: [], memo: memo, swapPayload: swap, approvePayload: approve,
            vaultPubKeyECDSA: "fixture", vaultLocalPartyID: "fixture", libType: "DKLS",
            wasmExecuteContractPayload: nil, tronTransferContractPayload: nil,
            tronTriggerSmartContractPayload: nil, tronTransferAssetContractPayload: nil,
            qbtcClaimPayload: nil, isQbtcClaim: qbtc, skipBroadcast: skipBroadcast, signData: nil
        )
    }
}
