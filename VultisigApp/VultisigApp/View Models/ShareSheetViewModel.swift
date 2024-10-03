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
    
    func render(
        qrCodeImage: Image,
        displayScale: CGFloat,
        type: QRShareSheetType,
        addressData: String = ""
    ) {
        let renderer = ImageRenderer(
            content:
                QRShareSheetImage(
                    image: qrCodeImage,
                    type: type,
                    addressData: addressData
                )
        )

        renderer.scale = displayScale
        setImage(renderer)
    }
}
