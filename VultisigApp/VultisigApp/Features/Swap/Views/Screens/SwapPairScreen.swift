//
//  SwapPairScreen.swift
//  VultisigApp
//

import SwiftUI

struct SwapPairScreen: View {
    @Environment(\.router) var router
    @StateObject var shareSheetViewModel = ShareSheetViewModel()

    let vault: Vault
    let transaction: SwapTransaction
    let retrySignal: SwapRetrySignal
    let keysignPayload: KeysignPayload
    let fastVaultPassword: String?

    var body: some View {
        Screen {
            KeysignDiscoveryView(
                vault: vault,
                keysignPayload: keysignPayload,
                customMessagePayload: nil,
                fastVaultPassword: fastVaultPassword,
                shareSheetViewModel: shareSheetViewModel,
                previewType: .Swap,
                swapTransaction: transaction,
                contentPadding: 0
            ) { input in
                router.navigate(to: SwapRoute.keysign(input: input, transaction: transaction, retrySignal: retrySignal))
            }
        }
        .screenTitle("pair".localized)
        .if(fastVaultPassword != nil) {
            $0
                .screenNavigationBarHidden(true)
                .screenEdgeInsets(.zero)
        }
        .screenToolbar {
            CustomToolbarItem(placement: .trailing) {
                NavigationQRShareButton(
                    vault: vault,
                    type: .Keysign,
                    viewModel: shareSheetViewModel
                )
                .showIf(fastVaultPassword == nil)
            }
        }
    }
}
