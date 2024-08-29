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
#if os(iOS)
        shareButton
#elseif os(macOS)
        VStack(spacing: 12) {
            saveButton
            shareButton
        }
        .padding(.horizontal, 25)
#endif
    }
    
#if os(macOS)
    var saveButton: some View {
        ZStack {
            if let renderedImage = viewModel.renderedImage {
                Button {
                    isExporting = true
                } label: {
                    FilledButton(title: "save")
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
#endif
    
    var shareButton: some View {
        ZStack {
            if let renderedImage = viewModel.renderedImage {
                ShareLink(
                    item: renderedImage,
                    preview: SharePreview(imageName, image: renderedImage)
                ) {
#if os(iOS)
                    FilledButton(title: "saveOrShare")
                        .padding(.bottom, 10)
#elseif os(macOS)
                    OutlineButton(title: "share")
                        .padding(.bottom, 10)
#endif
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
