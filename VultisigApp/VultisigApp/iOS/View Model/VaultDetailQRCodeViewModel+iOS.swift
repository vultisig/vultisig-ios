//
//  VaultDetailQRCodeViewModel+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-13.
//

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
