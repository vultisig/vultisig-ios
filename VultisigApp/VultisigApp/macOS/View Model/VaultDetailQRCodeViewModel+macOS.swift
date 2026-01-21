//
//  VaultDetailQRCodeViewModel+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-13.
//

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
