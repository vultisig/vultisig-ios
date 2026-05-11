//
//  SwapRouter.swift
//  VultisigApp
//

import SwiftData
import SwiftUI

struct SwapRouter {

    @MainActor
    @ViewBuilder
    func build(_ route: SwapRoute) -> some View {
        switch route {
        case .root(let fromCoinID, let toCoinID, let vaultPubKeyECDSA):
            if let vault = lookupVault(pubKeyECDSA: vaultPubKeyECDSA) {
                let fromCoin = lookupCoin(id: fromCoinID, in: vault)
                let toCoin = lookupCoin(id: toCoinID, in: vault)
                buildDetailsScreen(fromCoin: fromCoin, toCoin: toCoin, vault: vault)
            }
        case .verify(let tx, let vaultPubKeyECDSA):
            if let vault = lookupVault(pubKeyECDSA: vaultPubKeyECDSA) {
                buildVerifyScreen(tx: tx, vault: vault)
            }
        case .pair(let vaultPubKeyECDSA, let tx, let keysignPayload, let fastVaultPassword):
            if let vault = lookupVault(pubKeyECDSA: vaultPubKeyECDSA) {
                buildPairScreen(
                    vault: vault,
                    tx: tx,
                    keysignPayload: keysignPayload,
                    fastVaultPassword: fastVaultPassword
                )
            }
        case .keysign(let input, let tx):
            buildKeysignScreen(input: input, tx: tx)
        case .done(let vaultPubKeyECDSA, let hash, let approveHash, let chain, let tx, let progressLink):
            if let vault = lookupVault(pubKeyECDSA: vaultPubKeyECDSA) {
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

    // MARK: - SwiftData lookups
    //
    // Route values can flow through SwiftUI's NavigationPath across actor
    // hops; @Model objects (`Vault`, `Coin`) must not. The route carries
    // stable string identifiers; the live objects are re-fetched on
    // MainActor when the screen is about to be built.

    @MainActor
    private func lookupVault(pubKeyECDSA: String) -> Vault? {
        guard let context = Storage.shared.modelContext else { return nil }
        let descriptor = FetchDescriptor<Vault>(predicate: #Predicate { $0.pubKeyECDSA == pubKeyECDSA })
        return (try? context.fetch(descriptor))?.first
    }

    @MainActor
    private func lookupCoin(id: String?, in vault: Vault) -> Coin? {
        guard let id else { return nil }
        return vault.coins.first { $0.id == id }
    }
}
