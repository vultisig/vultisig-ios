//
//  ReshareView.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 27.09.2024.
//

import SwiftUI

#if os(macOS)
extension ReshareView {
    var content: some View {
        ZStack {
            Background()
            main

            if viewModel.isLoading {
                Loader()
            }
        }
    }

    var main: some View {
        VStack {
            headerMac
            view
                .padding(.bottom, 30)
                .padding(.horizontal, 40)
        }
    }

    var headerMac: some View {
        GeneralMacHeader(title: "reshare")
    }

    var joinReshareButton: some View {
        NavigationLink(destination: {
            MacScannerView(vault: vault, type: .NewVault, sendTx: SendTransaction())
        }) {
            OutlineButton(title: "joinReshare")
        }
    }
}
#endif
