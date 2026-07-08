//
//  SigningPairScreen.swift
//  VultisigApp
//
//  Shared pairing screen for the Send / Swap / FunctionCall signing flows.
//  Replaces the near-identical per-flow pair wrappers: it wraps the shared
//  `PairScreen`, derives the preview flavor from the `SigningTxContext`, and
//  advances into the shared `SigningRoute.keysign` once the peer has paired.
//

import SwiftUI

struct SigningPairScreen: View {
    @Environment(\.router) var router

    let vault: Vault
    let context: SigningTxContext
    let keysignPayload: KeysignPayload
    let fastVaultPassword: String?

    var body: some View {
        PairScreen(
            vault: vault,
            keysignPayload: keysignPayload,
            fastVaultPassword: fastVaultPassword,
            previewType: context.previewType,
            sendPreviewOverride: context.sendPreviewOverride(payload: keysignPayload),
            swapTransaction: context.swapTransaction
        ) { input in
            router.navigate(to: SigningRoute.keysign(input: input, context: context))
        }
    }
}
