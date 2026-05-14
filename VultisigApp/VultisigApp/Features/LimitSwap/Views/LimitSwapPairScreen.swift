//
//  LimitSwapPairScreen.swift
//  VultisigApp
//
//  Limit-swap counterpart of `SwapPairScreen`. Hosts the standard
//  `KeysignDiscoveryView` (same as Market) but uses `.Send` preview
//  type — limit orders are memo'd deposits, not routed swaps, so there
//  is no quote/from-amount/to-amount preview to render. On keysign
//  input ready, routes into `.limitKeysign` carrying the pending order
//  record so the post-broadcast persist step in `LimitSwapDoneScreen`
//  can store the order with the on-chain hash.
//

import SwiftUI

struct LimitSwapPairScreen: View {
    @Environment(\.router) var router
    @StateObject var shareSheetViewModel = ShareSheetViewModel()

    let vault: Vault
    let keysignPayload: KeysignPayload
    let pendingRecord: LimitOrderRecord

    var body: some View {
        Screen {
            KeysignDiscoveryView(
                vault: vault,
                keysignPayload: keysignPayload,
                customMessagePayload: nil,
                fastVaultPassword: nil,
                shareSheetViewModel: shareSheetViewModel,
                previewType: .Send,
                swapTransaction: nil,
                contentPadding: 0
            ) { input in
                router.navigate(to: SwapRoute.limitKeysign(input: input, pendingRecord: pendingRecord))
            }
        }
        .screenTitle("pair".localized)
        .screenToolbar {
            CustomToolbarItem(placement: .trailing) {
                NavigationQRShareButton(
                    vault: vault,
                    type: .Keysign,
                    viewModel: shareSheetViewModel
                )
            }
        }
    }
}
