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
    @State private var otpVerified = false
    @Environment(\.router) var router

    private var content: OnboardingOverviewContent {
        OnboardingOverviewContent(tssType: tssType, setupType: setupType)
    }

    private var isKeyImport: Bool {
        content.isKeyImport
    }

    private var descriptionText: String {
        content.descriptionKey.localized
    }

    private var row1Title: String {
        content.backupRowTitleKey.localized
    }

    private var row1Subtitle: String {
        switch content.backupRowSubtitle {
        case .plain(let key):
            return key.localized
        case .secureCount(let key, let count):
            return String(format: key.localized, count)
        }
    }

    private var row2Subtitle: String {
        content.storeSeparatelyRowSubtitleKey.localized
    }

    private var descriptionHighlightedText: String? {
        content.descriptionHighlightKey?.localized
    }

    private var row1HighlightedText: String? {
        content.backupRowHighlightKey?.localized
    }

    private var buttonTitle: String {
        content.buttonTitleKey.localized
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
        Screen {
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
        .screenNavigationBarHidden()
        .onAppear(perform: onAppear)
        .crossPlatformSheet(isPresented: $isVerificationLinkActive, isDismissable: false) {
            ServerBackupVerificationScreen(
                tssType: tssType,
                vault: vault,
                email: email ?? .empty,
                isPresented: $isVerificationLinkActive,
                tabIndex: .constant(0),
                otpVerified: $otpVerified,
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
        .onNavigationStackChange { isVisible in
            if isVisible { onAppear() }
        }
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

                Group {
                    if let descriptionHighlightedText {
                        HighlightedText(
                            text: descriptionText,
                            highlightedText: descriptionHighlightedText,
                            textStyle: {
                                $0.font = Theme.fonts.footnote
                                $0.foregroundColor = Theme.colors.textTertiary
                            },
                            highlightedTextStyle: {
                                $0.foregroundColor = Theme.colors.textPrimary
                            }
                        )
                    } else {
                        Text(descriptionText)
                            .foregroundStyle(Theme.colors.textTertiary)
                            .font(Theme.fonts.footnote)
                    }
                }
                .frame(maxWidth: 329)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            OnboardingInformationRowView(
                title: row1Title,
                subtitle: row1Subtitle,
                icon: .cloudUploadFilled,
                highlightedText: row1HighlightedText
            )

            OnboardingInformationRowView(
                title: "storeBackupsSeparately".localized,
                subtitle: row2Subtitle,
                icon: .arrowSplit
            )

            if content.showsOldBackupsRow {
                OnboardingInformationRowView(
                    title: "oldBackupsWontWork".localized,
                    subtitle: "oldBackupsWontWorkDescription".localized,
                    icon: .pageCrossText
                )
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func onAppear() {
        animationVM = RiveViewModel(fileName: animationFileName)
        animationVM?.fit = .fitHeight

        if email != nil, !otpVerified {
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
        setupType: .fast
    )
    .frame(width: isMacOS ? 1500 : nil)
    .frame(maxHeight: isMacOS ? 800 : nil)
}
