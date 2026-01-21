//
//  NavigationQRShareButton.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-06-07.
//

import SwiftUI
import CoreTransferable

enum NavigationQRType {
    case Keygen
    case Keysign
    case Address
}

struct NavigationQRShareButton: View {
    let vault: Vault
    let type: NavigationQRType
    let viewModel: ShareSheetViewModel
    var tint: Color = Theme.colors.textPrimary

    var title: String = ""

    var body: some View {
        if let image = viewModel.renderedImage {
            CrossPlatformShareButton(image: image, caption: viewModel.qrCodeData ?? .empty) { onShare in
                ToolbarButton(image: "share", action: onShare)
            }
        }
    }
}

#Preview {
    ZStack {
        Background()
        NavigationQRShareButton(
            vault: Vault.example,
            type: .Keygen,
            viewModel: ShareSheetViewModel()
        )
    }
}
