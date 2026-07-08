//
//  SigningRouter.swift
//  VultisigApp
//
//  Single router for the shared `SigningRoute`, registered once in
//  `ContentView`. Builds the shared pairing screen and dispatches to each
//  flow's keysign / done screens based on the folded `SigningTxContext` /
//  `DoneKind` payloads.
//
//  Swap routes carry `Vault.pubKeyECDSA` (not a live `@Model`); the live
//  vault is re-fetched here on `MainActor` before a screen is built, so a
//  SwiftData `@Model` never rides through the `NavigationPath`.
//

import SwiftData
import SwiftUI

struct SigningRouter {

    @MainActor
    @ViewBuilder
    func build(_ route: SigningRoute) -> some View {
        switch route {
        case .pair(let context, let keysignPayload, let fastVaultPassword):
            pairScreen(context: context, keysignPayload: keysignPayload, fastVaultPassword: fastVaultPassword)
        case .fastKeysign(let context, let keysignPayload, let fastVaultPassword):
            fastKeysignScreen(context: context, keysignPayload: keysignPayload, fastVaultPassword: fastVaultPassword)
        case .keysign(let input, let context):
            keysignScreen(input: input, context: context)
        case .done(let kind):
            doneScreen(kind: kind)
        }
    }

    @MainActor
    @ViewBuilder
    private func pairScreen(
        context: SigningTxContext,
        keysignPayload: KeysignPayload,
        fastVaultPassword: String?
    ) -> some View {
        if let vault = resolveVault(for: context) {
            SigningPairScreen(
                vault: vault,
                context: context,
                keysignPayload: keysignPayload,
                fastVaultPassword: fastVaultPassword
            )
        }
    }

    @MainActor
    @ViewBuilder
    private func fastKeysignScreen(
        context: SigningTxContext,
        keysignPayload: KeysignPayload,
        fastVaultPassword: String
    ) -> some View {
        if let vault = resolveVault(for: context) {
            switch context {
            case .send(_, let tx, let retry), .functionCall(_, let tx, let retry):
                SendFastKeysignScreen(
                    vault: vault,
                    keysignPayload: keysignPayload,
                    tx: tx,
                    retrySignal: retry,
                    fastVaultPassword: fastVaultPassword
                )
            case .swap(_, let transaction, let retry):
                SwapFastKeysignScreen(
                    vault: vault,
                    keysignPayload: keysignPayload,
                    transaction: transaction,
                    retrySignal: retry,
                    fastVaultPassword: fastVaultPassword
                )
            }
        }
    }

    @MainActor
    @ViewBuilder
    private func keysignScreen(input: KeysignInput, context: SigningTxContext) -> some View {
        switch context {
        case .send(_, let tx, let retry), .functionCall(_, let tx, let retry):
            SendKeysignScreen(input: input, tx: tx, retrySignal: retry)
        case .swap(_, let transaction, let retry):
            SwapKeysignScreen(input: input, transaction: transaction, retrySignal: retry)
        }
    }

    @MainActor
    @ViewBuilder
    private func doneScreen(kind: DoneKind) -> some View {
        switch kind {
        case .send(let vault, let hash, let chain, let tx, let keysignPayload):
            SendDoneScreen(vault: vault, hash: hash, chain: chain, tx: tx, keysignPayload: keysignPayload)
        case .swap(let vaultPubKeyECDSA, let hash, let approveHash, let chain, let transaction, let progressLink):
            if let vault = lookupVault(pubKeyECDSA: vaultPubKeyECDSA) {
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
    }

    // MARK: - Vault resolution
    //
    // Route values can flow through SwiftUI's `NavigationPath` across actor
    // hops; a `Vault` (`@Model`) must not. Send/FunctionCall keep the live
    // vault they already carried; Swap carries `pubKeyECDSA` and the live
    // object is re-fetched on `MainActor` right before the screen is built.

    @MainActor
    private func resolveVault(for context: SigningTxContext) -> Vault? {
        switch context {
        case .send(let vault, _, _), .functionCall(let vault, _, _):
            return vault
        case .swap(let vaultPubKeyECDSA, _, _):
            return lookupVault(pubKeyECDSA: vaultPubKeyECDSA)
        }
    }

    @MainActor
    private func lookupVault(pubKeyECDSA: String) -> Vault? {
        guard let context = Storage.shared.modelContext else { return nil }
        let descriptor = FetchDescriptor<Vault>(predicate: #Predicate { $0.pubKeyECDSA == pubKeyECDSA })
        return (try? context.fetch(descriptor))?.first
    }
}
