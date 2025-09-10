//
//  VaultSettingsScreen.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-12.
//

import SwiftUI
import SwiftData

struct VaultSettingsScreen: View {
    let vault: Vault
    
    @Query var vaults: [Vault]
    @Query var folders: [Folder]
    
    @Environment(\.dismiss) var dismiss
    
    @State var devicesInfo: [DeviceInfo] = []
    @State var showUpgradeYourVaultSheet = false
    @State var upgradeYourVaultLinkActive = false
    @State var presentBackupSheet = false
    @State var presentSingleDeviceBackup = false
    @State var presentMultipleDeviceBackup = false
    @State var presentServerBackup = false
    @State var presentFastSigningBiometricsSheet = false
    
    @State var isFastSigningBiometricsEnabled: Bool = false
    @StateObject var viewModel = SettingsBiometryViewModel()
    
    init(vault: Vault) {
        self.vault = vault
    }
    
    var body: some View {
        Screen(title: "vaultSettings".localized) {
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 14) {
                    SettingsSectionView(title: "vaultManagement".localized) {
                        vaultDetails
                        editVault
                        fastSigningBiometrics
                            .showIf(vault.isFastVault)
                    }
                    
                    SettingsSectionView(title: "security".localized) {
                        passwordHint
                            .showIf(vault.isFastVault)
                        backupVault
                    }
                    
                    SettingsSectionView(title: "other".localized) {
                        VStack(spacing: .zero) {
                            if vault.libType == nil || vault.libType == .GG20 {
                                migrateVault
                            }
                            advancedSettings
                        }
                    }
                    
                    SettingsSectionContainerView {
                        VStack(spacing: .zero) {
                            deleteVault
                        }
                    }
                }
            }
        }
        .onLoad(perform: onLoad)
        .navigationDestination(isPresented: $upgradeYourVaultLinkActive) {
            if vault.isFastVault {
                VaultShareBackupsView(vault: vault)
            } else {
                AllDevicesUpgradeView(vault: vault)
            }
        }
        .sheet(isPresented: $showUpgradeYourVaultSheet) {
            UpgradeYourVaultView(
                showSheet: $showUpgradeYourVaultSheet,
                navigationLinkActive: $upgradeYourVaultLinkActive
            )
        }
        .bottomSheet(isPresented: $presentBackupSheet) {
            ChooseBackupSheetView(vault: vault) {
                presentBackupSheet = false
                onDeviceBackup()
            } onServerBackup: {
                presentBackupSheet = false
                presentServerBackup = true
            }
        }
        .navigationDestination(isPresented: $presentServerBackup) {
            VaultServerBackupScreen(vault: vault)
        }
        .navigationDestination(isPresented: $presentSingleDeviceBackup) {
            VaultBackupPasswordOptionsScreen(tssType: .Keygen, backupType: .single(vault: vault))
        }
        .navigationDestination(isPresented: $presentMultipleDeviceBackup) {
            VaultBackupSelectionScreen(selectedVault: vault)
        }
        .onChange(of: presentFastSigningBiometricsSheet) { _, isPresented in
            if !isPresented {
                isFastSigningBiometricsEnabled = viewModel.isBiometryEnabled
            }
        }
        .bottomSheet(isPresented: $presentFastSigningBiometricsSheet) {
            FastSigningPasswordSheetView(viewModel: viewModel, vault: vault)
        }
    }
    
    var fastSigningBiometrics: some View {
        SettingsOptionView(
            icon: "lightning",
            title: "biometricsFastSigning".localized,
            showSeparator: false
        ) {
            Toggle("", isOn: Binding(
                get: { viewModel.isBiometryEnabled },
                set: { onBiometryEnabledChanged($0) }
            ))
            .labelsHidden()
            .scaleEffect(0.8)
            .tint(Theme.colors.primaryAccent4)
            .toggleStyle(.switch)
        }
    }
    
    var passwordHint: some View {
        NavigationLink {
            SettingsPasswordHintScreen(vault: vault, viewModel: viewModel)
        } label: {
            SettingsCommonOptionView(icon: "message-square-lock", title: "passwordHint".localized, subtitle: "setOrUpdateHint".localized)
        }
    }
    
    var vaultDetails: some View {
        NavigationLink {
            VaultPairDetailView(vault: vault, devicesInfo: devicesInfo)
        } label: {
            SettingsCommonOptionView(icon: "circle-info", title: "vaultDetailsTitle".localized, subtitle: "vaultDetailsDescription".localized)
        }
    }
    
    var backupVault: some View {
        Button {
            if vault.isFastVault {
                presentBackupSheet = true
            } else {
                onDeviceBackup()
            }
        } label: {
            SettingsCommonOptionView(
                icon: "hard-drive-upload",
                title: "backupVaultShareTitle".localized,
                subtitle: "backupVaultShareDescription".localized,
                showSeparator: false
            )
        }
    }
    
    var editVault: some View {
        NavigationLink {
            RenameVaultView(vaults: vaults, folders: folders, vault: vault)
        } label: {
            SettingsCommonOptionView(
                icon: "pencil",
                title: "rename".localized,
                subtitle: "renameVault".localized,
                showSeparator: vault.isFastVault
            )
        }
    }
    
    var deleteVault: some View {
        NavigationLink {
            VaultDeletionConfirmView(vault: vault, devicesInfo: devicesInfo)
        } label: {
            SettingsCommonOptionView(
                icon: "trash",
                title: "delete".localized,
                subtitle: "deleteVault".localized,
                type: .alert,
                showSeparator: false
            )
        }
        
    }

    var migrateVault: some View {
        Button {
            showUpgradeYourVaultSheet = true
        } label: {
            SettingsCommonOptionView(
                icon: "arrow-up-from-dot",
                title: "migrate".localized,
                subtitle: "migrateVault".localized
            )
        }
    }
    
    var advancedSettings: some View {
        NavigationLink {
            VaultAdvancedSettingsScreen(vault: vault)
        } label: {
            SettingsCommonOptionView(
                icon: "folder-key",
                title: "advanced".localized,
                subtitle: "advancedDescription".localized,
                showSeparator: false
            )
        }
    }
    
    private func onLoad() {
        self.isFastSigningBiometricsEnabled = viewModel.isBiometryEnabled
        devicesInfo = vault.signers.enumerated().map { index, signer in
            DeviceInfo(Index: index, Signer: signer)
        }
    }
    
    func onDeviceBackup() {
        if vaults.count > 1 {
            presentMultipleDeviceBackup = true
        } else {
            presentSingleDeviceBackup = true
        }
    }
    
    func onBiometryEnabledChanged(_ isEnabled: Bool) {
        isFastSigningBiometricsEnabled = isEnabled
        
        guard isEnabled else {
            viewModel.onBiometryEnabledChanged(isEnabled, vault: vault)
            return
        }
        
        presentFastSigningBiometricsSheet = true
    }
}

#Preview {
    VaultSettingsScreen(vault: Vault.example)
}
