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
#if os(iOS)
        ZStack {
            if type == .Address {
                shareLink
            } else {
                button
            }
        }
#elseif os(macOS)
        shareLink
#endif
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
    
#if os(iOS)
    var button: some View {
        Button {
            shareImage()
        } label: {
            content
        }
    }
#endif
    
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
    
#if os(iOS)
    func shareImage() {
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
                    .frame(width: 278, height: 500)
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
