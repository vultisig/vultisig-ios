//
//  SwapRouteBuilder.swift
//  VultisigApp
//

import SwiftUI

struct SwapRouteBuilder {

    @ViewBuilder
    func buildDetailsScreen(fromCoin: Coin?, toCoin: Coin?, vault: Vault) -> some View {
        SwapDetailsScreen(fromCoin: fromCoin, toCoin: toCoin, vault: vault)
    }

    @ViewBuilder
    func buildVerifyScreen(transaction: SwapTransaction, retrySignal: SwapRetrySignal, vault: Vault) -> some View {
        SwapVerifyScreen(transaction: transaction, retrySignal: retrySignal, vault: vault)
    }

    @ViewBuilder
    func buildPairScreen(
        vault: Vault,
        transaction: SwapTransaction,
        retrySignal: SwapRetrySignal,
        keysignPayload: KeysignPayload,
        fastVaultPassword: String?
    ) -> some View {
        SwapPairScreen(
            vault: vault,
            transaction: transaction,
            retrySignal: retrySignal,
            keysignPayload: keysignPayload,
            fastVaultPassword: fastVaultPassword
        )
    }

    @ViewBuilder
    func buildKeysignScreen(input: KeysignInput, transaction: SwapTransaction, retrySignal: SwapRetrySignal) -> some View {
        SwapKeysignScreen(input: input, transaction: transaction, retrySignal: retrySignal)
    }

    @ViewBuilder
    func buildDoneScreen(
        vault: Vault,
        hash: String,
        approveHash: String?,
        chain: Chain,
        transaction: SwapTransaction,
        progressLink: String?
    ) -> some View {
        SwapDoneScreen(
            vault: vault,
            hash: hash,
            approveHash: approveHash,
            chain: chain,
            transaction: transaction,
            progressLink: progressLink
        )
    }
}
