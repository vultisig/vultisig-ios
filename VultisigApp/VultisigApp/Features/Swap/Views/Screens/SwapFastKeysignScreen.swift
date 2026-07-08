//
//  SwapFastKeysignScreen.swift
//  VultisigApp
//
//  Fast-vault Swap keysign screen. Reached directly from Verify (no
//  pairing screen) for fast vaults: it hosts `FastKeysignBootstrapView`,
//  which provisions the relay session off-screen and then drives the
//  standard `KeysignView`. Mirrors `SwapKeysignScreen`'s done-navigation
//  and predicate-based retry handling.
//

import SwiftUI

struct SwapFastKeysignScreen: View {
    @Environment(\.router) var router

    let vault: Vault
    let keysignPayload: KeysignPayload
    let transaction: SwapTransaction
    let retrySignal: SwapRetrySignal
    let fastVaultPassword: String
    @State private var viewModel: SwapKeysignViewModel

    init(
        vault: Vault,
        keysignPayload: KeysignPayload,
        transaction: SwapTransaction,
        retrySignal: SwapRetrySignal,
        fastVaultPassword: String
    ) {
        self.vault = vault
        self.keysignPayload = keysignPayload
        self.transaction = transaction
        self.retrySignal = retrySignal
        self.fastVaultPassword = fastVaultPassword
        self._viewModel = State(initialValue: SwapKeysignViewModel(retrySignal: retrySignal))
    }

    var body: some View {
        Screen {
            FastKeysignBootstrapView(
                vault: vault,
                keysignPayload: keysignPayload,
                customMessagePayload: nil,
                fastVaultPassword: fastVaultPassword,
                transferViewModel: viewModel
            )
        }
        .screenNavigationBarHidden()
        .screenEdgeInsets(.zero)
        .onChange(of: viewModel.keysignFinished) { _, finished in
            guard finished, let hash = viewModel.hash else { return }
            let chain = transaction.fromCoin.chain
            router.navigate(to: SwapRoute.done(
                vaultPubKeyECDSA: vault.pubKeyECDSA,
                hash: hash,
                approveHash: viewModel.approveHash,
                chain: chain,
                transaction: transaction,
                progressLink: transaction.progressLink(hash: hash)
            ))
        }
        .onChange(of: retrySignal.pendingRetryReason) { _, reason in
            guard reason != nil else { return }
            // Pop back to the verify screen — robust to deep-links that add
            // routes before .root. Fast stack: root -> verify -> keysign.
            router.navigateBack { destination in
                guard let route = destination as? SwapRoute else { return false }
                if case .verify = route { return true }
                return false
            }
        }
        .onDisappear {
            viewModel.stopMediator()
        }
    }
}
