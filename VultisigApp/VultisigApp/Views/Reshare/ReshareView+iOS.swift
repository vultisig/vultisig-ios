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
        .onChange(of: shouldJoinKeygen) { _, shouldNavigate in
            guard shouldNavigate else { return }
            router.navigate(to: OnboardingRoute.joinKeygen(
                vault: vault,
                selectedVault: nil
            ))
            shouldJoinKeygen = false
        }
        .crossPlatformSheet(isPresented: $showJoinReshare) {
            GeneralCodeScannerView(
                showSheet: $showJoinReshare,
                selectedChain: .constant(nil),
                sendTX: SendTransaction(),
                onJoinKeygen: {
                    shouldJoinKeygen = true
                }
            )
        }
    }

    var joinReshareButton: some View {
        PrimaryButton(title: "joinReshare", type: .secondary) {
            showJoinReshare = true
        }
        .padding(.bottom, 16)
    }
}
#endif
