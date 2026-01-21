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
    @Published var qrCodeData: String?

    func render(
        qrCodeImage: Image,
        qrCodeData: String?,
        displayScale: CGFloat,
        type: QRShareSheetType,
        addressData: String = "",
        vaultName: String = "",
        amount: String = "",
        toAddress: String = "",
        fromAmount: String = "",
        toAmount: String = ""
    ) {
        let renderer = ImageRenderer(
            content:
            QRShareSheetImage(
                image: qrCodeImage,
                type: type,
                vaultName: vaultName,
                amount: amount,
                toAddress: toAddress,
                fromAmount: fromAmount,
                toAmount: toAmount,
                address: addressData
            )
        )

        renderer.scale = displayScale
        setImage(renderer)
        self.qrCodeData = qrCodeData
    }
    func clear() {
        print("clear image reference")
        renderedImage = nil
        qrCodeData = nil
    }
}
