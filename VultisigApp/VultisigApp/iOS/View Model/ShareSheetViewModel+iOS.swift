//
//  ShareSheetViewModel+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-13.
//

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
