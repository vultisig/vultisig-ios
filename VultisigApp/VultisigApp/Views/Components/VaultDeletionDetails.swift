//
//  VaultDeletionDetails.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-06-10.
//

import SwiftUI

struct VaultDeletionDetails: View {
    let name: String
    let type: String
    let ECDSAKey: String
    let EdDSAKey: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            title
            nameCell
            typeCell
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
            getDescriptionText(name)
        }
    }
    
    var typeCell: some View {
        HStack(spacing: 0) {
            getTitleText("vaultType")
            getDescriptionText(type)
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
}

#Preview {
    ZStack {
        Background()
        VaultDeletionDetails(
            name: "Main Vault",
            type: "2-of-3 Vault",
            ECDSAKey: "asdjhfaksdjhfkajsdhflkajshflkasdjflkajsdflk",
            EdDSAKey: "lasdjflkasdjflkasjdflkasjdfklasjf"
        )
    }
}
