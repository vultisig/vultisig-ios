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
    
    @State var backgroundColor: Color = .borderBlue
    
    var body: some View {
        uploadSection
    }
    
    var uploadSection: some View {
        section
            .frame(height: 200)
            .frame(maxWidth: .infinity)
            .background(backgroundColor.opacity(0.15))
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
            if isUploading {
                isUploadingContent
            } else if let filename = viewModel.importedFileName, viewModel.isFileUploaded {
                getUploadedFileContent(filename)
            } else if viewModel.showAlert {
                errorContent
            } else {
                importFileContent
            }
        }
        .animation(.none, value: isUploading)
    }
    
    var isUploadingContent: some View {
        VStack(spacing: 16) {
            getIcon(tint: .persianBlue400)
            
            Text(NSLocalizedString("dropFileHere", comment: ""))
                .font(.body14MontserratMedium)
                .foregroundColor(.neutral0)
        }
    }
    
    var errorContent: some View {
        VStack(spacing: 16) {
            getIcon(tint: .invalidRed)
            
            Text(NSLocalizedString(viewModel.alertTitle, comment: ""))
                .font(.body14MontserratMedium)
        }
        .foregroundColor(.invalidRed)
        .onAppear {
            withAnimation {
                backgroundColor = .invalidRed
            }
        }
    }
    
    var importFileContent: some View {
        VStack(spacing: 16) {
            getIcon(tint: .persianBlue400)
            
            Text(NSLocalizedString("importYourVaultShare", comment: ""))
                .font(.body14MontserratMedium)
                .foregroundColor(.neutral0)
        }
    }
    
    private func textFile(for text: String) -> some View {
        Text(text)
            .font(.body12MontserratSemiBold)
            .foregroundColor(.neutral0)
            .padding(12)
    }
    
    private func getOverlay(_ lineWidth: CGFloat) -> some View {
        ZStack {
            if backgroundColor == .turquoise600 {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(backgroundColor, lineWidth: 1)
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(backgroundColor, style: StrokeStyle(lineWidth: lineWidth, dash: [5]))
            }
        }
    }
    
    private func getUploadedFileContent(_ filename: String) -> some View {
        VStack(spacing: 16) {
            getIcon(isFileUploaded: true, tint: .alertTurquoise)
            
            Text(filename)
                .font(.body14MontserratMedium)
        }
        .foregroundColor(.alertTurquoise)
        .onAppear {
            withAnimation {
                backgroundColor = .turquoise600
            }
        }
    }
    
    private func getIcon(isFileUploaded: Bool = false, tint: Color) -> some View {
        Image(systemName: isFileUploaded ? "text.document" : "icloud.and.arrow.up")
            .foregroundColor(tint)
            .font(.body34BrockmannMedium)
    }
}

#Preview {
    ImportWalletUploadSection(
        viewModel: EncryptedBackupViewModel(),
        isUploading: false
    )
}
