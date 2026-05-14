//
//  LimitSwapKeysignScreen.swift
//  VultisigApp
//
//  Limit-swap counterpart of `SwapKeysignScreen`. Hosts the standard
//  `KeysignView` (same as Market). On broadcast success, routes to
//  `.limitDone(...)` carrying the inbound tx hash so `LimitSwapDoneScreen`
//  can persist the order via `LimitOrderStorageService`.
//
//  Limit orders don't have a market quote → no `SwapRetrySignal` /
//  re-quote path: a failure here drops the user back via the standard
//  navigation pop rather than the market path's pop-back-to-verify.
//

import SwiftUI

struct LimitSwapKeysignScreen: View {
    @Environment(\.router) var router

    let input: KeysignInput
    let pendingRecord: LimitOrderRecord
    @State var viewModel: SwapKeysignViewModel

    init(input: KeysignInput, pendingRecord: LimitOrderRecord) {
        self.input = input
        self.pendingRecord = pendingRecord
        self._viewModel = State(initialValue: SwapKeysignViewModel(retrySignal: SwapRetrySignal()))
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
            let chain = input.keysignPayload?.coin.chain ?? .thorChain
            router.navigate(to: SwapRoute.limitDone(
                vaultPubKeyECDSA: input.vault.pubKeyECDSA,
                hash: hash,
                chain: chain,
                pendingRecord: pendingRecord
            ))
        }
        .onDisappear {
            viewModel.stopMediator()
        }
    }
}
