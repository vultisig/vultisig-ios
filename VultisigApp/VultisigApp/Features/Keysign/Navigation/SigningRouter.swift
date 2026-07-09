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

import OSLog
import SwiftData
import SwiftUI

private let logger = Logger(subsystem: "com.vultisig.app", category: "signing-router")

struct SigningRouter {

    @MainActor
    @ViewBuilder
    func build(_ route: SigningRoute) -> some View {
        switch route {
        case .pair(let context, let keysignPayload, let fastVaultPassword):
            pairScreen(context: context, keysignPayload: keysignPayload, fastVaultPassword: fastVaultPassword)
        case .keysign(let keysignRoute):
            keysignScreen(keysignRoute)
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
    private func keysignScreen(_ route: SigningKeysignRoute) -> some View {
        switch route {
        case .ready(let input, let context):
            // Paired: the KeysignInput (committee known) drives the ceremony.
            SigningKeysignScreen(source: .ready(input), context: context)
        case .fast(let context, let keysignPayload, let fastVaultPassword):
            // Fast: resolve the live vault on MainActor and build the fast
            // KeysignStartInput here so no live @Model rides the route.
            if let vault = resolveVault(for: context) {
                SigningKeysignScreen(
                    source: .fast(
                        vault: vault,
                        keysignPayload: keysignPayload,
                        customMessagePayload: nil,
                        fastVaultPassword: fastVaultPassword
                    ),
                    context: context
                )
            }
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

    // Sole source of a nil vault on the shared signing route (Send/FunctionCall
    // carry the live vault). Log every nil path so a stale/deleted-vault route —
    // which otherwise renders a blank pair/keysign/done screen — is diagnosable.
    @MainActor
    private func lookupVault(pubKeyECDSA: String) -> Vault? {
        guard let context = Storage.shared.modelContext else {
            logger.error("Vault lookup failed: no modelContext; signing screen will not render")
            return nil
        }
        let descriptor = FetchDescriptor<Vault>(predicate: #Predicate { $0.pubKeyECDSA == pubKeyECDSA })
        do {
            guard let vault = try context.fetch(descriptor).first else {
                logger.error("Vault lookup found no vault for the routed key; signing screen will not render")
                return nil
            }
            return vault
        } catch {
            logger.error("Vault lookup fetch failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
