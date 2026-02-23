//
//  OnboardingOverviewScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 11/12/2025.
//

import SwiftUI
import RiveRuntime

struct OnboardingOverviewScreen: View {
    let tssType: TssType
    let vault: Vault
    let email: String?
    let keyImportInput: KeyImportInput?
    let setupType: KeyImportSetupType

    @State private var animationVM: RiveViewModel? = nil
    @State private var isVerificationLinkActive = false
    @Environment(\.router) var router

    var animationFileName: String {
        switch setupType {
        case .fast:
            return "backup_device1"
        case .secure(let count):
            return "backup_device\(count)"
        }
    }

    var body: some View {
        Screen {
            VStack(alignment: .leading, spacing: 0) {
                Spacer()
                animation
                Spacer()
                VStack(spacing: 32) {
                    informationView
                    PrimaryButton(title: "iUnderstand") {
                        router.navigate(to: KeygenRoute.backupNow(
                            tssType: tssType,
                            backupType: .single(vault: vault),
                            isNewVault: true
                        ))
                    }
                }
            }
        }
        .screenBackButtonHidden()
        .onLoad(perform: onLoad)
        .crossPlatformSheet(isPresented: $isVerificationLinkActive) {
            ServerBackupVerificationScreen(
                tssType: tssType,
                vault: vault,
                email: email ?? .empty,
                isPresented: $isVerificationLinkActive,
                tabIndex: .constant(0),
                onBackup: { },
                onBackToEmailSetup: {
                    router.navigate(to: OnboardingRoute.vaultSetup(
                        tssType: tssType,
                        keyImportInput: keyImportInput
                    ))
                }
            )
        }
        .navigationBarBackButtonHidden(true)
    }

    var animation: some View {
        animationVM?.view()
            .frame(maxWidth: 350, maxHeight: 240)
            .offset(x: -48)
    }

    var informationView: some View {
        VStack(alignment: .leading, spacing: 32) {
            VStack(alignment: .leading, spacing: 16) {
                CustomHighlightText(
                    "backupsTitle".localized,
                    highlight: "backupsTitleHighlight".localized,
                    style: LinearGradient.primaryGradientHorizontal
                )
                .foregroundStyle(Theme.colors.textPrimary)
                .font(Theme.fonts.title2)

                Text("backupsDescription".localized)
                    .foregroundStyle(Theme.colors.textTertiary)
                    .font(Theme.fonts.footnote)
                    .frame(maxWidth: 329)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            OnboardingInformationRowView(
                title: "backupEachDevice".localized,
                subtitle: "backupEachDeviceDescription".localized,
                icon: "cloud-upload-filled"
            )

            OnboardingInformationRowView(
                title: "storeBackupsSeparately".localized,
                subtitle: "storeBackupsSeparatelyDescription".localized,
                icon: "arrow-split"
            )
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func onLoad() {
        animationVM = RiveViewModel(fileName: animationFileName)
        animationVM?.fit = .fitHeight

        if email != nil {
            isVerificationLinkActive = true
        }
    }
}

#Preview {
    OnboardingOverviewScreen(
        tssType: .Keygen,
        vault: .example,
        email: nil,
        keyImportInput: nil,
        setupType: .secure(numberOfDevices: 1)
    )
    .frame(width: 1500)
    .frame(maxHeight: isMacOS ? 800 : nil)
}
