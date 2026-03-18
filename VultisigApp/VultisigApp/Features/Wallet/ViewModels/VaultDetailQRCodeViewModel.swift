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

    func generateName(vault: Vault) -> String {
        let name = vault.name
        let ecdsaKey = vault.pubKeyECDSA
        let eddsaKey = vault.pubKeyEdDSA
        let hexCode = vault.hexChainCode
        let id = "\(name)-\(ecdsaKey)-\(eddsaKey)-\(hexCode)".sha256()
        let cleanVaultName = vault.name.replacingOccurrences(of: "/", with: "-")
        return "VultisigQR-\(cleanVaultName)-\(id.suffix(3)).png"
    }

    func getVaultPublicKeyExport(vault: Vault) -> VaultPublicKeyExport {
        let name = vault.name
        let ecdsaKey = vault.pubKeyECDSA
        let eddsaKey = vault.pubKeyEdDSA
        let hexCode = vault.hexChainCode
        let id = "\(name)-\(ecdsaKey)-\(eddsaKey)-\(hexCode)".sha256()

        return VaultPublicKeyExport(uid: id, name: name, public_key_ecdsa: ecdsaKey, public_key_eddsa: eddsaKey, hex_chain_code: hexCode)
    }

    func getId(for vault: Vault) -> String {
        let name = vault.name
        let ecdsaKey = vault.pubKeyECDSA
        let eddsaKey = vault.pubKeyEdDSA
        let hexCode = vault.hexChainCode
        return "\(name)-\(ecdsaKey)-\(eddsaKey)-\(hexCode)".sha256()
    }
}

#if os(iOS)
import SwiftUI

extension VaultDetailQRCodeViewModel {
    func render(vault: Vault, displayScale: CGFloat) {
        let screenSize = UIScreen.main.bounds.size

        // Create a scaled version that fills the screen while maintaining aspect ratio
        let qrCodeView = VaultDetailQRCode(vault: vault)

        let renderer = ImageRenderer(content: qrCodeView)
        renderer.proposedSize = ProposedViewSize(screenSize)
        renderer.scale = displayScale

        if let uiImage = renderer.uiImage {
            renderedImage = Image(uiImage: uiImage)
        }
    }

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

    func renderImage(image: Image) -> UIImage {
        let controller = UIHostingController(rootView: image)
        let view = controller.view

        let targetSize = controller.view.intrinsicContentSize
        view?.bounds = CGRect(origin: .zero, size: targetSize)
        view?.backgroundColor = .clear

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            view?.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }
    }
}
#endif

#if os(macOS)
import SwiftUI

extension VaultDetailQRCodeViewModel {
    func render(vault: Vault, displayScale: CGFloat) {
        let renderer = ImageRenderer(content: VaultDetailMacQRCode(vault: vault))

        renderer.scale = displayScale

        if let nsImage = renderer.nsImage {
            renderedImage = Image(nsImage: nsImage)
        }
    }
}
#endif
