//
//  KeyImportNewVaultSetupScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 11/12/2025.
//

import SwiftUI

struct KeyImportNewVaultSetupScreen: View {
    let vault: Vault
    let keyImportInput: KeyImportInput?
    let fastSignConfig: FastSignConfig

    @State private var presentPeersScreen: Bool = false
    @Environment(\.router) var router
    
    var body: some View {
        Screen(edgeInsets: .init(leading: 0, trailing: 0)) {
            VStack(spacing: 0) {
                Spacer()
                Image("seed-phrase-vault-setup")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                Spacer()
                VStack(spacing: 0) {
                    informationView
                    Spacer().frame(maxHeight: 64)
                    PrimaryButton(title: "setup") {
                        presentPeersScreen = true
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .onChange(of: presentPeersScreen) { _, isActive in
            guard isActive else { return }
            router.navigate(to: KeygenRoute.peerDiscovery(
                tssType: .KeyImport,
                vault: vault,
                selectedTab: .secure,
                fastSignConfig: fastSignConfig,
                keyImportInput: keyImportInput
            ))
        }
    }
    
    var informationView: some View {
        VStack(alignment: .leading, spacing: 24) {
            CustomHighlightText(
                "yourNewVaultSetup".localized,
                highlight: "yourNewVaultSetupHighlight".localized,
                style: LinearGradient.primaryGradientHorizontal
            )
            .foregroundStyle(Theme.colors.textPrimary)
            .font(Theme.fonts.title2)
            
            OnboardingInformationRowView(
                title: "twoDevicesPlusServer".localized,
                subtitle: "twoDevicesPlusServerSubtitle".localized,
                icon: "devices"
            )
            
            OnboardingInformationRowView(
                title: "whySecureServer".localized,
                subtitle: "whySecureServerSubtitle".localized,
                icon: "secure"
            )
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

#Preview {
    KeyImportNewVaultSetupScreen(
        vault: .example,
        keyImportInput: .init(
            mnemonic: "",
            chains: []
        ),
        fastSignConfig: .init(
            email: "",
            password: "",
            hint: nil,
            isExist: false
        )
    )
}
