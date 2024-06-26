//
//  ShareSheetViewModel.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-06-07.
//

import SwiftUI

@MainActor
class ShareSheetViewModel: ObservableObject {
    @Published var renderedImage: Image? = nil
    
    func render(title: String, qrCodeImage: Image, displayScale: CGFloat) {
        let renderer = ImageRenderer(content: QRShareSheetImage(title: title, image: qrCodeImage))

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
}
