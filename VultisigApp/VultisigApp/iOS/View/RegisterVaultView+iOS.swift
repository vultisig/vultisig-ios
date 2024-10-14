//
//  RegisterVaultView+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-10-09.
//

#if os(iOS)
import SwiftUI

extension RegisterVaultView {
    var view: some View {
        VStack {
            image
            content
        }
        .navigationTitle(NSLocalizedString("registerVault", comment: ""))
    }
    
    var content: some View {
        VStack(alignment: .leading, spacing: 36) {
            text1
            text2
            text3
            text4
            Spacer()
            button
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .font(.body20MenloBold)
        .foregroundColor(.neutral0)
        .padding(16)
    }
    
    var button: some View {
        ZStack {
            if let renderedImage = viewModel.renderedImage {
                ShareLink(
                    item: renderedImage,
                    preview: SharePreview(imageName, image: renderedImage)
                ) {
                    label
                }
            } else {
                ProgressView()
            }
        }
    }
}
#endif
