//
//  VaultBackupScreen.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-06-13.
//

import SwiftUI
import RiveRuntime

struct VaultBackupScreen: View {
    let tssType: TssType
    let backupType: VaultBackupType
    var isNewVault = false

    @StateObject var backupViewModel = EncryptedBackupViewModel()
    @State var animation: RiveViewModel?
    @State var fileModel: FileExporterModel<EncryptedDataFile>?
    @State var presentFileExporter = false
    @State private var checkboxChecked = false
    @Environment(\.router) var router

    private var vault: Vault { backupType.vault }

    private var titleText: String {
        if vault.isFastVault {
            return "backupSetupTitle".localized
        }
        return String(
            format: "backupSetupTitleSecure".localized,
            1,
            vault.signers.count
        )
    }

    // MARK: - Body

    var body: some View {
        VaultBackupContainerView(
            presentFileExporter: $presentFileExporter,
            fileModel: $fileModel,
            backupViewModel: backupViewModel,
            tssType: tssType,
            backupType: backupType,
            isNewVault: isNewVault
        ) {
            Screen {
                VStack(spacing: 32) {
                    animation?.view()
                    VaultSetupStepIcon(
                        state: .active,
                        icon: "cloud-upload-filled"
                    )
                    VStack(spacing: 16) {
                        titleView
                        subtitleView
                    }

                    Spacer()

                    VStack(spacing: 24) {
                        checkboxView
                        PrimaryButton(title: "backupSaveButton".localized) {
                            onBackupNow()
                        }
                        .disabled(!checkboxChecked)
                    }
                }
            }
            .screenEdgeInsets(.init(leading: 24, trailing: 24))
        }
        .onLoad(perform: onLoad)
    }

    // MARK: - Title & Subtitle

    private var titleView: some View {
        Text(titleText)
            .font(Theme.fonts.title2)
            .foregroundStyle(Theme.colors.textPrimary)
            .multilineTextAlignment(.center)
    }

    private var subtitleView: some View {
        HighlightedText(
            text: "backupSetupSubtitle".localized,
            highlightedText: "backupSetupSubtitleHighlight".localized,
            textStyle: { attributedString in
                attributedString.font = Theme.fonts.bodySMedium
                attributedString.foregroundColor = Theme.colors.textTertiary
            },
            highlightedTextStyle: { substring in
                substring.foregroundColor = Theme.colors.textPrimary
            }
        )
        .multilineTextAlignment(.center)
        .frame(maxWidth: 321)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Checkbox

    private var checkboxView: some View {
        Checkbox(
            isChecked: $checkboxChecked,
            text: "backupSaveCheckbox".localized
        )
    }

    // MARK: - Actions

    func onLoad() {
        FileManager.default.clearTmpDirectory()
        animation = RiveViewModel(fileName: "backupvault_splash", autoPlay: true)

        Task { @MainActor in
            if vault.isFastVault, isNewVault {
                let fileModel = backupViewModel.exportFileWithVaultPassword(backupType)
                self.fileModel = fileModel
            }
        }
    }

    func onBackupNow() {
        guard checkboxChecked else { return }

        // Only export backup directly if it's fast vault during creation
        guard vault.isFastVault, isNewVault, fileModel != nil else {
            router.navigate(to: VaultRoute.backupPasswordOptions(
                tssType: tssType,
                backupType: backupType,
                isNewVault: isNewVault
            ))
            return
        }

        presentFileExporter = true
    }
}

#Preview {
    VaultBackupScreen(tssType: .Keygen, backupType: .single(vault: .example))
}
