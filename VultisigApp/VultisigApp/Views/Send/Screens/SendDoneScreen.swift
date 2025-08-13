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
    
    var body: some View {
        Screen(title: "done") {
            SendCryptoDoneView(
                vault: vault,
                hash: hash,
                approveHash: nil,
                chain: chain,
                sendTransaction: tx,
                swapTransaction: nil
            )
        }
    }
}
