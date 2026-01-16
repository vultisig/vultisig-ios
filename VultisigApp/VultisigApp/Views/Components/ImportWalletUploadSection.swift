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
    
    @State var backgroundColor: Color = Theme.colors.border
    
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
            } else if viewModel.showAlert {
                errorContent
            } else if let filename = viewModel.importedFileName, viewModel.isFileUploaded {
                getUploadedFileContent(filename)
            } else {
                importFileContent
                    .onAppear  { backgroundColor = Theme.colors.border }
            }
        }
        .animation(.none, value: isUploading)
    }
    
    var isUploadingContent: some View {
        VStack(spacing: 16) {
            getIcon(tint: Theme.colors.bgButtonTertiary)
            
            Text(NSLocalizedString("dropFileHere", comment: ""))
                .font(Theme.fonts.bodySMedium)
                .foregroundColor(Theme.colors.textPrimary)
        }
    }
    
    var errorContent: some View {
        VStack(spacing: 16) {
            getIcon(tint: Theme.colors.alertError)
            
            Text(NSLocalizedString(viewModel.alertTitle, comment: ""))
                .font(Theme.fonts.bodySMedium)
        }
        .foregroundColor(Theme.colors.alertError)
        .onAppear {
            withAnimation {
                backgroundColor = Theme.colors.alertError
            }
        }
    }
    
    var importFileContent: some View {
        VStack(spacing: 16) {
            getIcon(tint: Theme.colors.bgButtonTertiary)
            
            Text(NSLocalizedString("importYourVaultShare", comment: ""))
                .font(Theme.fonts.bodySMedium)
                .foregroundColor(Theme.colors.textPrimary)
        }
    }
    
    private func textFile(for text: String) -> some View {
        Text(text)
            .font(Theme.fonts.caption12)
            .foregroundColor(Theme.colors.textPrimary)
            .padding(12)
    }
    
    private func getOverlay(_ lineWidth: CGFloat) -> some View {
        ZStack {
            if backgroundColor == Theme.colors.bgButtonPrimary {
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
            getIcon(isFileUploaded: true, tint: Theme.colors.alertInfo)
            
            Text(filename)
                .font(Theme.fonts.bodySMedium)
        }
        .foregroundColor(Theme.colors.alertInfo)
        .onAppear {
            withAnimation {
                backgroundColor = Theme.colors.bgButtonPrimary
            }
        }
    }
    
    private func getIcon(isFileUploaded: Bool = false, tint: Color) -> some View {
        Image(systemName: isFileUploaded ? "text.document" : "icloud.and.arrow.up")
            .foregroundColor(tint)
            .font(Theme.fonts.largeTitle)
    }
}

#Preview {
    ImportWalletUploadSection(
        viewModel: EncryptedBackupViewModel(),
        isUploading: false
    )
}
