//
//  SendPairScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 13/08/2025.
//

import SwiftUI

struct SendPairScreen: View {
    @Environment(\.router) var router

    let vault: Vault
    let tx: SendTransaction
    let retrySignal: SendRetrySignal
    let keysignPayload: KeysignPayload
    let fastVaultPassword: String?

    var body: some View {
        PairScreen(
            vault: vault,
            keysignPayload: keysignPayload,
            fastVaultPassword: fastVaultPassword,
            previewType: .Send,
            sendPreviewOverride: sendPreviewOverride
        ) { input in
            router.navigate(to: SendRoute.keysign(input: input, tx: tx, retrySignal: retrySignal))
        }
    }

    /// When the signed payload's coin differs from the display `tx` coin, the
    /// payload-derived pairing/QR preview ("0 ETH → MSCA" for a Circle USDC
    /// withdraw) would mislead. In that case surface the display `tx`'s amount
    /// + recipient instead, leaving the signed payload untouched. For every
    /// regular send the coins match, so this stays `nil` and the preview keeps
    /// reading from the payload.
    private var sendPreviewOverride: SendPreviewOverride? {
        SendPreviewOverride.makeIfNeeded(displayTx: tx, signedPayload: keysignPayload)
    }
}
