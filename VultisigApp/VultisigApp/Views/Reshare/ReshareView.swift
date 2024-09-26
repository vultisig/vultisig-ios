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
            Text("Reshare your vault")
                .font(.body24MontserratMedium)
                .foregroundColor(.neutral0)

            Text("Reshare can be used to refresh, expand or reduce the amount of devices in a Vault.")
                .font(.body14Montserrat)
                .foregroundColor(.neutral300)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 36)
    }

    var disclaimer: some View {
        OutlinedDisclaimer(text: "For all Reshare actions the threshold of devices is always required.", alignment: .center)
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
                    fastVaultPassword: nil
                )
            } label: {
                FilledButton(title: "Start Reshare")
            }

            NavigationLink {
                FastVaultEmailView(
                    tssType:  viewModel.isFastVault ? .Reshare : .Keygen,
                    vault: vault,
                    selectedTab: .secure
                )
            } label: {
                OutlineButton(title: "Start Reshare with Vultisigner")
            }

            Button {
                showJoinReshare = true
            } label: {
                OutlineButton(title: "Join Reshare")
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
            .navigationDestination(isPresented: $shouldJoinKeygen) {
                JoinKeygenView(vault: vault)
            }
        }
        .padding(.horizontal, 40)
    }
}
