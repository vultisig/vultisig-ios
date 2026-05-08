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
    func buildVerifyScreen(tx: SwapTransaction, vault: Vault) -> some View {
        SwapVerifyScreen(tx: tx, vault: vault)
    }

    @ViewBuilder
    func buildPairScreen(
        vault: Vault,
        tx: SwapTransaction,
        keysignPayload: KeysignPayload,
        fastVaultPassword: String?
    ) -> some View {
        SwapPairScreen(
            vault: vault,
            tx: tx,
            keysignPayload: keysignPayload,
            fastVaultPassword: fastVaultPassword
        )
    }

    @ViewBuilder
    func buildKeysignScreen(input: KeysignInput, tx: SwapTransaction) -> some View {
        SwapKeysignScreen(input: input, tx: tx)
    }

    @ViewBuilder
    func buildDoneScreen(
        vault: Vault,
        hash: String,
        approveHash: String?,
        chain: Chain,
        tx: SwapTransaction,
        progressLink: String?
    ) -> some View {
        SwapDoneScreen(
            vault: vault,
            hash: hash,
            approveHash: approveHash,
            chain: chain,
            tx: tx,
            progressLink: progressLink
        )
    }
}
