//
//  ShareSheetViewModel+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-13.
//

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
