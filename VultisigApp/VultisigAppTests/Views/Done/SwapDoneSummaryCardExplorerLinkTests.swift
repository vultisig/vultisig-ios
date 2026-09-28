//
//  SwapDoneSummaryCardExplorerLinkTests.swift
//  VultisigAppTests
//
//  `SwapDoneSummaryCard`'s hash rows resolve their explorer link off
//  `fields.chain`, which both builders set to the SOURCE coin's chain
//  (`fromCoin` / `keysignPayload.coin`) — never the destination. For a
//  cross-chain SwapKit route (e.g. ADA -> USDC on Ethereum, #5485) that
//  distinction is the whole feature: getting it backwards would open
//  the destination chain's explorer for a hash that only exists on the
//  source chain.
//

import BigInt
@testable import VultisigApp
import XCTest

@MainActor
final class SwapDoneSummaryCardExplorerLinkTests: XCTestCase {

    private var token: TestContextToken!

    override func setUpWithError() throws {
        token = try TestStore.installInMemoryContainer()
    }

    override func tearDown() {
        TestStore.restore(token)
        token = nil
    }

    func testInitiatorFieldsChainIsTheSourceChainNotTheDestination() {
        let transaction = makeCrossChainTransaction()
        let card = SwapDoneSummaryCard.initiator(
            transaction: transaction,
            vault: TestStore.makeVault(pubKey: "swap-done-explorer-initiator"),
            sendSummaryViewModel: SendSummaryViewModel(),
            hash: "cardano-tx-hash",
            approveHash: nil
        )

        XCTAssertEqual(card.fields.chain, .cardano)
        XCTAssertNotEqual(card.fields.chain, .ethereum)
        XCTAssertEqual(
            ExplorerLinkBuilder.getExplorerURL(chain: card.fields.chain, txid: card.fields.txHash),
            "https://cardanoscan.io/transaction/cardano-tx-hash"
        )
    }

    func testCosignerFieldsChainIsTheSourceChainNotTheDestination() {
        let keysignPayload = makeCrossChainKeysignPayload()
        let card = SwapDoneSummaryCard.cosigner(
            keysignPayload: keysignPayload,
            vault: TestStore.makeVault(pubKey: "swap-done-explorer-cosigner"),
            summaryViewModel: JoinKeysignSummaryViewModel(),
            txHash: "cardano-tx-hash",
            networkFee: "0.17 ADA"
        )

        XCTAssertEqual(card.fields.chain, .cardano)
        XCTAssertNotEqual(card.fields.chain, .ethereum)
        XCTAssertEqual(
            ExplorerLinkBuilder.getExplorerURL(chain: card.fields.chain, txid: card.fields.txHash),
            "https://cardanoscan.io/transaction/cardano-tx-hash"
        )
    }

    // MARK: - Fixtures

    private func makeCrossChainTransaction() -> SwapTransaction {
        let ada = makeCoin(.cardano, ticker: "ADA", decimals: 6, isNative: true)
        let usdc = makeCoin(.ethereum, ticker: "USDC", decimals: 6, isNative: false)
        let quote = ThorchainSwapQuote(
            dustThreshold: nil,
            expectedAmountOut: "100000000",
            expiry: 0,
            fees: Fees(affiliate: "0", asset: "ADA", outbound: "0", total: "0", liquidity: nil, slippageBps: nil, totalBps: nil),
            inboundAddress: "cardano-inbound",
            inboundConfirmationBlocks: nil,
            inboundConfirmationSeconds: nil,
            memo: "swap-memo",
            notes: "",
            outboundDelayBlocks: 0,
            outboundDelaySeconds: 0,
            recommendedMinAmountIn: "0",
            totalSwapSeconds: nil,
            warning: "",
            router: nil,
            maxStreamingQuantity: nil
        )
        return SwapTransaction(
            fromCoin: ada,
            toCoin: usdc,
            fromAmount: 1.0,
            kind: .market(.thorchain(quote)),
            gas: 0,
            gasLimit: 0,
            thorchainFee: 0,
            vultDiscountBps: 0,
            referralDiscountBps: 0,
            feeCoin: ada,
            advancedSettings: .default
        )
    }

    private func makeCrossChainKeysignPayload() -> KeysignPayload {
        let ada = CoinMeta.make(chain: .cardano, ticker: "ADA", decimals: 6, isNativeToken: true)
        return KeysignPayload(
            coin: Coin(asset: ada, address: "addr1source", hexPublicKey: ""),
            toAddress: "0xrecipient",
            toAmount: BigInt(1),
            chainSpecific: .Cardano(byteFee: 44, sendMaxAmount: false, ttl: 0),
            utxos: [],
            memo: nil,
            swapPayload: nil,
            approvePayload: nil,
            vaultPubKeyECDSA: "",
            vaultLocalPartyID: "",
            libType: LibType.DKLS.toString(),
            wasmExecuteContractPayload: nil,
            tronTransferContractPayload: nil,
            tronTriggerSmartContractPayload: nil,
            tronTransferAssetContractPayload: nil,
            qbtcClaimPayload: nil,
            isQbtcClaim: false,
            skipBroadcast: false,
            signData: nil,
            dappMetadata: nil
        )
    }

    private func makeCoin(_ chain: Chain, ticker: String, decimals: Int, isNative: Bool) -> Coin {
        let asset = CoinMeta.make(chain: chain, ticker: ticker, decimals: decimals, isNativeToken: isNative)
        return Coin(asset: asset, address: "test-address-\(ticker)", hexPublicKey: "")
    }
}
