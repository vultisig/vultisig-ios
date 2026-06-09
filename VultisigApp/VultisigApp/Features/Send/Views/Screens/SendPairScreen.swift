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
            previewType: .Send
        ) { input in
            router.navigate(to: SendRoute.keysign(input: input, tx: tx, retrySignal: retrySignal))
        }
    }
}
