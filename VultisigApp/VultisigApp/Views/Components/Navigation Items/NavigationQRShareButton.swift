//
//  NavigationQRShareButton.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-06-07.
//

import SwiftUI
import CoreTransferable

enum NavigationQRType {
    case Keygen
    case Keysign
    case Address
}

struct NavigationQRShareButton: View {
    let vault: Vault
    let type: NavigationQRType
    let viewModel: ShareSheetViewModel
    var tint: Color = Theme.colors.textPrimary
    
    var title: String = ""
    
    @State var imageName: String = ""
    
    var body: some View {
        container
    }
    
    var shareLink: some View {
        ZStack {
            if let image = viewModel.renderedImage {
                getLink(image: image)
            } else {
                ProgressView()
            }
        }
    }
    
    @ViewBuilder
    private func getLink(image: Image) -> some View {
        CrossPlatformShareButton(image: image, caption: viewModel.qrCodeData ?? .empty) {
            content
        }
        .onLoad {
            setData()
        }
    }
    
    var content: some View {
        Image(systemName: "arrow.up.doc")
            .font(Theme.fonts.bodyLMedium)
            .foregroundColor(tint)
    }
    
    func setData() {
        if type == .Address {
            imageName = "Vultisig-\(vault.name)-\(title).png"
        } else {
            let name = vault.name
            let ecdsaKey = vault.pubKeyECDSA
            let eddsaKey = vault.pubKeyEdDSA
            let hexCode = vault.hexChainCode
            let id = "\(name)-\(ecdsaKey)-\(eddsaKey)-\(hexCode)".sha256()
            
            let today = Date.now
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            let date = formatter.string(from: today).replacingOccurrences(of: "/", with: "-")
            
            let suffix = type == .Keygen ? "VaultKeygen" : "VaultSend"
            
            imageName = "\(suffix)-\(vault.name)-\(id.suffix(3))-\(date).png"
        }
    }
}

#Preview {
    ZStack {
        Background()
        NavigationQRShareButton(
            vault: Vault.example, 
            type: .Keygen,
            viewModel: ShareSheetViewModel()
        )
    }
}

