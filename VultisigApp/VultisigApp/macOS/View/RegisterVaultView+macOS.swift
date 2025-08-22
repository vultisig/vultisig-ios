//
//  RegisterVaultView+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-10-09.
//

#if os(macOS)
import SwiftUI

extension RegisterVaultView {
    var saveVaultButton: some View {
        ZStack {
            if let renderedImage = viewModel.renderedImage {
                PrimaryButton(title: "saveVaultQR") {
                    isExporting = true
                }
                .padding(.bottom, 24)
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
}
#endif
