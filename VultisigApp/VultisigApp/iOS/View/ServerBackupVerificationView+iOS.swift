//
//  ServerBackupVerificationView+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-11-13.
//

#if os(iOS)
import SwiftUI

extension ServerBackupVerificationView {
    var container: some View {
        content
            .navigationTitle(NSLocalizedString("", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
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
        .padding(.horizontal, 16)
    }
    
    var textField: some View {
        HStack(spacing: 8) {
            field
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
            pasteButton
        }
        .colorScheme(.dark)
        .padding(.top, 32)
    }
    
    var field: some View {
        HStack(spacing: 8) {
            ForEach(0 ..< Self.codeLength, id: \.self) { index in
                OTPCharTextField(text: $otp[index]) {
                    focusedField = max(0, index - 1)
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
    
    func pasteCode() {
        guard
            let raw = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
            raw.count == Self.codeLength,
            raw.unicodeScalars.allSatisfy(CharacterSet.decimalDigits.contains)
        else {
            return
        }
        
        otp = raw.map(String.init)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            focusedField = Self.codeLength - 1
        }
    }
}
#endif
