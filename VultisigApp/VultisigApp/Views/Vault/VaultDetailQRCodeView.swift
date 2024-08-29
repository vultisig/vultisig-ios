//
//  VaultDetailQRCodeView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-07-18.
//

import SwiftUI

struct VaultDetailQRCodeView: View {
    let vault: Vault
    
    @State var imageName = ""
    @StateObject var viewModel = VaultDetailQRCodeViewModel()
    @Environment(\.displayScale) var displayScale
    
    var body: some View {
        ZStack {
            Background()
            main
        }
#if os(iOS)
        .navigationTitle(NSLocalizedString("shareVaultQR", comment: ""))
#endif
    }
    
    var main: some View {
        VStack {
#if os(macOS)
            headerMac
#endif
            content
        }
    }
    
    var headerMac: some View {
        GeneralMacHeader(title: "shareVaultQR")
    }
    
    var content: some View {
        VStack {
            Spacer()
            qrCode
            Spacer()
            button
        }
        .padding(15)
        .onAppear {
            setData()
        }
    }
    
    var qrCode: some View {
        VaultDetailQRCode(vault: vault, viewModel: viewModel)
    }
    
    var button: some View {
        ZStack {
            if let renderedImage = viewModel.renderedImage {
                ShareLink(
                    item: renderedImage,
                    preview: SharePreview(imageName, image: renderedImage)
                ) {
                    FilledButton(title: "saveOrShare")
                        .padding(.bottom, 10)
                }
            } else {
                ProgressView()
            }
        }
    }
    
    private func setData() {
        imageName = viewModel.generateName(vault: vault)
        viewModel.render(vault: vault, displayScale: displayScale)
    }
}

#Preview {
    VaultDetailQRCodeView(vault: Vault.example)
}
