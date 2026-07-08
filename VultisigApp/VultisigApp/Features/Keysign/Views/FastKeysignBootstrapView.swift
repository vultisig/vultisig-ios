//
//  FastKeysignBootstrapView.swift
//  VultisigApp
//
//  Shared keysign-hosted wait wrapper for the fast-vault signing path.
//  A fast vault has no one to pair with, so instead of mounting the
//  pairing screen it lands here: the off-screen session bootstrap runs
//  in `.task` (showing the signing animation while Vultiserver joins),
//  and once the `KeysignInput` is ready it drives the standard
//  `KeysignView`. The bootstrap wait and the keysign ceremony render the
//  same `KeysignAnimationView`, so the transition is seamless. Errors
//  surface through the existing keysign error surface with a retry that
//  re-runs the bootstrap — no new error UI. Used by Send / Swap /
//  FunctionCall / CustomMessage.
//

import SwiftUI

struct FastKeysignBootstrapView: View {
    let vault: Vault
    let keysignPayload: KeysignPayload?
    let customMessagePayload: CustomMessagePayload?
    let fastVaultPassword: String
    let transferViewModel: TransferViewModel?
    /// Fires once the bootstrap has assembled the `KeysignInput`. Callers
    /// that navigate on completion (Send/FunctionCall done screens) use it
    /// to read the actually-signed payload — the bootstrap can replace the
    /// input payload before signing (e.g. Solana blockhash refresh), so the
    /// original route payload can diverge from what was signed.
    var onKeysignInputResolved: ((KeysignInput) -> Void)?

    @State private var input: KeysignInput?
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            if let input {
                KeysignView(
                    vault: input.vault,
                    keysignCommittee: input.keysignCommittee,
                    mediatorURL: input.mediatorURL,
                    sessionID: input.sessionID,
                    keysignType: input.keysignType,
                    messsageToSign: input.messsageToSign,
                    keysignPayload: input.keysignPayload,
                    customMessagePayload: input.customMessagePayload,
                    transferViewModel: transferViewModel,
                    encryptionKeyHex: input.encryptionKeyHex,
                    isInitiateDevice: input.isInitiateDevice
                )
            } else {
                // While bootstrapping: `errorMessage == nil` so this shows
                // the signing animation. On failure it flips to the shared
                // keysign error surface with a retry that re-runs bootstrap.
                SendCryptoKeysignView(
                    title: errorMessage,
                    showError: errorMessage != nil,
                    coinLogo: keysignPayload?.coin.logo,
                    errorButtonTitle: "tryAgain".localized,
                    errorAction: { Task { await runBootstrap() } }
                )
            }
        }
        .task { await runBootstrap() }
    }

    @MainActor
    private func runBootstrap() async {
        errorMessage = nil
        do {
            let bootstrap = FastVaultKeysignBootstrap()
            let resolved = try await bootstrap.makeKeysignInput(
                vault: vault,
                keysignPayload: keysignPayload,
                customMessagePayload: customMessagePayload,
                fastVaultPassword: fastVaultPassword
            )
            input = resolved
            onKeysignInputResolved?(resolved)
        } catch {
            input = nil
            errorMessage = error.localizedDescription
        }
    }
}
