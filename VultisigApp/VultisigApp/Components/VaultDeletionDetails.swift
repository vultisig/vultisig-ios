//
//  VaultDeletionDetails.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-06-10.
//

import SwiftUI

struct VaultDeletionDetails: View {
    let vault: Vault
    let devicesInfo: [DeviceInfo]

    @EnvironmentObject var appViewModel: AppViewModel
    @State var totalValue: String = ""

    func setData() {
        totalValue = appViewModel.selectedVault?.coins.totalBalanceInFiatString ?? "$0"
    }

    var body: some View {
        VStack(spacing: 12) {
            nameView
            valueView
            HStack(spacing: 12) {
                typeView
                deviceView
            }
            .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                ECDSAKeyView
                EdDSAKeyView
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            setData()
        }
    }

    func rowCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            content()
        }
        .foregroundStyle(Theme.colors.textPrimary)
        .padding(20)
        .settingsInfoCard(radius: Theme.radius.lg)
    }

    func tileCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            content()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .settingsInfoCard(radius: Theme.radius.lg)
    }

    var nameView: some View {
        rowCard {
            title(for: "vaultName".localized)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(vault.name)
                .settingsText(.bodyS)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .multilineTextAlignment(.trailing)
        }
    }

    var valueView: some View {
        rowCard {
            title(for: "vaultValue".localized)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(totalValue)
                .settingsText(.bodyS)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .multilineTextAlignment(.trailing)
        }
    }

    var typeView: some View {
        tileCard {
            title(for: "vaultType".localized)
                .foregroundStyle(Theme.colors.textSecondary)
            Text(titlePartText())
                .settingsText(.footnote)
                .foregroundStyle(Theme.colors.textPrimary)
        }
    }

    var deviceView: some View {
        tileCard {
            title(for: "deviceID".localized)
                .foregroundStyle(Theme.colors.textSecondary)
            Text(vault.localPartyID)
                .settingsText(.footnote)
                .foregroundStyle(Theme.colors.textPrimary)
        }
    }

    var ECDSAKeyView: some View {
        keyTile(title: "ECDSAKey".localized, value: vault.pubKeyECDSA)
    }

    var EdDSAKeyView: some View {
        keyTile(title: "EdDSAKey".localized, value: vault.pubKeyEdDSA)
    }

    func keyTile(title text: String, value: String) -> some View {
        tileCard {
            title(for: text)
                .foregroundStyle(Theme.colors.textPrimary)
            Text(value)
                .settingsText(.caption)
                .foregroundStyle(Theme.colors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    func title(for text: String) -> some View {
        Text("\(text):")
            .settingsText(.footnote)
    }

    private func titlePartText() -> String {
        String(format: "vaultSharePosition".localized, getDeviceIndex(), vault.signers.count)
    }

    private func getDeviceIndex() -> Int {
        for device in devicesInfo {
            if device.Signer == vault.localPartyID {
                return device.Index + 1
            }
        }

        return 0
    }
}

#Preview {
    ZStack {
        Background()
        VaultDeletionDetails(vault: Vault.example, devicesInfo: [])
            .environmentObject(AppViewModel())
    }
}
