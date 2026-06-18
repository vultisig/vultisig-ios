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
        case .verify(let transaction, let retrySignal, let vaultPubKeyECDSA):
            if let vault = lookupVault(pubKeyECDSA: vaultPubKeyECDSA) {
                buildVerifyScreen(transaction: transaction, retrySignal: retrySignal, vault: vault)
            }
        case .pair(let vaultPubKeyECDSA, let transaction, let retrySignal, let keysignPayload, let fastVaultPassword):
            if let vault = lookupVault(pubKeyECDSA: vaultPubKeyECDSA) {
                buildPairScreen(
                    vault: vault,
                    transaction: transaction,
                    retrySignal: retrySignal,
                    keysignPayload: keysignPayload,
                    fastVaultPassword: fastVaultPassword
                )
            }
        case .keysign(let input, let transaction, let retrySignal):
            buildKeysignScreen(input: input, transaction: transaction, retrySignal: retrySignal)
        case .done(let vaultPubKeyECDSA, let hash, let approveHash, let chain, let transaction, let progressLink):
            if let vault = lookupVault(pubKeyECDSA: vaultPubKeyECDSA) {
                buildDoneScreen(
                    vault: vault,
                    hash: hash,
                    approveHash: approveHash,
                    chain: chain,
                    transaction: transaction,
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
