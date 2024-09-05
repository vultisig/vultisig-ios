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
    
    var shareButton: some View {
        Button {
            shareImage()
        } label: {
            FilledButton(title: "share")
                .padding(.bottom, 22)
        }
    }
    
    private func setData() {
        imageName = viewModel.generateName(vault: vault)
        viewModel.render(vault: vault, displayScale: displayScale)
    }
    
    func shareImage() {
        guard let image = viewModel.renderedImage else {
            return
        }
        
        let uiImage = renderImage(image: image)

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(imageName)

        // Save UIImage as PNG to temporary directory
        if let pngData = uiImage.pngData() {
            try? pngData.write(to: tempURL)
        }

        // Create and present the share sheet
        let activityViewController = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)

        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            rootViewController.present(activityViewController, animated: true, completion: nil)
        }
    }
    
    func renderImage(image: Image) -> UIImage {
        let controller = UIHostingController(
            rootView: 
                image
                    .frame(width: 278, height: 402)
                    .offset(y: -30)
        )
        let view = controller.view

        let targetSize = controller.view.intrinsicContentSize
        view?.bounds = CGRect(origin: .zero, size: targetSize)
        view?.backgroundColor = .clear

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            view?.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }
    }
}

#Preview {
    VaultDetailQRCodeView(vault: Vault.example)
}
