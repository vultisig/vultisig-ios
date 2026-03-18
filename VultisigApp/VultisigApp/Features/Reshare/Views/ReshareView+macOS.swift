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
        .crossPlatformToolbar("reshare".localized)
    }

    var main: some View {
        view
            .padding(.bottom, 30)
            .padding(.horizontal, 40)
    }

    var joinReshareButton: some View {
        PrimaryButton(title: "joinReshare", type: .secondary) {
            router.navigate(to: KeygenRoute.macScanner(
                type: .NewVault,
                sendTx: SendTransaction(),
                selectedVault: nil
            ))
        }
    }
}
#endif
