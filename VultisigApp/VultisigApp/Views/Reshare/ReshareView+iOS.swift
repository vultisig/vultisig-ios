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
        .sheet(isPresented: $showJoinReshare, content: {
            GeneralCodeScannerView(
                showSheet: $showJoinReshare,
                shouldJoinKeygen: $shouldJoinKeygen,
                shouldKeysignTransaction: .constant(false), // CodeScanner used for keygen only
                shouldSendCrypto: .constant(false),         // -
                selectedChain: .constant(nil),              // -
                sendTX: SendTransaction()                   // -
            )
        })
    }

    var joinReshareButton: some View {
        Button {
            showJoinReshare = true
        } label: {
            OutlineButton(title: "joinReshare")
        }
        .navigationDestination(isPresented: $shouldJoinKeygen) {
            JoinKeygenView(vault: vault)
        }
        .padding(.bottom, 16)
    }
}
#endif
