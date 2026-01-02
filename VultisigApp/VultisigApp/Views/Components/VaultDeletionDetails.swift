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
    
    func setData(){
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
            HStack(spacing: 12) {
                ECDSAKeyView
                EdDSAKeyView
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear() {
            setData()
        }
    }
    
    func cellContainer<Content: View>(@ViewBuilder content: @escaping () -> Content) -> some View {
        ContainerView {
            content()
                .font(Theme.fonts.footnote)
                .foregroundStyle(Theme.colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    var nameView: some View {
        cellContainer {
            HStack {
                title(for: "vaultName".localized)
                Spacer()
                Text(vault.name)
            }
        }
    }
    
    var valueView: some View {
        cellContainer {
            HStack {
                title(for: "vaultValue".localized)
                Spacer()
                Text(totalValue)
            }
        }
    }
    
    var typeView: some View {
        cellContainer {
            VStack(alignment: .leading, spacing: 0) {
                title(for: "vaultType".localized)
                    .foregroundStyle(Theme.colors.textSecondary)
                Text(titlePartText())
            }
        }
    }
    
    var deviceView: some View {
        cellContainer {
            VStack(alignment: .leading, spacing: 0) {
                title(for: "deviceID".localized)
                    .foregroundStyle(Theme.colors.textSecondary)
                Text(vault.localPartyID)
            }
        }
    }
    
    var ECDSAKeyView: some View {
        cellContainer {
            VStack(alignment: .leading, spacing: 0) {
                title(for: "ECDSAKey".localized)
                    .foregroundStyle(Theme.colors.textSecondary)
                Text(vault.pubKeyECDSA)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    
    var EdDSAKeyView: some View {
        cellContainer {
            VStack(alignment: .leading, spacing: 0) {
                title(for: "EdDSAKey".localized)
                    .foregroundStyle(Theme.colors.textSecondary)
                Text(vault.pubKeyEdDSA)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    
    func title(for text: String) -> some View {
        Text("\(text):")
    }
    
    private func titlePartText() -> String {
        let part = NSLocalizedString("share", comment: "")
        let of = NSLocalizedString("of", comment: "")
        let space = " "
        let vaultIndex = getDeviceIndex()
        let totalCount = "\(vault.signers.count)"
        
        return part + space + vaultIndex + space + of + space + totalCount
    }
    
    private func getDeviceIndex() -> String {
        for device in devicesInfo {
            if device.Signer == vault.localPartyID {
                return "\(device.Index + 1)"
            }
        }
        
        return "0"
    }
}

#Preview {
    ZStack {
        Background()
        VaultDeletionDetails(vault: Vault.example, devicesInfo: [])
            .environmentObject(AppViewModel())
    }
}
