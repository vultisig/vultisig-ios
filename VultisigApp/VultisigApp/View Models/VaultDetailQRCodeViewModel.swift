//
//  VaultDetailQRCodeViewModel.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-07-18.
//

import Foundation
import SwiftUI

@MainActor
class VaultDetailQRCodeViewModel: ObservableObject {
    @Published var renderedImage: Image? = nil
    
    func render(vault: Vault, displayScale: CGFloat) {
#if os(iOS)
        let renderer = ImageRenderer(content: VaultDetailQRCode(vault: vault))
#elseif os(macOS)
        let renderer = ImageRenderer(content: VaultDetailMacQRCode(vault: vault))
#endif

        renderer.scale = displayScale

#if os(iOS)
        if let uiImage = renderer.uiImage {
            renderedImage = Image(uiImage: uiImage)
        }
#elseif os(macOS)
        if let nsImage = renderer.nsImage {
            renderedImage = Image(nsImage: nsImage)
        }
#endif
    }
    
    func generateName(vault: Vault) -> String {
        let name = vault.name
        let ecdsaKey = vault.pubKeyECDSA
        let eddsaKey = vault.pubKeyEdDSA
        let hexCode = vault.hexChainCode
        let id = "\(name)-\(ecdsaKey)-\(eddsaKey)-\(hexCode)".sha256()
        
        return "VultisigQR-\(vault.name)-\(id.suffix(3)).png"
    }
    
    func getVaultPublicKeyExport(vault: Vault) -> VaultPublicKeyExport {
        let name = vault.name
        let ecdsaKey = vault.pubKeyECDSA
        let eddsaKey = vault.pubKeyEdDSA
        let hexCode = vault.hexChainCode
        let id = "\(name)-\(ecdsaKey)-\(eddsaKey)-\(hexCode)".sha256()
        
        return VaultPublicKeyExport(uid: id, name: name, public_key_ecdsa: ecdsaKey, public_key_eddsa: eddsaKey, hex_chain_code: hexCode)
    }
    
#if os(iOS)
    func shareImage(_ imageName: String) {
        guard let image = renderedImage else {
            return
        }
        
        let uiImage = renderImage(image: image)

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(imageName)

        if let pngData = uiImage.pngData() {
            try? pngData.write(to: tempURL)
        }

        let activityViewController = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)

        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            rootViewController.present(activityViewController, animated: true, completion: nil)
        }
    }
    
    private func renderImage(image: Image) -> UIImage {
        let controller = UIHostingController(
            rootView:
                image
                    .frame(width: 278, height: 402)
                    .offset(y: -30)
        )
        let view = controller.view

        let targetSize = controller.view.intrinsicContentSize
        view?.bounds = CGRect(origin: .zero, size: targetSize)
        view?.backgroundColor = .clear

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            view?.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }
    }
#endif
}
