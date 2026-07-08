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
    /// The payload the bootstrap actually signed. It can differ from the
    /// route's `keysignPayload` (e.g. Solana blockhash refresh), so the
    /// done screen shows the signed payload, matching the paired path.
    @State private var signedPayload: KeysignPayload?

    var body: some View {
        Screen {
            FastKeysignBootstrapView(
                vault: vault,
                keysignPayload: keysignPayload,
                customMessagePayload: nil,
                fastVaultPassword: fastVaultPassword,
                transferViewModel: viewModel,
                onKeysignInputResolved: { signedPayload = $0.keysignPayload }
            )
        }
        .screenNavigationBarHidden()
        .screenEdgeInsets(.zero)
        .onChange(of: viewModel.keysignFinished) { _, finished in
            guard finished, let hash = viewModel.hash else { return }
            let payload = signedPayload ?? keysignPayload
            router.navigate(to: SendRoute.done(
                vault: vault,
                hash: hash,
                chain: payload.coin.chain,
                tx: tx,
                keysignPayload: payload
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
