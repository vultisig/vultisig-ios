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
        view
            .padding(.bottom, 30)
            .padding(.horizontal, 40)
            .crossPlatformToolbar("reshare".localized)
    }

    var joinReshareButton: some View {
        PrimaryNavigationButton(title: "joinReshare", type: .secondary) {
            MacScannerView(type: .NewVault, sendTx: SendTransaction(), selectedVault: nil)
        }
    }
}
#endif
