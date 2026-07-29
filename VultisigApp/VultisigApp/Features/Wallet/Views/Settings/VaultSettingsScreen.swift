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

    @Environment(\.router) var router

    @State var devicesInfo: [DeviceInfo] = []
    @State var showUpgradeYourVaultSheet = false
    @State var presentBackupSheet = false
    @State var presentFastSigningBiometricsSheet = false

    @State var isFastSigningBiometricsEnabled: Bool = false
    @StateObject var viewModel = SettingsBiometryViewModel()

    init(vault: Vault) {
        self.vault = vault
    }

    var body: some View {
        Screen {
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 14) {
                    section(title: "vaultManagement".localized, rows: vaultManagementRows)
                    section(title: "security".localized, rows: securityRows)
                    section(title: "other".localized, rows: otherRows)

                    deleteVault
                        .commonListItemContainer(index: 0, itemsCount: 1)
                        .commonListContainer()
                }
            }
        }
        .screenTitle("vaultSettings".localized)
        .onLoad(perform: onLoad)
        .crossPlatformSheet(isPresented: $showUpgradeYourVaultSheet) {
            UpgradeYourVaultView(
                showSheet: $showUpgradeYourVaultSheet,
                onUpgrade: {
                    router.navigate(to: VaultRoute.upgradeVault(
                        vault: vault,
                        isFastVault: vault.isFastVault
                    ))
                }
            )
        }
        .bottomSheet(isPresented: $presentBackupSheet) {
            ChooseBackupSheetView(vault: vault) {
                presentBackupSheet = false
                onDeviceBackup()
            } onServerBackup: {
                presentBackupSheet = false
                router.navigate(to: VaultRoute.serverBackup(vault: vault))
            }
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

    /// The rows a section can hold. Sections compose them as an ordered array
    /// so each row knows its position, which is what drives the shared list
    /// container's separators and end-row corner rounding.
    enum Row {
        case vaultDetails
        case editVault
        case fastSigningBiometrics
        case passwordHint
        case backupVault
        case migrateVault
        case advancedSettings
    }

    var vaultManagementRows: [Row] {
        var rows: [Row] = [.vaultDetails, .editVault]
        if vault.isFastVault {
            rows.append(.fastSigningBiometrics)
        }
        return rows
    }

    var securityRows: [Row] {
        vault.isFastVault ? [.passwordHint, .backupVault] : [.backupVault]
    }

    var otherRows: [Row] {
        let canMigrate = vault.libType == nil || vault.libType == .GG20
        return canMigrate ? [.migrateVault, .advancedSettings] : [.advancedSettings]
    }

    func section(title: String, rows: [Row]) -> some View {
        SettingsSectionView(title: title) {
            ForEach(Array(rows.enumerated()), id: \.element) { index, row in
                view(for: row)
                    .commonListItemContainer(index: index, itemsCount: rows.count)
            }
        }
    }

    @ViewBuilder
    func view(for row: Row) -> some View {
        switch row {
        case .vaultDetails:
            vaultDetails
        case .editVault:
            editVault
        case .fastSigningBiometrics:
            fastSigningBiometrics
        case .passwordHint:
            passwordHint
        case .backupVault:
            backupVault
        case .migrateVault:
            migrateVault
        case .advancedSettings:
            advancedSettings
        }
    }

    var fastSigningBiometrics: some View {
        SettingsOptionView(
            icon: .bolt,
            title: "biometricsFastSigning".localized
        ) {
            VultiToggle(isOn: Binding(
                get: { viewModel.isBiometryEnabled },
                set: { onBiometryEnabledChanged($0) }
            ))
        }
    }

    var passwordHint: some View {
        Button {
            router.navigate(to: VaultRoute.passwordHint(vault: vault))
        } label: {
            SettingsCommonOptionView(icon: .inputPasswordEdit, title: "passwordHint".localized, subtitle: "setOrUpdateHint".localized)
        }
    }

    var vaultDetails: some View {
        Button {
            router.navigate(to: VaultRoute.vaultDetails(vault: vault, devicesInfo: devicesInfo))
        } label: {
            SettingsCommonOptionView(icon: .circleInfo, title: "vaultDetailsTitle".localized, subtitle: "vaultDetailsDescription".localized)
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
                icon: .cloudDownload,
                title: "backupVaultShareTitle".localized,
                subtitle: "backupVaultShareDescription".localized
            )
        }
    }

    var editVault: some View {
        Button {
            router.navigate(to: VaultRoute.renameVault(vault: vault, vaults: vaults, folders: folders))
        } label: {
            SettingsCommonOptionView(
                icon: .penWritingFilled,
                title: "rename".localized,
                subtitle: "renameVault".localized
            )
        }
    }

    var deleteVault: some View {
        Button {
            router.navigate(to: VaultRoute.deleteVault(vault: vault, devicesInfo: devicesInfo))
        } label: {
            SettingsCommonOptionView(
                icon: .trash,
                title: "delete".localized,
                subtitle: "deleteVault".localized,
                type: .alert
            )
        }

    }

    var migrateVault: some View {
        Button {
            showUpgradeYourVaultSheet = true
        } label: {
            SettingsCommonOptionView(
                icon: .cloudUpload,
                title: "migrate".localized,
                subtitle: "migrateVault".localized
            )
        }
    }

    var advancedSettings: some View {
        Button {
            router.navigate(to: VaultRoute.advancedSettings(vault: vault))
        } label: {
            SettingsCommonOptionView(
                icon: .folderKey,
                title: "advanced".localized,
                subtitle: "advancedDescription".localized
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
            router.navigate(to: VaultRoute.backupSelection(vault: vault))
        } else {
            router.navigate(to: VaultRoute.backupPasswordOptions(
                tssType: .Keygen,
                backupType: .single(vault: vault),
                isNewVault: false
            ))
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
