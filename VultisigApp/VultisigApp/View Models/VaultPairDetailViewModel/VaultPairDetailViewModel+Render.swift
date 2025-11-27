//
//  VaultPairDetailViewModel+Render.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 24/11/2025.
//

import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

extension VaultPairDetailViewModel {
    func render(vault: Vault, devicesInfo: [DeviceInfo], displayScale: CGFloat) {
        let cardView = VaultPairDetailCard(vault: vault, devicesInfo: devicesInfo, isForSharing: true)
        let renderer = ImageRenderer(content: cardView)

        #if os(iOS)
        let screenSize = UIScreen.main.bounds.size
        renderer.proposedSize = ProposedViewSize(screenSize)
        renderer.scale = displayScale

        if let uiImage = renderer.uiImage {
            renderedImage = Image(uiImage: uiImage)
        }
        #elseif os(macOS)
        // Use a larger width for better quality on macOS
        // Let height be determined by content to avoid white borders
        let targetWidth: CGFloat = 1200
        renderer.proposedSize = ProposedViewSize(width: targetWidth, height: nil)
        // Use 2x scale for retina quality (or 3x for even higher quality)
        renderer.scale = max(displayScale, 2.0)

        if let nsImage = renderer.nsImage {
            renderedImage = Image(nsImage: nsImage)
        }
        #endif
    }
}
