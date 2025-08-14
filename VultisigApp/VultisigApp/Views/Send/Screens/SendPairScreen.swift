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
    @State var keysignInput: KeysignInput?
    
    var body: some View {
        Screen(title: "pair".localized) {
            KeysignDiscoveryView(
                vault: vault,
                keysignPayload: keysignPayload,
                customMessagePayload: nil,
                fastVaultPassword: fastVaultPassword,
                shareSheetViewModel: shareSheetViewModel,
                previewType: .Send
            ) { input in
                self.keysignInput = input
            }
        }
        .navigationBarBackButtonHidden(true)
        .navigationDestination(item: $keysignInput) { input in
            SendRouteBuilder().buildKeysignScreen(input: input, tx: tx)
        }
        .toolbar {
            ToolbarItem(placement: Placement.topBarTrailing.getPlacement()) {
                NavigationQRShareButton(
                    vault: vault,
                    type: .Keysign,
                    viewModel: shareSheetViewModel
                )
            }
        }
    }
}
