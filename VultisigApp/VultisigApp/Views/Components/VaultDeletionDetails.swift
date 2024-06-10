//
//  VaultDeletionDetails.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-06-10.
//

import SwiftUI

struct VaultDeletionDetails: View {
    let vault: Vault
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            title
            nameCell
            typeCell
            ECDSAKeyCell
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
        .font(.body20MenloBold)
        .foregroundColor(.neutral0)
    }
    
    var nameCell: some View {
        HStack(spacing: 0) {
            getTitleText("vaultName")
            getDescriptionText(vault.name)
        }
    }
    
    var typeCell: some View {
        HStack(spacing: 0) {
            getTitleText("vaultType")
            getDescriptionText(getVaultType())
        }
    }
    
    var ECDSAKeyCell: some View {
        HStack(spacing: 0) {
            getTitleText("ECDSAKey")
            getDescriptionText(vault.pubKeyECDSA)
        }
    }
    
    var EdDSAKeyCell: some View {
        HStack(spacing: 0) {
            getTitleText("EdDSAKey")
            getDescriptionText(vault.pubKeyEdDSA)
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
    
    private func getDescriptionText(_ description: String) -> some View {
        Text(NSLocalizedString(description, comment: ""))
            .font(.body12Menlo)
            .foregroundColor(.neutral0)
    }
    
    private func getVaultType() -> String {
        return ""
    }
}

#Preview {
    ZStack {
        Background()
        VaultDeletionDetails(vault: Vault.example)
    }
}
