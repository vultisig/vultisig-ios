//
//  LimitSwapEntryView.swift
//  VultisigApp
//

import SwiftUI

/// Wrapper that owns the `LimitSwapFormViewModel` lifecycle and renders the
/// body. Lives at this layer so `SwapCryptoView` doesn't need to manage VM
/// construction itself. The VM is built once on first appearance from the
/// supplied initial coins; subsequent renders reuse it.
struct LimitSwapEntryView: View {

    let initialFromCoin: Coin
    let initialToCoin: Coin
    let vault: Vault

    @State private var vm: LimitSwapFormViewModel?

    var body: some View {
        Group {
            if let vm {
                LimitSwapBodyView(
                    vm: vm,
                    onPickAssetPair: handlePickAssetPair,
                    onPlaceOrder: handlePlaceOrder
                )
            } else {
                Color.clear
            }
        }
        .onAppear {
            if vm == nil {
                vm = makeViewModel()
            }
        }
    }

    private func makeViewModel() -> LimitSwapFormViewModel {
        let draft = LimitSwapDraft(
            fromAsset: LimitSwapAsset(coin: initialFromCoin),
            toAsset: LimitSwapAsset(coin: initialToCoin)
        )
        let interactor = DefaultLimitSwapInteractor(
            quoteService: ThorchainService.shared,
            storage: LimitOrderStorageService()
        )
        return LimitSwapFormViewModel(
            initialDraft: draft,
            vault: vault,
            interactor: interactor
        )
    }

    private func handlePickAssetPair() {
        // TODO(§7 follow-up): wire to the existing market-swap asset picker
        // sheet. Tracked in design-flags.md item #2 (coin logos depend on
        // this integration).
    }

    private func handlePlaceOrder() {
        // TODO(§8): present the confirmation sheet, run Blockaid scan, gate
        // Sign on the "swap amount is correct" checkbox, assemble
        // KeysignPayload with the limit memo, run the byte-cap pre-flight,
        // and persist the LimitOrder on broadcast success.
    }
}
