//
//  OpenGalleryButton.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-05-15.
//

import SwiftUI

struct OpenGalleryButton: View {
    var body: some View {
        content
            .padding(12)
            .padding(.horizontal, 12)
            .background(Color.turquoise600)
            .cornerRadius(100)
    }
    
    var content: some View {
        HStack(spacing: 10) {
            Image(systemName: "photo.stack")
                .font(.body16Menlo)
                .foregroundColor(.blue600)
            
            Text(NSLocalizedString("openGallery", comment: ""))
                .font(.body16MontserratBold)
                .foregroundColor(.blue600)
        }
    }
}

#Preview {
    OpenGalleryButton()
}
