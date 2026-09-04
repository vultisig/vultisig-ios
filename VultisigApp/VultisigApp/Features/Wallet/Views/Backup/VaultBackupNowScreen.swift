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
    @State var fileModel: FileExporterModel<EncryptedDataFile>?
    @State var presentFileExporter = false
    @State private var checkboxChecked = false
    @Environment(\.router) var router

    private var vault: Vault { backupType.vault }

    private var titleText: String {
        if vault.isFastVault {
            return "backupSetupTitle".localized
        }
        let position = (vault.signers.firstIndex(of: vault.localPartyID) ?? 0) + 1
        return String(
            format: "backupSetupTitleSecure".localized,
            position,
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
            isNewVault: isNewVault,
            origin: .standard
        ) {
            Screen {
                VStack(spacing: 32) {
                    VaultBackupContent(title: titleText) {
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

    private var subtitleView: some View {
        VStack(spacing: 0) {
            if vault.isFastVault {
                HighlightedText(
                    text: "backupSetupSubtitleFast".localized,
                    highlightedText: "backupSetupSubtitleFastHighlight".localized,
                    textStyle: { attributedString in
                        attributedString.font = Theme.fonts.bodySMedium
                        attributedString.foregroundColor = Theme.colors.textTertiary
                    },
                    highlightedTextStyle: { substring in
                        substring.foregroundColor = Theme.colors.textPrimary
                    }
                )
            } else {
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
            }

            Text("backupSetupSubtitleHighlight".localized)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textPrimary)
                .showIf(vault.isFastVault)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: 321)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Checkbox

    private var checkboxView: some View {
        Checkbox(
            isChecked: $checkboxChecked,
            text: "backupSaveCheckbox".localized,
            isExtended: false
        )
    }

    // MARK: - Actions

    func onLoad() {
        FileManager.default.clearTmpDirectory()

        Task { @MainActor in
            if vault.isFastVault, isNewVault {
                let fileModel = await backupViewModel.exportFileWithVaultPassword(backupType)
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

/// Shared backup education content used by the standard backup flow and the
/// App Lock preflight. Keeping the animation, step icon, spacing and typography
/// here prevents the two backup entry points from drifting apart.
struct VaultBackupContent<Subtitle: View>: View {
    let title: String
    @ViewBuilder let subtitle: () -> Subtitle

    @State private var animation: RiveViewModel?

    var body: some View {
        VStack(spacing: 32) {
            animation?.view()

            VaultSetupStepIcon(
                state: .active,
                icon: .cloudUpload
            )

            VStack(spacing: 16) {
                Text(title)
                    .font(Theme.fonts.title2)
                    .foregroundStyle(Theme.colors.textPrimary)

                subtitle()
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: 321)
            .fixedSize(horizontal: false, vertical: true)
        }
        .onLoad {
            animation = RiveViewModel(fileName: "backupvault_splash", autoPlay: true)
        }
    }
}

#Preview {
    VaultBackupScreen(tssType: .Keygen, backupType: .single(vault: .example))
}
