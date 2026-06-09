//
//  SwapPairScreen.swift
//  VultisigApp
//

import SwiftUI

struct SwapPairScreen: View {
    @Environment(\.router) var router

    let vault: Vault
    let transaction: SwapTransaction
    let retrySignal: SwapRetrySignal
    let keysignPayload: KeysignPayload
    let fastVaultPassword: String?

    var body: some View {
        PairScreen(
            vault: vault,
            keysignPayload: keysignPayload,
            fastVaultPassword: fastVaultPassword,
            previewType: .Swap,
            swapTransaction: transaction
        ) { input in
            router.navigate(to: SwapRoute.keysign(input: input, transaction: transaction, retrySignal: retrySignal))
        }
    }
}
