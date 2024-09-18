//
//  NavigationQRShareButton.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-06-07.
//

import SwiftUI

enum NavigationQRType {
    case Keygen
    case Keysign
    case Address
}

struct NavigationQRShareButton: View {
    let vault: Vault
    let type: NavigationQRType
    let renderedImage: Image?
    var tint: Color = Color.neutral0
    
    var title: String = ""
    
    @State var imageName: String = ""
    
    var body: some View {
        container
    }
    
    var shareLink: some View {
        ZStack {
            if let image = renderedImage {
                getLink(image: image)
            } else {
                ProgressView()
            }
        }
    }
    
    private func getLink(image: Image) -> some View {
        ShareLink(
            item: image,
            preview: SharePreview(imageName, image: image)
        ) {
            content
        }
    }
    
    var content: some View {
        Image(systemName: "arrow.up.doc")
            .font(.body18MenloBold)
            .foregroundColor(tint)
            .onAppear {
                setData()
            }
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
            let date = formatter.string(from: today)
            
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
            renderedImage: nil
        )
    }
}
