//
//  VaultBackupPasswordOptionsScreen.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-03-21.
//

import SwiftUI

struct VaultBackupPasswordOptionsScreen: View {
    let tssType: TssType
    let backupType: VaultBackupType
    var isNewVault = false
    var origin: VaultBackupOrigin = .standard

    @State var isLoading = false
    @State var presentFileExporter = false
    @StateObject var backupViewModel = EncryptedBackupViewModel()
    @State var fileModel: FileExporterModel<EncryptedDataFile>?
    @Environment(\.router) var router

    var body: some View {
        VaultBackupContainerView(
            presentFileExporter: $presentFileExporter,
            fileModel: $fileModel,
            backupViewModel: backupViewModel,
            tssType: tssType,
            backupType: backupType,
            isNewVault: isNewVault,
            origin: origin
        ) {
            Screen {
                if origin.usesSettingsLook {
                    settingsContent
                } else {
                    standardContent
                }
            }
        }
        .onAppear(perform: onAppear)
        .onDisappear(perform: backupViewModel.resetData)
    }

    var standardContent: some View {
        VStack(spacing: 36) {
            icon
            textContent
            Spacer()
            buttons
        }
    }

    /// The buttons follow the boxes in one scroll, so on a short screen all three
    /// warnings pass before either button can be reached.
    var settingsContent: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 36) {
                    settingsIcon
                    settingsTextContent
                    Spacer(minLength: 0)
                    buttons
                }
                .frame(minHeight: proxy.size.height)
            }
            .scrollIndicatorsFlash(onAppear: true)
        }
    }

    var icon: some View {
        Image(systemName: "person.badge.key")
            .font(Theme.fonts.title1)
            .foregroundStyle(Theme.colors.textPrimary)
            .frame(width: 64, height: 64)
            .background(Theme.colors.bgSurface2)
            .cornerRadius(Theme.radius.lg)
    }

    var settingsIcon: some View {
        Icon(.lockPassword, color: Theme.colors.textPrimary, size: 32)
            .padding(16)
            .background(Theme.colors.bgSurface2)
            .clipShape(Theme.radius.lg.shape)
    }

    var textContent: some View {
        VStack(spacing: 16) {
            Text("backupOptionsTitle".localized)
                .font(Theme.fonts.title2)
                .foregroundStyle(Theme.colors.textPrimary)
                .multilineTextAlignment(.center)

            boxedText("backupOptionsBox1".localized, highlighted: "backupOptionsBox1Highlighted".localized, icon: .lockFilled)

            boxedText("backupOptionsBox2".localized, highlighted: "backupOptionsBox2Highlighted".localized, icon: .folderLock)

            boxedText("backupOptionsBox3".localized, highlighted: "backupOptionsBox3Highlighted".localized, icon: .fileAlert)
        }
    }

    var settingsTextContent: some View {
        VStack(spacing: 16) {
            Text("backupOptionsTitle".localized)
                .settingsText(.title2)
                .foregroundStyle(Theme.colors.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            settingsBoxedText("backupOptionsBox1".localized, highlighted: "backupOptionsBox1Highlighted".localized, icon: .lockFilled)

            settingsBoxedText("backupOptionsSettingsBox2".localized, highlighted: "backupOptionsSettingsBox2Highlighted".localized, icon: .folders)

            settingsBoxedText("backupOptionsSettingsBox3".localized, highlighted: "backupOptionsSettingsBox3Highlighted".localized, icon: .triangleWarningFilled)
        }
    }

    func boxedText(_ text: String, highlighted: String, icon: ImageResource) -> some View {
        HStack(spacing: 12) {
            Icon(icon, color: Theme.colors.primaryAccent4, size: 24)
            HighlightedText(text: String(format: text.localized, highlighted), highlightedText: highlighted) {
                $0.foregroundColor = Theme.colors.textTertiary
                $0.font = Theme.fonts.footnote
            } highlightedTextStyle: {
                $0.foregroundColor = Theme.colors.textPrimary
                $0.font = Theme.fonts.footnote
            }
        }
        .frame(maxWidth: 325)
        .containerStyle(padding: 16, bgColor: Theme.colors.bgSurface1)

    }

    func settingsBoxedText(_ text: String, highlighted: String, icon: ImageResource) -> some View {
        HStack(spacing: 12) {
            Icon(icon, color: Theme.colors.primaryAccent4, size: 24)
            HighlightedText(text: String(format: text.localized, highlighted), highlightedText: highlighted) {
                $0.foregroundColor = Theme.colors.textTertiary
                $0.font = Theme.fonts.footnote
            } highlightedTextStyle: {
                $0.foregroundColor = Theme.colors.textPrimary
                $0.font = Theme.fonts.footnote
            }
            .settingsText(.footnote)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .frame(maxWidth: 327)
        .background(Theme.colors.bgSurface1)
        .clipShape(Theme.radius.lg.shape)
        .overlay(Theme.radius.lg.shape.strokeBorder(Theme.colors.borderLight, lineWidth: 1))
    }

    var buttons: some View {
        VStack(spacing: 12) {
            withoutPasswordButton
            withPasswordButton
        }
        .disabled(isLoading)
    }

    var withoutPasswordButton: some View {
        PrimaryButton(title: "backupWithoutPassword", size: origin.usesSettingsLook ? .compact : .medium) {
            presentFileExporter = true
        }
    }

    var withPasswordButton: some View {
        PrimaryButton(
            title: origin.usesSettingsLook ? "backupWithPassword" : "usePassword",
            type: .secondary,
            size: origin.usesSettingsLook ? .compact : .medium
        ) {
            router.navigate(to: VaultRoute.backupPasswordScreen(
                tssType: tssType,
                backupType: backupType,
                isNewVault: isNewVault,
                origin: origin
            ))
        }
    }

    private func onAppear() {
        isLoading = true
        FileManager.default.clearTmpDirectory()
        backupViewModel.resetData()
        Task {
            let fileModel = await backupViewModel.exportFileWithoutPassword(backupType)
            await MainActor.run {
                isLoading = false
                self.fileModel = fileModel
            }
        }
    }
}

#Preview {
    VaultBackupPasswordOptionsScreen(tssType: .Keygen, backupType: .single(vault: Vault.example))
}
