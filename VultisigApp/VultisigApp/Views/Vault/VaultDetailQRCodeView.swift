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
    
#if os(iOS)
    private var idiom : UIUserInterfaceIdiom { UIDevice.current.userInterfaceIdiom }
#endif
    
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
    
    var buttons: some View {
        HStack(spacing: 12) {
            saveButton
            shareButton
        }
        .padding(.horizontal, 25)
    }
    
    var saveButton: some View {
        ZStack {
            if let renderedImage = viewModel.renderedImage {
                Button {
                    isExporting = true
                } label: {
                    FilledButton(title: "save")
                        .padding(.bottom, 22)
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
    
#if os(iOS)
    var shareButton: some View {
        ZStack {
            if idiom == .phone {
                Button {
                    viewModel.shareImage(imageName)
                } label: {
                    FilledButton(title: "share")
                        .padding(.bottom, 22)
                }
            } else {
                shareLinkButton
            }
        }
    }
#elseif os(macOS)
    var shareButton: some View {
        shareLinkButton
    }
#endif
    
    var shareLinkButton: some View {
        ZStack {
            if let renderedImage = viewModel.renderedImage {
                ShareLink(
                    item: renderedImage,
                    preview: SharePreview(imageName, image: renderedImage)
                ) {
                    FilledButton(title: "share")
                        .padding(.bottom, 22)
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
