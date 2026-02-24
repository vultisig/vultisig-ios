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

    private var isKeyImport: Bool {
        tssType == .KeyImport
    }

    private var descriptionText: String {
        isKeyImport ? "backupsDescription".localized : "backupsDescriptionVault".localized
    }

    private var row1Title: String {
        if !isKeyImport && setupType == .fast {
            return "backupDeviceDriver".localized
        }
        return "backupEachDevice".localized
    }

    private var row1Subtitle: String {
        if isKeyImport {
            return "backupEachDeviceDescription".localized
        }
        switch setupType {
        case .fast:
            return "backupDeviceDriverDescription".localized
        case .secure(let count):
            return String(format: "backupEachDeviceDescriptionSecure".localized, count)
        }
    }

    private var row2Subtitle: String {
        if !isKeyImport, case .secure = setupType {
            return "storeBackupsSeparatelyDescriptionSecure".localized
        }
        return "storeBackupsSeparatelyDescription".localized
    }

    private var buttonTitle: String {
        isKeyImport ? "continue".localized : "iUnderstand".localized
    }

    var animationFileName: String {
        switch setupType {
        case .fast:
            return "backup_device1"
        case .secure(let count):
            return "backup_device\(count)"
        }
    }

    var body: some View {
        Screen(showNavigationBar: false) {
            VStack(alignment: .leading, spacing: 0) {
                Spacer()
                animation
                Spacer()
                VStack(spacing: 32) {
                    informationView
                    PrimaryButton(title: buttonTitle) {
                        router.navigate(to: KeygenRoute.backupNow(
                            tssType: tssType,
                            backupType: .single(vault: vault),
                            isNewVault: true
                        ))
                    }
                }
            }
        }
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
        .crossPlatformToolbar(.empty, showsBackButton: false)
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

                Text(descriptionText)
                    .foregroundStyle(Theme.colors.textTertiary)
                    .font(Theme.fonts.footnote)
                    .frame(maxWidth: 329)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            OnboardingInformationRowView(
                title: row1Title,
                subtitle: row1Subtitle,
                icon: "cloud-upload-filled"
            )

            OnboardingInformationRowView(
                title: "storeBackupsSeparately".localized,
                subtitle: row2Subtitle,
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
        tssType: .KeyImport,
        vault: .example,
        email: nil,
        keyImportInput: .init(mnemonic: "", chainSettings: []),
        setupType: .secure(numberOfDevices: 3)
    )
    .frame(width: isMacOS ? 1500 : nil)
    .frame(maxHeight: isMacOS ? 800 : nil)
}
