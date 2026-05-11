//
//  SwapRouter.swift
//  VultisigApp
//

import SwiftUI

struct SwapRouter {

    @ViewBuilder
    func build(_ route: SwapRoute) -> some View {
        switch route {
        case .root(let fromCoin, let toCoin, let vault):
            buildDetailsScreen(fromCoin: fromCoin, toCoin: toCoin, vault: vault)
        case .verify(let tx, let vault):
            buildVerifyScreen(tx: tx, vault: vault)
        case .pair(let vault, let tx, let keysignPayload, let fastVaultPassword):
            buildPairScreen(
                vault: vault,
                tx: tx,
                keysignPayload: keysignPayload,
                fastVaultPassword: fastVaultPassword
            )
        case .keysign(let input, let tx):
            buildKeysignScreen(input: input, tx: tx)
        case .done(let vault, let hash, let approveHash, let chain, let tx, let progressLink):
            buildDoneScreen(
                vault: vault,
                hash: hash,
                approveHash: approveHash,
                chain: chain,
                tx: tx,
                progressLink: progressLink
            )
        }
    }

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
