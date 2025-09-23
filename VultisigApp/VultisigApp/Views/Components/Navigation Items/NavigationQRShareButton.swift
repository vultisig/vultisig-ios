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
        shareLink
    }
    
    var shareLink: some View {
        ZStack {
            if let image = viewModel.renderedImage {
                CrossPlatformShareButton(image: image, caption: viewModel.qrCodeData ?? .empty) {
                    content
                }
            } else {
                ProgressView()
            }
        }
    }
    
    var content: some View {
        Image(systemName: "arrow.up.doc")
            .font(Theme.fonts.bodyLMedium)
            .foregroundColor(tint)
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

