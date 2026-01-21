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
    @StateObject var viewModel = SendKeysignViewModel()

    var body: some View {
        Screen(title: "keysign".localized) {
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
        .navigationBarBackButtonHidden(true)
        .onChange(of: viewModel.keysignFinished) { _, finished in
            guard finished else { return }

            guard
                  let hash = viewModel.hash,
                  let chain = input.keysignPayload?.coin.chain
            else { return }

            router.navigate(to: SendRoute.done(
                vault: input.vault,
                hash: hash,
                chain: chain,
                tx: tx,
                keysignPayload: input.keysignPayload
            ))
        }
    }
}

class SendKeysignViewModel: ObservableObject, TransferViewModel {
    @Published var keysignFinished: Bool = false

    var hash: String?
    var approveHash: String?

    func moveToNextView() {
        keysignFinished = true
    }
}
