//
//  ReshareView.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 26.09.2024.
//

import SwiftUI

struct ReshareView: View {

    let vault: Vault

    @State var showJoinReshare = false
    @State var shouldJoinKeygen = false
    @State var showFastShareExists = false
    @State var showFastShareNew = false

    @StateObject var viewModel = ReshareViewModel()

    var body: some View {
        content
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Image("LogoWithTitle")
                        .resizable()
                        .frame(width: 140, height: 32)
                }
            }
            .task {
                await viewModel.load(vault: vault)
            }
    }

    var view: some View {
        VStack(spacing: 16) {
            Spacer()
            Spacer()
            title
            Spacer()
            disclaimer
            buttons
        }
    }

    var title: some View {
        VStack(spacing: 16) {
            Text(NSLocalizedString("reshareLabelTitle", comment: ""))
                .font(.body24MontserratMedium)
                .foregroundColor(.neutral0)

            Text(NSLocalizedString("reshareLabelSubtitle", comment: ""))
                .font(.body14Montserrat)
                .foregroundColor(.neutral300)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 36)
    }

    var disclaimer: some View {
        OutlinedDisclaimer(text: NSLocalizedString("reshareLabelDisclaimer", comment: ""), alignment: .center)
            .padding(.horizontal, 16)
    }

    var buttons: some View {
        VStack(spacing: 12) {
            NavigationLink {
                PeerDiscoveryView(
                    tssType: .Reshare,
                    vault: vault,
                    selectedTab: .secure,
                    fastVaultEmail: nil,
                    fastVaultPassword: nil, 
                    fastVaultExist: false
                )
            } label: {
                FilledButton(title: "startReshare")
            }

            NavigationLink {
                FastVaultEmailView(
                    tssType: .Reshare,
                    vault: vault,
                    selectedTab: .secure,
                    fastVaultExist: viewModel.isFastVault
                )
            } label: {
                OutlineButton(title: "startFastVaultReshare")
            }

            joinReshareButton
        }
        .padding(.horizontal, 40)
    }
}
