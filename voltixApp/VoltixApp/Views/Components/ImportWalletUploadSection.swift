//
//  ImportWalletUploadSection.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-13.
//

import SwiftUI

struct ImportWalletUploadSection: View {
    @ObservedObject var viewModel: ImportVaultViewModel
    
    var body: some View {
        uploadSection
    }
    
    var uploadSection: some View {
        section
            .frame(height: 200)
            .frame(maxWidth: .infinity)
            .background(Color.turquoise600.opacity(0.15))
            .cornerRadius(10)
            .overlay (
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.turquoise600, style: StrokeStyle(lineWidth: 1, dash: [10]))
            )
    }
    
    var section: some View {
        ZStack {
            if let vaultText = viewModel.vaultText {
                textFile(for: vaultText)
            } else {
                uploadFile
            }
        }
    }
    
    var uploadFile: some View {
        VStack(spacing: 26) {
            Image("fileIcon")
            uploadText
        }
    }
    
    var uploadText: some View {
        Text(NSLocalizedString("uploadFile", comment: "Upload file details"))
            .font(.body12MontserratSemiBold)
            .foregroundColor(.neutral0)
    }
    
    private func textFile(for text: String) -> some View {
        Text(text)
            .font(.body12MontserratSemiBold)
            .foregroundColor(.neutral0)
            .padding(12)
    }
}

#Preview {
    ImportWalletUploadSection(viewModel: ImportVaultViewModel())
}
