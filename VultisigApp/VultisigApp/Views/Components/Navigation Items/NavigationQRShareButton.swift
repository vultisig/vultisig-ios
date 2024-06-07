//
//  NavigationQRShareButton.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-06-07.
//

import SwiftUI

struct NavigationQRShareButton: View {
    let title: String
    let renderedImage: Image?
    var tint: Color = Color.neutral0
    
    var body: some View {
        ZStack {
            if let image = renderedImage {
                getLink(image: image)
            } else {
                ProgressView()
            }
        }
    }
    
    private func getLink(image: Image) -> some View {
        ShareLink(
            item: image,
            preview: SharePreview(Text(NSLocalizedString(title, comment: "")), image: image)
        ) {
            content
        }
    }
    
    var content: some View {
        Image(systemName: "arrow.up.doc")
            .font(.body16MenloBold)
            .foregroundColor(tint)
    }
}

#Preview {
    ZStack {
        Background()
        NavigationQRShareButton(title: "", renderedImage: nil)
    }
}
