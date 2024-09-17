//
//  VaultCell.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-08.
//

import SwiftUI

struct VaultCell: View {
    let vault: Vault
    let isEditing: Bool
    
    @State var isFastVault: Bool = false
    @State var devicesInfo: [DeviceInfo] = []
    
    var body: some View {
        HStack(spacing: 12) {
            rearrange
            title
            Spacer()
            
            if isFastVault {
                fastVaultLabel
            }
            
            actions
        }
        .frame(height: 48)
        .padding(.horizontal, 16)
        .background(Color.blue600)
        .cornerRadius(10)
        .padding(.horizontal, 16)
        .animation(.easeInOut, value: isEditing)
        .onAppear {
            setData()
        }
    }
    
    var rearrange: some View {
        Image(systemName: "line.3.horizontal")
            .font(.body14MontserratMedium)
            .foregroundColor(.neutral100)
            .frame(maxWidth: isEditing ? nil : 0)
            .clipped()
    }
    
    var title: some View {
        Text(vault.name.capitalized)
            .font(.body16MenloBold)
            .foregroundColor(.neutral100)
    }
    
    var actions: some View {
        HStack(spacing: 8) {
            selectOption
        }
    }
    
    var fastVaultLabel: some View {
        Text(NSLocalizedString("fastSign", comment: ""))
            .font(.body14Menlo)
            .foregroundColor(.body)
            .padding(4)
            .padding(.horizontal, 2)
            .background(Color.blue200)
            .cornerRadius(5)
    }
    
    var selectOption: some View {
        Image(systemName: "chevron.right")
            .font(.body16MontserratBold)
            .foregroundColor(.neutral100)
    }
    
    private func setData() {
        devicesInfo = vault.signers.enumerated().map { index, signer in
            DeviceInfo(Index: index, Signer: signer)
        }
        
        for device in devicesInfo {
            if device.Signer.contains("Server-") {
                isFastVault = true
                return
            }
        }
    }
}

#Preview {
    VStack {
        VaultCell(vault: Vault.example, isEditing: true)
        VaultCell(vault: Vault.fastVaultExample, isEditing: false)
    }
}
