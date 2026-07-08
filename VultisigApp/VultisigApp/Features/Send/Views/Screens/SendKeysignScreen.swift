//
//  SendKeysignScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 13/08/2025.
//

import SwiftUI

struct SendKeysignScreen: View {
    @Environment(\.router) var router

    let input: KeysignInput
    let tx: SendTransaction
    let retrySignal: SendRetrySignal
    @StateObject var viewModel = SendKeysignViewModel()

    var body: some View {
        Screen {
            KeysignView(
                vault: input.vault,
                keysignCommittee: input.keysignCommittee,
                mediatorURL: input.mediatorURL,
                sessionID: input.sessionID,
                keysignType: input.keysignType,
                messsageToSign: input.messsageToSign,
                keysignPayload: input.keysignPayload,
                customMessagePayload: input.customMessagePayload,
                transferViewModel: viewModel,
                encryptionKeyHex: input.encryptionKeyHex,
                isInitiateDevice: input.isInitiateDevice
            )
        }
        .screenNavigationBarHidden()
        .screenEdgeInsets(.zero)
        .onChange(of: viewModel.keysignFinished) { _, finished in
            guard finished else { return }

            guard
                  let hash = viewModel.hash,
                  let chain = input.keysignPayload?.coin.chain
            else { return }

            router.navigate(to: SigningRoute.done(.send(
                vault: input.vault,
                hash: hash,
                chain: chain,
                tx: tx,
                keysignPayload: input.keysignPayload
            )))
        }
        .onChange(of: viewModel.pendingRetryReason) { _, reason in
            guard let reason else { return }
            retrySignal.pendingRetryReason = reason
            viewModel.pendingRetryReason = nil
            router.navigateBackToKeysignVerify()
        }
    }
}

class SendKeysignViewModel: ObservableObject, TransferViewModel {
    @Published var keysignFinished: Bool = false
    @Published var pendingRetryReason: BroadcastRetryReason?

    var hash: String?
    var approveHash: String?

    func moveToNextView() {
        keysignFinished = true
    }

    func retryBroadcast(reason: BroadcastRetryReason) {
        pendingRetryReason = reason
    }
}
