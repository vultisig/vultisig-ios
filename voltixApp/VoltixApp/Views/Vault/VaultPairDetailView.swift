//
//  VaultPairDetailView.swift
//  VoltixApp
//
//  Created by Enrique Souza Soares on 10/04/2024.
//
import Foundation
import SwiftUI

struct VaultPairDetailView: View {
    let vault: Vault
    
    @State var devicesInfo: [DeviceInfo] = []
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        ZStack {
            Background()
            view
        }
        .navigationBarBackButtonHidden(true)
        .navigationTitle(NSLocalizedString("vaultDetailsTitle", comment: "View your vault details"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationBackButton()
            }
        }
        .onAppear {
            self.devicesInfo = vault.signers.enumerated().map { index, signer in
                DeviceInfo(Index: index, Signer: signer, PubKey: vault.keyshares[index].pubkey)
            }
        }
    }
    
    var view: some View {
        VStack {
            content
        }
    }
    
    var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                
                VaultPairDetailCell(title: NSLocalizedString("vaultName", comment: ""), description: vault.name).frame(maxWidth: .infinity, alignment: .leading)
                
                VaultPairDetailCell(title: "Device Name", description: Utils.getLocalDeviceIdentity()).frame(maxWidth: .infinity, alignment: .leading)
                
                VaultPairDetailCell(title: "ECDSA", description: vault.pubKeyECDSA).frame(maxWidth: .infinity, alignment: .leading)
                
                VaultPairDetailCell(title: "EdDSA", description: vault.pubKeyEdDSA).frame(maxWidth: .infinity, alignment: .leading)
                
                
                Text("\(vault.getThreshold() + 1) of \(vault.signers.count) Vault")
                    .font(.body14MontserratMedium)
                    .foregroundColor(.neutral0)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, alignment: .center)
                
                ForEach(devicesInfo, id: \.Signer) { device in
                    VaultPairDetailCell(title: device.Signer, description: device.PubKey)
                }
            }
        }
    }
}




#Preview {
    VaultPairDetailView(vault: Vault.example)
}
