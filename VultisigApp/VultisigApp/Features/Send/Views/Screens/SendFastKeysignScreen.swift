//
//  SendFastKeysignScreen.swift
//  VultisigApp
//
//  Fast-vault Send keysign screen. Reached directly from Verify (no
//  pairing screen) for fast vaults: it hosts `FastKeysignBootstrapView`,
//  which provisions the relay session off-screen and then drives the
//  standard `KeysignView`. Mirrors `SendKeysignScreen`'s done-navigation
//  and retry handling; the only difference is that the `KeysignInput`
//  is produced by the bootstrap rather than handed in pre-built.
//

import SwiftUI

struct SendFastKeysignScreen: View {
    @Environment(\.router) var router

    let vault: Vault
    let keysignPayload: KeysignPayload
    let tx: SendTransaction
    let retrySignal: SendRetrySignal
    let fastVaultPassword: String
    @StateObject var viewModel = SendKeysignViewModel()

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
            router.navigate(to: SendRoute.done(
                vault: vault,
                hash: hash,
                chain: keysignPayload.coin.chain,
                tx: tx,
                keysignPayload: keysignPayload
            ))
        }
        .onChange(of: viewModel.pendingRetryReason) { _, reason in
            guard let reason else { return }
            retrySignal.pendingRetryReason = reason
            viewModel.pendingRetryReason = nil
            router.navigateBackToKeysignVerify()
        }
    }
}
