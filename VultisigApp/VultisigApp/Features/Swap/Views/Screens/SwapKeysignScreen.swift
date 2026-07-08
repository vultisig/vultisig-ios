//
//  SwapKeysignScreen.swift
//  VultisigApp
//

import SwiftUI

struct SwapKeysignScreen: View {
    @Environment(\.router) var router

    let input: KeysignInput
    let transaction: SwapTransaction
    let retrySignal: SwapRetrySignal
    @State var viewModel: SwapKeysignViewModel

    init(input: KeysignInput, transaction: SwapTransaction, retrySignal: SwapRetrySignal) {
        self.input = input
        self.transaction = transaction
        self.retrySignal = retrySignal
        self._viewModel = State(initialValue: SwapKeysignViewModel(retrySignal: retrySignal))
    }

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
            guard let hash = viewModel.hash else { return }

            let chain = transaction.fromCoin.chain
            router.navigate(to: SigningRoute.done(.swap(
                vaultPubKeyECDSA: input.vault.pubKeyECDSA,
                hash: hash,
                approveHash: viewModel.approveHash,
                chain: chain,
                transaction: transaction,
                progressLink: transaction.progressLink(hash: hash)
            )))
        }
        .onChange(of: retrySignal.pendingRetryReason) { _, reason in
            guard reason != nil else { return }
            // Pop back to the verify screen — robust to deep-links that add routes before .root.
            router.navigateBack { destination in
                guard let route = destination as? SwapRoute else { return false }
                if case .verify = route { return true }
                return false
            }
        }
        .onDisappear {
            viewModel.stopMediator()
        }
    }
}
