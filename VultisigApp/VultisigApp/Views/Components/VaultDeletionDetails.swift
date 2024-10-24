//
//  VaultDeletionDetails.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-06-10.
//

import SwiftUI

struct VaultDeletionDetails: View {
    let vault: Vault
    
    @EnvironmentObject var homeViewModel: HomeViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            title
            nameCell
            valueCell
            typeCell
            deviceCell
            ECDSAKeyCell
            EdDSAKeyCell
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.blue600)
        .cornerRadius(10)
    }
    
    var title: some View {
        Group {
            Text(NSLocalizedString("details", comment: "")) +
            Text(":")
        }
        .multilineTextAlignment(.leading)
        .font(.body20MontserratSemiBold)
        .foregroundColor(.neutral0)
        .padding(.top, 8)
    }
    
    var nameCell: some View {
        HStack(spacing: 0) {
            getTitleText("vaultName")
            getDescriptionText(vault.name)
        }
    }
    
    var valueCell: some View {
        HStack(spacing: 0) {
            getTitleText("vaultValue")
            getDescriptionText(homeViewModel.selectedVault?.coins.totalBalanceInFiatString ?? "$0")
        }
    }
    
    var typeCell: some View {
        HStack(spacing: 0) {
            getTitleText("vaultType")
            getDescriptionText(getVaultType())
        }
    }
    
    var deviceCell: some View {
        HStack(spacing: 0) {
            getTitleText("deviceID")
            getDescriptionText(vault.localPartyID)
        }
    }
    
    var ECDSAKeyCell: some View {
        HStack(spacing: 0) {
            getTitleText("ECDSAKey")
            getDescriptionText(vault.pubKeyECDSA, shouldShrink: true)
        }
    }
    
    var EdDSAKeyCell: some View {
        HStack(spacing: 0) {
            getTitleText("EdDSAKey")
            getDescriptionText(vault.pubKeyEdDSA, shouldShrink: true)
        }
    }
    
    private func getTitleText(_ title: String) -> some View {
        Group {
            Text(NSLocalizedString(title, comment: "")) +
            Text(": ")
        }
        .font(.body14Menlo)
        .foregroundColor(.neutral0)
    }
    
    private func getVaultType() -> String {
        return "\(vault.getThreshold() + 1) of \(vault.signers.count) Vaults"
    }
}

#Preview {
    ZStack {
        Background()
        VaultDeletionDetails(vault: Vault.example)
            .environmentObject(HomeViewModel())
    }
}
