//
//  ServerBackupVerificationView+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-11-13.
//

#if os(macOS)
import SwiftUI

extension ServerBackupVerificationView {
    var container: some View {
        VStack(spacing: 0) {
            header
            content
        }
    }
    
    var header: some View {
        ServerBackupVerificationHeader()
    }
    
    var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            title
            description
            textField
            
            if isLoading {
                loadingText
            }
            
            if showAlert {
                alertText
            }
            
            Spacer()
        }
        .padding(.horizontal, 40)
    }

    var textField: some View {
        HStack(spacing: 8) {
            field
                .multilineTextAlignment(.center)
            pasteButton
        }
        .colorScheme(.dark)
        .padding(.top, 32)
    }
    
    var field: some View {
        HStack(spacing: 8) {
            ForEach(0 ..< Self.codeLength, id: \.self) { index in
                BackspaceDetectingTextField(text: $otp[index]) {
                    handleBackspaceTap(index: index)
                }
                    .foregroundColor(Theme.colors.textPrimary)
                    .disableAutocorrection(true)
                    .borderlessTextFieldStyle()
                    .font(Theme.fonts.bodyMMedium)
                    .frame(width: 46, height: 46)
                    .background(Theme.colors.bgSurface1)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(getBorderColor(index), lineWidth: 1)
                    )
                    .focused($focusedField, equals: index)
                    .onChange(of: otp[index]) { _, newValue in
                        handleInputChange(newValue, index: index)
                    }
            }
        }
    }
    
    private func handleBackspaceTap(index: Int) {
        if otp[index].isEmpty && index > 0 {
            otp[index] = ""
            focusedField = index - 1
        }
    }

    func pasteCode() {
        let pasteboard = NSPasteboard.general
        if let clipboardContent = pasteboard.string(forType: .string), clipboardContent.count == Self.codeLength {
            otp = clipboardContent
                .map { String($0) }
        }
    }
}
#endif
