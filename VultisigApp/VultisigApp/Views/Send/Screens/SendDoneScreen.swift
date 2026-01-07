//
//  SendDoneScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 13/08/2025.
//

import SwiftUI

struct SendDoneScreen: View {
    let vault: Vault
    let hash: String
    let chain: Chain
    let tx: SendTransaction
    let keysignPayload: KeysignPayload?

    var body: some View {
        Screen(title: "done".localized) {
            SendCryptoDoneView(
                vault: vault,
                hash: hash,
                approveHash: nil,
                chain: chain,
                sendTransaction: tx,
                swapTransaction: nil,
                isSend: true,
                contentPadding: 0,
                keysignPayload: keysignPayload
            )
        }
        .navigationBarBackButtonHidden(true)
    }
}
