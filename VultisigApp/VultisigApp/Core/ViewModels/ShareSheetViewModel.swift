//
//  ShareSheetViewModel.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-06-07.
//

import SwiftUI
import OSLog

private let logger = Logger(subsystem: "com.vultisig.app", category: "share-sheet-view-model")

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
        vaultType: String = "",
        amount: String = "",
        toAddress: String = "",
        coinLogo: String = "",
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
                coinLogo: coinLogo,
                fromAmount: fromAmount,
                toAmount: toAmount,
                vaultType: vaultType,
                address: addressData
            )
        )

        renderer.scale = displayScale
        setImage(renderer)
        self.qrCodeData = qrCodeData
    }
    func clear() {
        logger.debug("clear image reference")
        renderedImage = nil
        qrCodeData = nil
    }
}

#if os(iOS)
import SwiftUI

extension ShareSheetViewModel {
    func setImage(_ renderer: ImageRenderer<QRShareSheetImage>) {
        if let uiImage = renderer.uiImage {
            renderedImage = Image(uiImage: uiImage)
        }
    }
}
#endif

#if os(macOS)
import SwiftUI

extension ShareSheetViewModel {
    func setImage(_ renderer: ImageRenderer<QRShareSheetImage>) {
        if let nsImage = renderer.nsImage {
            renderedImage = Image(nsImage: nsImage)
        }
    }
}
#endif
