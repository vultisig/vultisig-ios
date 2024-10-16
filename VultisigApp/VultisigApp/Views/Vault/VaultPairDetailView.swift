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
    
    @State var deviceIndex: Int = 0
    
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
                getTitleCell(for: vault.name)
                getTitleCell(for: titlePartText())
                
                VaultPairDetailCell(title: NSLocalizedString("ECDSA", comment: ""), description: vault.pubKeyECDSA).frame(maxWidth: .infinity, alignment: .leading)
                
                VaultPairDetailCell(title: NSLocalizedString("EdDSA", comment: ""), description: vault.pubKeyEdDSA).frame(maxWidth: .infinity, alignment: .leading)
                
                Text(NSLocalizedString("devices", comment: ""))
                    .font(.body14MontserratMedium)
                    .foregroundColor(.neutral0)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .offset(y: 8)
                
                ForEach(devicesInfo, id: \.Index) { device in
                    getDeviceCell(for: device)
                }
            }
            .padding(.top, 30)
        }
    }
    
    private func getTitleCell(for text: String) -> some View {
        Text(text)
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
    
    private func getDeviceCell(for device: DeviceInfo) -> some View {
        let part = "Part of \(device.Index+1) of \(vault.signers.count): "
        let signer = device.Signer
        
        return ZStack {
            if device.Signer == vault.localPartyID {
                VaultPairDetailCell(
                    title: .empty,
                    description: part + signer + " (This device)"
                )
                .onAppear {
                    deviceIndex = device.Index + 1
                }
            } else {
                VaultPairDetailCell(
                    title: .empty,
                    description: part + signer
                )
            }
        }
    }
    
    private func titlePartText() -> String {
        let part = NSLocalizedString("part", comment: "")
        let of = NSLocalizedString("of", comment: "")
        let space = " "
        let vaultIndex = "\(deviceIndex)"
        let totalCount = "\(vault.signers.count)"
        
        return part + space + vaultIndex + space + of + space + totalCount
    }
}

#Preview {
    VaultPairDetailView(vault: Vault.example)
}
