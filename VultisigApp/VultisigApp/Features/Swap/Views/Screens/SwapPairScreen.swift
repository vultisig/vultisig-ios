//
//  SwapPairScreen.swift
//  VultisigApp
//

import SwiftUI

struct SwapPairScreen: View {
    @Environment(\.router) var router
    @StateObject var shareSheetViewModel = ShareSheetViewModel()

    let vault: Vault
    @ObservedObject var tx: SwapTransaction
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
                swapTransaction: tx,
                contentPadding: 0
            ) { input in
                router.navigate(to: SwapRoute.keysign(input: input, tx: tx))
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
