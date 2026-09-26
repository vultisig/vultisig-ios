//
//  KeysignReviewFixture.swift
//  VultisigAppTests
//
//  Review and signing-route values for the presenter and router tests. Builds
//  unmanaged `Coin`s, so callers install an in-memory container first.
//

import Foundation
@testable import VultisigApp

@MainActor
enum KeysignReviewFixture {
    static let vaultPubKeyECDSA = "keysign-review-fixture-ecdsa"

    static func swapReview(retrySignal: SwapRetrySignal = SwapRetrySignal()) -> KeysignReview {
        .swap(transaction: swapTransaction(), retrySignal: retrySignal, vaultPubKeyECDSA: vaultPubKeyECDSA)
    }

    static func pairRoute() -> SigningRoute {
        .pair(context: swapContext(), keysignPayload: payload(), fastVaultPassword: nil)
    }

    static func fastKeysignRoute() -> SigningRoute {
        .keysign(.fast(context: swapContext(), keysignPayload: payload(), fastVaultPassword: "password"))
    }

    private static func swapContext() -> SigningTxContext {
        .swap(vaultPubKeyECDSA: vaultPubKeyECDSA, transaction: swapTransaction(), retry: SwapRetrySignal())
    }

    private static func swapTransaction() -> SwapTransaction {
        let arb = coin(.arbitrum, ticker: "ARB")
        let btc = coin(.bitcoin, ticker: "BTC")
        let record = LimitOrderRecord(
            inboundTxHash: "",
            sourceAsset: "ARB.ETH",
            sourceAmount: "1000000000000000000",
            sourceDecimals: 18,
            targetAsset: "BTC.BTC",
            destAddress: "addr-BTC",
            targetPrice: 1,
            expiryBlocks: 14_400
        )
        return SwapTransaction(
            fromCoin: arb,
            toCoin: btc,
            fromAmount: 1,
            kind: .limit(record),
            gas: .zero,
            gasLimit: .zero,
            thorchainFee: .zero,
            vultDiscountBps: 0,
            referralDiscountBps: 0,
            feeCoin: arb,
            advancedSettings: .default
        )
    }

    private static func payload() -> KeysignPayload {
        KeysignPayload(
            coin: coin(.arbitrum, ticker: "ARB"), toAddress: "test", toAmount: 1,
            chainSpecific: .Cosmos(accountNumber: 0, sequence: 0, gas: 0, transactionType: 0, ibcDenomTrace: nil, gasLimit: nil),
            utxos: [], memo: nil, swapPayload: nil, approvePayload: nil,
            vaultPubKeyECDSA: vaultPubKeyECDSA, vaultLocalPartyID: "iPhone", libType: "DKLS",
            wasmExecuteContractPayload: nil, tronTransferContractPayload: nil, tronTriggerSmartContractPayload: nil,
            tronTransferAssetContractPayload: nil, qbtcClaimPayload: nil, isQbtcClaim: false, skipBroadcast: false, signData: nil
        )
    }

    private static func coin(_ chain: Chain, ticker: String) -> Coin {
        Coin(asset: CoinMeta.make(chain: chain, ticker: ticker, decimals: 18), address: "addr-\(ticker)", hexPublicKey: "")
    }
}
