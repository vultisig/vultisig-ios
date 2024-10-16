//
//  VaultPairDetailView.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 10/04/2024.
//
import Foundation
import SwiftUI

struct VaultPairDetailView: View {
    let vault: Vault    
    @State var devicesInfo: [DeviceInfo] = []
    
    var body: some View {
        content
            .onAppear {
                self.devicesInfo = vault.signers.enumerated().map { index, signer in
                    DeviceInfo(Index: index, Signer: signer)
                }
            }
    }
    
    var cells: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                titleCell
                
                VaultPairDetailCell(title: NSLocalizedString("ECDSA", comment: ""), description: vault.pubKeyECDSA).frame(maxWidth: .infinity, alignment: .leading)
                
                VaultPairDetailCell(title: NSLocalizedString("EdDSA", comment: ""), description: vault.pubKeyEdDSA).frame(maxWidth: .infinity, alignment: .leading)
                
                Text("\(vault.getThreshold() + 1) of \(vault.signers.count) Vault")
                    .font(.body14MontserratMedium)
                    .foregroundColor(.neutral0)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, alignment: .center)
                
                ForEach(devicesInfo, id: \.Index) { device in
                    getDeviceCell(for: device)
                }
            }
            .padding(.top, 30)
        }
    }
    
    var titleCell: some View {
        Text(titleText())
            .foregroundColor(.neutral0)
            .font(.body20MenloBold)
            .padding(.vertical, 22)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.blue600)
            .cornerRadius(10)
            .padding(.horizontal, 16)
            .lineLimit(3)
    }
    
    private func titleText() -> String {
        let name = vault.name
        let dash = " - "
        let part = NSLocalizedString("part", comment: "")
        let of = NSLocalizedString("of", comment: "")
        let space = " "
        let vaultIndex = "\(vault.getThreshold() + 1)"
        let totalCount = "\(vault.signers.count)"
        
        return name + dash + part + space + vaultIndex + space + of + space + totalCount
    }
    
    private func getDeviceCell(for device: DeviceInfo) -> some View {
        let part = "Part of \(device.Index+1) of \(vault.signers.count): "
        let signer = device.Signer
        let suffix = device.Signer == vault.localPartyID ? " (This device)" : ""
        
        return VaultPairDetailCell(
            title: .empty,
            description: part + signer + suffix
        )
    }
}

#Preview {
    VaultPairDetailView(vault: Vault.example)
}
