//
//  ReshareView.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 26.09.2024.
//

import SwiftUI

struct ReshareView: View {
    @Environment(\.router) var router
    let vault: Vault

    @State var showJoinReshare = false
    @State var shouldJoinKeygen = false
    @State var showFastShareExists = false
    @State var showFastShareNew = false

    @StateObject var viewModel = ReshareViewModel()

    var body: some View {
        content
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
        .padding(.horizontal, 16)
    }

    var title: some View {
        VStack(spacing: 16) {
            Text(NSLocalizedString("reshareLabelTitle", comment: ""))
                .font(Theme.fonts.title2)
                .foregroundColor(Theme.colors.textPrimary)

            Text(NSLocalizedString("reshareLabelSubtitle", comment: ""))
                .font(Theme.fonts.bodySMedium)
                .foregroundColor(Theme.colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 36)
    }

    var disclaimer: some View {
        OutlinedDisclaimer(text: NSLocalizedString("reshareLabelDisclaimer", comment: ""), alignment: .center)
            .padding(.bottom, 8)
    }

    var buttons: some View {
        VStack(spacing: 12) {
            startReshareButton
            joinReshareButton
        }
    }

    var startReshareButton: some View {
        PrimaryButton(title: "startReshare") {
            router.navigate(to: KeygenRoute.peerDiscovery(
                tssType: .Reshare,
                vault: vault,
                selectedTab: .secure,
                fastSignConfig: nil,
                keyImportInput: nil
            ))
        }
    }

    var startReshareVultisignerButton: some View {
        PrimaryButton(title: "startFastVaultReshare", type: .secondary) {
            router.navigate(to: KeygenRoute.fastVaultEmail(
                tssType: .Reshare,
                vault: vault,
                selectedTab: .secure,
                fastVaultExist: viewModel.isFastVault
            ))
        }
    }
}

#Preview {
    ReshareView(vault: Vault.example)
}
