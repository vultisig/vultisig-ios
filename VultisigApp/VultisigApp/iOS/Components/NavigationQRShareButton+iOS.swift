//
//  NavigationQRShareButton+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-13.
//

#if os(iOS)
import SwiftUI

extension NavigationQRShareButton {
    var container: some View {
        ZStack {
            //if type == .Address {
                shareLink
            //} else {
            //    button
            //}
        }
    }
    
    var deleteButton: some View {
        Button {
            shareImage()
        } label: {
            content
        }
    }
    
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
}
#endif
