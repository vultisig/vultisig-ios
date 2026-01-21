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
                        router.navigate(to: KeygenRoute.peerDiscovery(
                            tssType: .KeyImport,
                            vault: vault,
                            selectedTab: .secure,
                            fastSignConfig: fastSignConfig,
                            keyImportInput: keyImportInput
                        ))
                    }
                }
                .padding(.horizontal, 16)
            }
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

            appStoreReadyView
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    var appStoreReadyView: some View {
        HStack(alignment: .top, spacing: 12) {
            Icon(named: "shield-check", color: Theme.colors.alertInfo, size: 20)

            VStack(alignment: .leading, spacing: 8) {
                Text("appStoreReady".localized)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .font(Theme.fonts.subtitle)

                Text("appStoreReadyDescription".localized)
                    .foregroundStyle(Theme.colors.textSecondary)
                    .font(Theme.fonts.footnote)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .inset(by: 0.5)
                .fill(
                    LinearGradient(
                        stops: [
                            Gradient.Stop(color: Color(red: 0.04, green: 0.07, blue: 0.18), location: 0.00),
                            Gradient.Stop(color: Color(red: 0.22, green: 0.39, blue: 0.6).opacity(0), location: 1.00)
                        ],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
                .strokeBorder(Color(hex: "5CA7FF").opacity(0.3), style: .init(lineWidth: 1, dash: [4, 4]))
        )
        .background(Color(hex: "376499").opacity(0.3).clipShape(RoundedRectangle(cornerRadius: 12)))
    }

}

#Preview {
    KeyImportNewVaultSetupScreen(
        vault: .example,
        keyImportInput: .init(
            mnemonic: "",
            chainSettings: []
        ),
        fastSignConfig: .init(
            email: "",
            password: "",
            hint: nil,
            isExist: false
        )
    )
}
