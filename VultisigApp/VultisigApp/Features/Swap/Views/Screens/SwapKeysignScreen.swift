//
//  SwapKeysignScreen.swift
//  VultisigApp
//

import SwiftUI

struct SwapKeysignScreen: View {
    @Environment(\.router) var router

    let input: KeysignInput
    @ObservedObject var tx: SwapTransaction
    @StateObject var viewModel = SwapKeysignViewModel()

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

            let chain = tx.fromCoin.chain
            router.navigate(to: SwapRoute.done(
                vaultPubKeyECDSA: input.vault.pubKeyECDSA,
                hash: hash,
                approveHash: viewModel.approveHash,
                chain: chain,
                tx: tx,
                progressLink: SwapCryptoLogic.progressLink(tx: tx, hash: hash)
            ))
        }
        .onChange(of: viewModel.pendingRetryReason) { _, reason in
            guard let reason else { return }
            tx.pendingRetryReason = reason
            viewModel.pendingRetryReason = nil
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
