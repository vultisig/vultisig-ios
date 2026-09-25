//
//  NativeSwapFixtures.swift
//  VultisigAppTests
//
//  Swap transactions, quotes and keysign payloads shared by the native-swap
//  recording and done-screen dispatch tests.
//

import BigInt
import Foundation
@testable import VultisigApp

@MainActor
enum NativeSwapFixtures {
    static let swapMemo = "=:BTC.BTC:bc1qexample:0/1/0:va:50"

    static func makeCoin(_ chain: Chain, ticker: String) -> Coin {
        Coin(asset: CoinMeta.make(chain: chain, ticker: ticker, decimals: 18), address: "addr-\(ticker)", hexPublicKey: "")
    }

    static func makeTransaction(kind: SwapKind) -> SwapTransaction {
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

    static func makeLimitTransaction() -> SwapTransaction {
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

    static func makeQuote(memo: String) -> ThorchainSwapQuote {
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

    static func makeEVMQuote() -> EVMQuote {
        EVMQuote(
            dstAmount: "100000000",
            tx: EVMQuote.Transaction(from: "0xfrom", to: "0xrouter", data: "0xdeadbeef", value: "0", gasPrice: "0", gas: 0)
        )
    }

    static func makeThorchainPayload() -> THORChainSwapPayload {
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

    static func makeKeysignPayload(memo: String?, swapPayload: SwapPayload?) -> KeysignPayload {
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
