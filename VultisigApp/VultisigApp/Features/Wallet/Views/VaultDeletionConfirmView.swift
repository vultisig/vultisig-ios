//
//  VaultDeletionConfirmView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-06-05.
//

import SwiftUI
import SwiftData
import OSLog

struct VaultDeletionConfirmView: View {
    let vault: Vault
    let devicesInfo: [DeviceInfo]

    @State var permanentDeletionCheck = false
    @State var canLoseFundCheck = false
    @State var vaultBackupCheck = false

    @State var nextSelectedVault: Vault? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(\.router) var router
    @EnvironmentObject var homeViewModel: HomeViewModel
    @EnvironmentObject var appViewModel: AppViewModel

    private static let topContentInset: CGFloat = 17
    private static let glowOffset: CGFloat = -9.5
    private static let firstCheckboxMinHeight: CGFloat = 24
    private static let checkboxMinHeight: CGFloat = 40

    var buttonEnabled: Bool {
        permanentDeletionCheck && canLoseFundCheck && vaultBackupCheck
    }

    var body: some View {
        Screen {
            VStack {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        header
                        details
                        checkboxes
                    }
                    .padding(.top, Self.topContentInset)
                }
                deleteButton
            }
            .background(SettingsGlowBackground(tint: .destructive, verticalOffset: Self.glowOffset))
        }
        .screenTitle("deleteVaultTitle".localized)
    }

    var header: some View {
        VStack(spacing: 14) {
            Icon(
                .triangleWarningFilled,
                color: Theme.colors.alertError,
                size: 24
            )

            VStack(spacing: 8) {
                Text("deleteVaultTitle".localized)
                    .settingsText(.title2)
                    .foregroundStyle(Theme.colors.alertError)

                Text("youArePermanentlyDeletingVault".localized)
                    .settingsText(.footnote)
                    .foregroundStyle(Theme.colors.textTertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 283)
            }
        }
    }

    var checkboxes: some View {
        VStack(spacing: 2) {
            Checkbox(
                isChecked: $permanentDeletionCheck,
                text: "vaultWillBeDeletedPermanentlyPrompt",
                appearance: .settings(rowMinHeight: Self.firstCheckboxMinHeight)
            )
            Checkbox(
                isChecked: $canLoseFundCheck,
                text: "canLoseFundsPrompt",
                appearance: .settings(rowMinHeight: Self.checkboxMinHeight)
            )
            Checkbox(
                isChecked: $vaultBackupCheck,
                text: "madeVaultBackupPrompt",
                appearance: .settings(rowMinHeight: Self.checkboxMinHeight)
            )
        }
        .padding(.vertical, 8)
    }

    var deleteButton: some View {
        SettingsCTAButton(title: "deleteVaultTitle", width: .fill, kind: .destructive, weight: .semibold) {
            delete()
        }
        .disabled(!buttonEnabled)
    }

    var details: some View {
        VaultDeletionDetails(vault: vault, devicesInfo: devicesInfo)
    }

    func delete() {
        // fetch the vault before deleting it , so we can make sure we have all the relationships loaded
        let publicKeyECDSA = vault.pubKeyECDSA
        let fetchNextVaultRequest = FetchDescriptor<Vault>(predicate: #Predicate { $0.pubKeyECDSA != publicKeyECDSA })
        let vaultsNext = try? modelContext.fetch(fetchNextVaultRequest)
        nextSelectedVault = vaultsNext?.first

        if nextSelectedVault != nil {
            appViewModel.set(selectedVault: nextSelectedVault, showingVaultSelector: false)
        } else {
            router.navigate(to: VaultRoute.createVault(showBackButton: false))
        }

        // Add delay on deletion to prevent accesing deleted vault during navigation
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            do {
                let fetchRequest = FetchDescriptor<Vault>(predicate: #Predicate { $0.pubKeyECDSA == publicKeyECDSA })
                let vaultsToDelete = try modelContext.fetch(fetchRequest)
                if let targetToBeDeleted = vaultsToDelete.first {
                    // the following few lines are used to ensure that all relationships are loaded before deletion
                    _ = targetToBeDeleted.signers
                    _ = targetToBeDeleted.keyshares
                    _ = targetToBeDeleted.libType
                    _ = targetToBeDeleted.closedBanners
                    _ = targetToBeDeleted.defiChains
                    _ = targetToBeDeleted.defiPositions
                    _ = targetToBeDeleted.bondPositions
                    _ = targetToBeDeleted.stakePositions
                    _ = targetToBeDeleted.lpPositions

                    modelContext.delete(targetToBeDeleted)
                }
                try modelContext.save()
            } catch {
                Log.wallet.view.error("Error: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

#Preview {
    VaultDeletionConfirmView(vault: Vault.example, devicesInfo: [])
        .environmentObject(HomeViewModel())
        .environmentObject(AppViewModel())
}
