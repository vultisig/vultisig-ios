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
    let devicesInfo: [DeviceInfo]
    
    @State var deviceIndex: Int = 0
    @State var showCapsule: Bool = false
    
    var body: some View {
        Screen(title: "vaultDetailsTitle".localized) {
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 24) {
                    vaultInfoSection
                    vaultKeysSection
                    vaultSetupSection
                }
            }
        }
        .overlay(PopupCapsule(text: "keyCopied", showPopup: $showCapsule))
    }
    
    var vaultInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("vaultInfo".localized)
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textExtraLight)
            
            vaultInfoRow(title: "vaultName".localized, description: vault.name)
            vaultInfoRow(title: "vaultPart".localized, description: titlePartText())
            vaultInfoRow(title: "vaultLibType".localized, description: getVaultLibType())
        }
    }
    
    func vaultInfoRow(title: String, description: String) -> some View {
        ContainerView {
            HStack {
                Text(title)
                Spacer()
                Text(description)
            }
            .font(Theme.fonts.bodySMedium)
            .foregroundStyle(Theme.colors.textPrimary)
            .padding(.vertical, 4)
        }
    }
    
    var vaultKeysSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("keys".localized)
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textExtraLight)
            
            vaultKeyRow(title: "ECDSA".localized, description: vault.pubKeyECDSA)
            vaultKeyRow(title: "EdDSA".localized, description: vault.pubKeyEdDSA)
        }
    }
    
    func vaultKeyRow(title: String, description: String) -> some View {
        Button {
            ClipboardManager.copyToClipboard(description)
            showCapsule = true
        } label: {
            ContainerView {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(Theme.fonts.bodySMedium)
                            .foregroundStyle(Theme.colors.textPrimary)
                        Text(description)
                            .font(Theme.fonts.caption12)
                            .foregroundStyle(Theme.colors.textExtraLight)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer()
                    Icon(named: "copy", color: Theme.colors.textPrimary, size: 17)
                }
            }
        }
    }
    
    @ViewBuilder
    var vaultSetupSection: some View {
        let title = "\(vault.getThreshold()+1)-\("of".localized)-\(devicesInfo.count) " + "vaultSetup".localized
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textExtraLight)
            
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ],
                spacing: 12
            ) {
                ForEach(devicesInfo, id: \.Index) { device in
                    signerCell(for: device)
                }
            }
            
        }
    }
    
    @ViewBuilder
    func signerCell(for device: DeviceInfo) -> some View {
        let signer = device.Signer
        let isLocalPary = device.Signer == vault.localPartyID
        let signerTitle = "\("signer".localized) \(device.Index + 1)"
        
        ContainerView {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(signerTitle)
                        .font(Theme.fonts.footnote)
                        .foregroundStyle(Theme.colors.textLight)
                    
                    Text(signer)
                        .font(Theme.fonts.bodySMedium)
                        .foregroundStyle(Theme.colors.textPrimary)
                    
                    Text("thisDevice".localized)
                        .font(Theme.fonts.footnote)
                        .foregroundStyle(Theme.colors.textLight)
                        .showIf(isLocalPary)
                }
                Spacer()
                Icon(
                    named: iconName(for: signer),
                    color: Theme.colors.textExtraLight,
                    size: 24
                )
            }
            .frame(maxWidth: .infinity, maxHeight: 75, alignment: .center)
            .onLoad {
                if isLocalPary {
                    deviceIndex = device.Index + 1
                }
            }
        }
    }
    
    private func getVaultLibType() -> String{
        guard let libType = vault.libType else {
            return "GG20"
        }
        switch libType {
        case .DKLS:
            return "DKLS"
        case .GG20:
            return "GG20"
        case .KeyImport:
            return "DKLS-Imported"
        }
        
    }
    private func titlePartText() -> String {
        let part = NSLocalizedString("share", comment: "")
        let of = NSLocalizedString("of", comment: "")
        let space = " "
        let vaultIndex = "\(deviceIndex)"
        let totalCount = "\(vault.signers.count)"
        
        return part + space + vaultIndex + space + of + space + totalCount
    }
    
    func iconName(for signer: String) -> String {
        let laptopSigners = ["windows", "extension", "mac"]
        let isLaptoSigner = laptopSigners.contains {
            signer.lowercased().contains($0)
        }
         
        return isLaptoSigner ? "laptop" : "smartphone"
    }
}

#Preview {
    VaultPairDetailView(vault: Vault.example, devicesInfo: [])
}
