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
    
    func render(title: String, addressData: String, displayScale: CGFloat) {
        let renderer = ImageRenderer(content: QRShareSheetImage(title: addressData, addressData: addressData))

        renderer.scale = displayScale

        if let uiImage = renderer.uiImage {
            renderedImage = Image(uiImage: uiImage)
        }
    }
}
