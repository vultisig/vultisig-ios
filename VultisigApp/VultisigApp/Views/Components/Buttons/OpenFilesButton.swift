//
//  OpenFilesButton.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 16/06/24.
//

import Foundation
import SwiftUI

struct OpenFilesButton: View {
    var body: some View {
        content
            .padding(12)
            .padding(.horizontal, 12)
            .background(Color.turquoise600)
            .cornerRadius(100)
    }
    
    var content: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder.badge.plus")
                .font(.body16Menlo)
                .foregroundColor(.blue600)
            
            Text(NSLocalizedString("uploadFromGallery", comment: ""))
                .font(.body16MontserratBold)
                .foregroundColor(.blue600)
        }
    }
}

#Preview {
    OpenGalleryButton()
}
