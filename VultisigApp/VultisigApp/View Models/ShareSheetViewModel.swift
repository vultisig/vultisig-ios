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
        setImage(renderer)
    }
}
