//
//  ImportWalletUploadSection.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-13.
//

import SwiftUI

struct ImportWalletUploadSection: View {
    @ObservedObject var viewModel: EncryptedBackupViewModel
    let isUploading: Bool
    
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
                ZStack {
                    getOverlay(isUploading ? 2 : 1)
                    getOverlay(1)
                        .padding(isUploading ? 8 : 0)
                }
            )
            .animation(.easeInOut, value: isUploading)
    }
    
    var section: some View {
        ZStack {
            if let vaultText = viewModel.decryptedContent, viewModel.isFileUploaded {
                textFile(for: vaultText)
            } else {
                uploadFile
            }
        }
    }
    
    var uploadFile: some View {
        VStack(spacing: 26) {
            Image("FileIcon")
            uploadText
        }
    }
    
    var uploadText: some View {
        Text(NSLocalizedString(isUploading ? "dropFileHere" : "uploadBackupFile", comment: "Upload backup file"))
            .font(.body12MontserratSemiBold)
            .foregroundColor(.neutral0)
            .animation(.none, value: isUploading)
    }
    
    private func textFile(for text: String) -> some View {
        Text(text)
            .font(.body12MontserratSemiBold)
            .foregroundColor(.neutral0)
            .padding(12)
    }
    
    private func getOverlay(_ lineWidth: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 10)
            .strokeBorder(Color.turquoise600, style: StrokeStyle(lineWidth: lineWidth, dash: [10]))
    }
}

#Preview {
    ImportWalletUploadSection(viewModel: EncryptedBackupViewModel(), isUploading: false)
}
