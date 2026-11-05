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
    @State var isPasscodeSet = false
    @State var showReferralBannerSheet = false
    @StateObject var viewModel = SettingsBiometryViewModel()
    @StateObject var referredViewModel = ReferredViewModel()

    private let passcodeService: PasscodeService

    init(vault: Vault, passcodeService: PasscodeService = .shared) {
        self.vault = vault
        self.passcodeService = passcodeService
    }

    var body: some View {
        Screen {
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 14) {
                    section(title: "vaultManagement".localized, rows: vaultManagementRows)
                    section(title: "security".localized, rows: securityRows)
                    section(title: "other".localized, rows: otherRows)

                    deleteVault
                        .commonListContainer(style: .flush)
                }
            }
        }
        .screenTitle("vaultSettings".localized)
        .screenEdgeInsets(ScreenEdgeInsets(bottom: 0))
        .onLoad(perform: onLoad)
        // The passcode is set or removed on a screen pushed from here, and returning
        // from it does not re-run `.task`.
        .task { await refreshPasscodeState() }
        .onAppear { Task { await refreshPasscodeState() } }
        // On macOS `.task` does not re-run when a pushed screen pops.
        #if os(macOS)
        .onReceive(router.$navPath) { _ in
            Task { await refreshPasscodeState() }
        }
        #endif
        .crossPlatformSheet(isPresented: $showReferralBannerSheet) {
            ReferralOnboardingBanner {
                showReferralBannerSheet = false
                referredViewModel.showReferralCodeOnboarding = false
                router.navigate(to: ReferralRoute.onboarding)
            } onClose: {
                showReferralBannerSheet = false
            }.presentationDetents([.height(400)])
        }
        .crossPlatformSheet(isPresented: $showUpgradeYourVaultSheet) {
            UpgradeYourVaultView(
                showSheet: $showUpgradeYourVaultSheet,
                onUpgrade: {
                    router.navigate(to: VaultRoute.upgradeVault(
                        vault: vault
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

    private static let toggleLayoutHeight: CGFloat = 20

    /// The rows a section can hold. Sections compose them as an ordered array
    /// so each row knows its position, which is what drives the shared list
    /// container's separators and end-row corner rounding.
    enum Row {
        case vaultDetails
        case editVault
        case referralCode
        case fastSigningBiometrics
        case security
        case lockTime
        case passwordHint
        case backupVault
        case migrateVault
        case advancedSettings
    }

    var vaultManagementRows: [Row] {
        var rows: [Row] = [.vaultDetails, .editVault, .referralCode]
        if vault.isFastVault {
            rows.append(.fastSigningBiometrics)
        }
        return rows
    }

    var securityRows: [Row] {
        var rows: [Row] = [.security]
        if isPasscodeSet {
            rows.append(.lockTime)
        }
        if vault.isFastVault {
            rows.append(.passwordHint)
        }
        rows.append(.backupVault)
        return rows
    }

    var otherRows: [Row] {
        let canMigrate = vault.libType == nil || vault.libType == .GG20
        return canMigrate ? [.migrateVault, .advancedSettings] : [.advancedSettings]
    }

    func section(title: String, rows: [Row]) -> some View {
        SettingsSectionView(title: title, style: .flush) {
            ForEach(Array(rows.enumerated()), id: \.element) { index, row in
                view(for: row)
                    .commonListItemContainer(index: index, itemsCount: rows.count, style: .flush)
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
        case .referralCode:
            referralCode
        case .fastSigningBiometrics:
            fastSigningBiometrics
        case .security:
            security
        case .lockTime:
            lockTime
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
            icon: .boltFilled,
            title: "biometricsFastSigning".localized,
            titleStyle: .footnote
        ) {
            Toggle("biometricsFastSigning".localized, isOn: Binding(
                get: { viewModel.isBiometryEnabled },
                set: { onBiometryEnabledChanged($0) }
            ))
            .toggleStyle(SettingsToggleStyle())
            // The switch overhangs the row's padding so the row stays as tall as an icon row.
            .frame(height: Self.toggleLayoutHeight)
        }
    }

    var passwordHint: some View {
        Button {
            router.navigate(to: VaultRoute.passwordHint(vault: vault))
        } label: {
            SettingsCommonOptionView(
                icon: .inputPasswordEdit,
                title: "passwordHint".localized,
                subtitle: "setOrUpdateHint".localized,
                titleStyle: .footnote
            )
        }
    }

    var referralCode: some View {
        Button {
            if referredViewModel.showReferralCodeOnboarding {
                showReferralBannerSheet = true
            } else {
                router.navigate(to: ReferralRoute.initial)
            }
        } label: {
            SettingsCommonOptionView(icon: .megaphone, title: "referralCode".localized, titleStyle: .footnote)
        }
    }

    var security: some View {
        Button {
            router.navigate(to: SettingsRoute.managePasscode)
        } label: {
            SettingsCommonOptionView(
                icon: .shield,
                title: "security".localized,
                subtitle: "securitySettingsSubtitle".localized,
                titleStyle: .footnote
            )
        }
        .accessibilityIdentifier(AccessibilityID.Settings.managePasscodeCell)
    }

    var lockTime: some View {
        Button {
            router.navigate(to: SettingsRoute.autoLock)
        } label: {
            SettingsCommonOptionView(
                icon: .lockFilled,
                title: "lockTime".localized,
                subtitle: "lockTimeSubtitle".localized,
                titleStyle: .footnote
            )
        }
        .accessibilityIdentifier(AccessibilityID.Settings.autoLockCell)
    }

    var vaultDetails: some View {
        Button {
            router.navigate(to: VaultRoute.vaultDetails(vault: vault, devicesInfo: devicesInfo))
        } label: {
            SettingsCommonOptionView(
                icon: .circleInfo,
                title: "vaultDetailsTitle".localized,
                subtitle: "vaultDetailsDescription".localized,
                titleStyle: .footnote
            )
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
                subtitle: "backupVaultShareDescription".localized,
                titleStyle: .footnote
            )
        }
    }

    var editVault: some View {
        Button {
            router.navigate(to: VaultRoute.renameVault(vault: vault, vaults: vaults, folders: folders))
        } label: {
            SettingsCommonOptionView(
                icon: .penWriting,
                title: "rename".localized,
                subtitle: "renameVault".localized,
                titleStyle: .footnote
            )
        }
    }

    var deleteVault: some View {
        Button {
            router.navigate(to: VaultRoute.deleteVault(vault: vault, devicesInfo: devicesInfo))
        } label: {
            SettingsCommonOptionView(
                icon: .trashFilled,
                title: "delete".localized,
                subtitle: "deleteVault".localized,
                type: .alert,
                titleStyle: .footnote,
                chevron: .regular
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
                subtitle: "migrateVault".localized,
                titleStyle: .footnote,
                chevron: .regular
            )
        }
    }

    var advancedSettings: some View {
        Button {
            router.navigate(to: VaultRoute.advancedSettings(vault: vault))
        } label: {
            SettingsCommonOptionView(
                icon: .fileSearch,
                title: "advanced".localized,
                subtitle: "advancedDescription".localized,
                titleStyle: .footnote,
                chevron: .regular
            )
        }
    }

    private func onLoad() {
        self.isFastSigningBiometricsEnabled = viewModel.isBiometryEnabled
        devicesInfo = vault.signers.enumerated().map { index, signer in
            DeviceInfo(Index: index, Signer: signer)
        }
    }

    private func refreshPasscodeState() async {
        isPasscodeSet = await passcodeService.isSet
    }

    func onDeviceBackup() {
        if vaults.count > 1 {
            router.navigate(to: VaultRoute.backupSelection(vault: vault, origin: .vaultSettings))
        } else {
            router.navigate(to: VaultRoute.backupPasswordOptions(
                tssType: .Keygen,
                backupType: .single(vault: vault),
                isNewVault: false,
                origin: .vaultSettings
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
