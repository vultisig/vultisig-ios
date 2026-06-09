//
//  FunctionCallPairScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 13/08/2025.
//

import SwiftUI

struct FunctionCallPairScreen: View {
    @Environment(\.router) var router

    let vault: Vault
    let tx: SendTransaction
    let keysignPayload: KeysignPayload
    let fastVaultPassword: String?

    var body: some View {
        PairScreen(
            vault: vault,
            keysignPayload: keysignPayload,
            fastVaultPassword: fastVaultPassword,
            previewType: .Send
        ) { input in
            router.navigate(to: FunctionCallRoute.keysign(input: input, tx: tx, retrySignal: SendRetrySignal()))
        }
    }
}
