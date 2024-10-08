//
//  FolderDetailSelectedVaultCell.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-10-07.
//

import SwiftUI

struct FolderDetailSelectedVaultCell: View {
    let vault: Vault
    let isEditing: Bool
    
    @State var order: Int = 0
    @State var totalSigners: Int = 0
    @State var devicesInfo: [DeviceInfo] = []
    @State var isFastVault: Bool = false
    
    var body: some View {
        content
            .animation(.easeInOut, value: isEditing)
            .onAppear {
                setData()
            }
    }
    
    var content: some View {
        HStack {
            rearrange
            text
            
            if isFastVault {
                fastVaultLabel
            }
            
            Spacer()
            partAssignedCell
            
            if isEditing {
                toggle
            } else {
                chevron
            }
        }
        .padding(12)
        .background(Color.blue600)
        .cornerRadius(10)
    }
    
    var rearrange: some View {
        Image(systemName: "line.3.horizontal")
            .font(.body14MontserratMedium)
            .foregroundColor(.neutral100)
            .frame(maxWidth: isEditing ? nil : 0)
            .clipped()
    }
    
    var text: some View {
        Text(vault.name)
            .foregroundColor(.neutral0)
            .font(.body14MontserratBold)
    }
    
    var toggle: some View {
        Toggle("Is selected", isOn: .constant(true))
            .labelsHidden()
            .scaleEffect(0.8)
            .allowsHitTesting(false)
    }
    
    var partAssignedCell: some View {
        Text("Part \(order)of\(totalSigners)")
            .font(.body14Menlo)
            .foregroundColor(.body)
    }
    
    var fastVaultLabel: some View {
        Text(NSLocalizedString("fastModeTitle", comment: "").capitalized)
            .font(.body14Menlo)
            .foregroundColor(.body)
            .padding(4)
            .padding(.horizontal, 2)
            .background(Color.blue200)
            .cornerRadius(5)
            .lineLimit(1)
    }
    
    var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.body16MontserratBold)
            .foregroundColor(.neutral100)
            .frame(maxWidth: isEditing ? 0 : nil)
            .padding(.vertical, 8)
    }
    
    func setData() {
        assignSigners(vault)
        setupLabel(vault)
    }
    
    private func assignSigners(_ vault: Vault) {
        devicesInfo = vault.signers.enumerated().map { index, signer in
            DeviceInfo(Index: index, Signer: signer)
        }
    }
    
    private func setupLabel(_ vault: Vault) {
        totalSigners = devicesInfo.count
        checkForFastSign()
        checkForAssignedPart(vault)
    }
    
    private func checkForFastSign() {
        for index in 0..<devicesInfo.count {
            if devicesInfo[index].Signer.lowercased().hasPrefix("server-") {
                isFastVault = true
                return
            }
        }
    }
    
    private func checkForAssignedPart(_ vault: Vault) {
        for index in 0..<devicesInfo.count {
            if devicesInfo[index].Signer == vault.localPartyID {
                order = index+1
                return
            }
        }
    }
}

#Preview {
    VStack {
        FolderDetailSelectedVaultCell(vault: Vault.example, isEditing: false)
        FolderDetailSelectedVaultCell(vault: Vault.example, isEditing: true)
    }
}
