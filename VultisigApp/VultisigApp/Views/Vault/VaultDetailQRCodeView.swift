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
    @State var isExporting: Bool = false

    @StateObject var viewModel = VaultDetailQRCodeViewModel()
    @Environment(\.displayScale) var displayScale

    var body: some View {
        Screen(title: "shareVaultQR".localized, edgeInsets: .init(bottom: .zero)) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 15) {
                    qrCode
                    InfoBannerView(
                        description: "shareVaultQRInformation".localized,
                        type: .info,
                        leadingIcon: "circle-info"
                    )
                    buttons
                }
                .onLoad {
                    setData()
                }
            }
        }
    }

    var qrCode: some View {
        VaultDetailQRCode(vault: vault, viewModel: viewModel)
    }

    var saveButton: some View {
        ZStack {
            if let renderedImage = viewModel.renderedImage {
                PrimaryButton(title: "save", type: .secondary) {
                    isExporting = true
                }
                .fileExporter(
                    isPresented: $isExporting,
                    document: ImageFileDocument(image: renderedImage),
                    contentType: .png,
                    defaultFilename: imageName
                ) { result in
                    switch result {
                    case .success(let url):
                        print("Image saved to: \(url.path)")
                    case .failure(let error):
                        print("Error saving image: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    var shareLinkButton: some View {
        ZStack {
            if let renderedImage = viewModel.renderedImage {
                ShareLink(
                    item: renderedImage,
                    preview: SharePreview(imageName, image: renderedImage)
                ) {
                    PrimaryButtonView(title: "share", leadingIcon: "share")
                }
                .buttonStyle(PrimaryButtonStyle())
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
