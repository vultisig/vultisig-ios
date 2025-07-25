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
        content
    }
    
    var view: some View {
        VStack {
            Spacer()
            qrCode
            Spacer()
            buttons
        }
        .padding(15)
        .onAppear {
            setData()
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
                .padding(.bottom, 22)
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
                    PrimaryButtonView(title: "share", leadingIcon: "square.and.arrow.up")
                    .padding(.bottom, 22)
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
