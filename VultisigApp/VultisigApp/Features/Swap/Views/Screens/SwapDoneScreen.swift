//
//  SwapDoneScreen.swift
//  VultisigApp
//

import SwiftUI
import Mediator

struct SwapDoneScreen: View {
    let vault: Vault
    let hash: String
    let approveHash: String?
    let chain: Chain
    @ObservedObject var tx: SwapTransaction
    let progressLink: String?

    var body: some View {
        Screen {
            SendCryptoDoneView(
                vault: vault,
                hash: hash,
                approveHash: approveHash,
                chain: chain,
                progressLink: progressLink,
                sendTransaction: nil,
                swapTransaction: tx,
                isSend: false
            )
        }
        .screenTitle("done".localized)
        .screenBackButtonHidden()
        .onAppear {
            Task {
                try? await Task.sleep(for: .seconds(5))
                Mediator.shared.stop()
            }
        }
    }
}
