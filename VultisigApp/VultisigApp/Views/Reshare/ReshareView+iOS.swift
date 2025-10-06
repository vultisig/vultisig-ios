//
//  ReshareView.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 27.09.2024.
//

import SwiftUI

#if os(iOS)
extension ReshareView {
    var content: some View {
        ZStack {
            Background()
            view

            if viewModel.isLoading {
                Loader()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Image("LogoWithTitle")
                    .resizable()
                    .frame(width: 140, height: 32)
            }
            
            ToolbarItem(placement: Placement.topBarTrailing.getPlacement()) {
                NavigationHelpButton()
            }
        }
        .crossPlatformSheet(isPresented: $showJoinReshare) {
            GeneralCodeScannerView(
                showSheet: $showJoinReshare,
                shouldJoinKeygen: $shouldJoinKeygen,
                shouldKeysignTransaction: .constant(false), // CodeScanner used for keygen only
                shouldSendCrypto: .constant(false),         // -
                selectedChain: .constant(nil),              // -
                sendTX: SendTransaction()                   // -
            )
        }
    }

    var joinReshareButton: some View {
        PrimaryButton(title: "joinReshare", type: .secondary) {
            showJoinReshare = true
        }
        .navigationDestination(isPresented: $shouldJoinKeygen) {
            JoinKeygenView(vault: vault, selectedVault: nil)
        }
        .padding(.bottom, 16)
    }
}
#endif
