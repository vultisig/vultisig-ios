//
//  RegisterVaultView+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-10-09.
//

#if os(iOS)
import SwiftUI

extension RegisterVaultView {
    var saveVaultButton: some View {
        ZStack {
            if let renderedImage = viewModel.renderedImage {
                ShareLink(
                    item: renderedImage,
                    preview: SharePreview(imageName, image: renderedImage)
                ) {
                    PrimaryButtonView(title: "saveVaultQR")
                }
                .buttonStyle(PrimaryButtonStyle())
            } else {
                ProgressView()
            }
        }
    }
}
#endif
