//
//  SendPairScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 13/08/2025.
//

import SwiftUI

struct SendPairScreen: View {
    @Environment(\.router) var router
    @StateObject var shareSheetViewModel = ShareSheetViewModel()

    let vault: Vault
    let tx: SendTransaction
    let keysignPayload: KeysignPayload
    let fastVaultPassword: String?

    var body: some View {
        Screen(showNavigationBar: false) {
            KeysignDiscoveryView(
                vault: vault,
                keysignPayload: keysignPayload,
                customMessagePayload: nil,
                fastVaultPassword: fastVaultPassword,
                shareSheetViewModel: shareSheetViewModel,
                previewType: .Send,
                contentPadding: 0
            ) { input in
                router.navigate(to: SendRoute.keysign(input: input, tx: tx))
            }
        }
        .crossPlatformToolbar("pair".localized) {
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
