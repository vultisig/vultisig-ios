//
//  AddressBookTextField+imacOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-24.
//

#if os(macOS)
import SwiftUI

extension AddressBookTextField {
    var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            titleContent
            textField
                .overlay {
                    ZStack {
                        if isUploading {
                            overlay
                        }
                    }
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onDrop(of: [.image], isTargeted: $isUploading) { providers -> Bool in
            OnDropQRUtils.handleOnDrop(providers: providers, handleImageQrCode: handleImageQrCode)
        }
    }
    
    var textField: some View {
        HStack {
            field
            
            if showActions {
                pasteButton
                fileButton
            }
        }
        .font(.body12Menlo)
        .foregroundColor(.neutral0)
        .frame(height: 48)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .background(Color.blue600)
        .cornerRadius(10)
        .colorScheme(.dark)
    }
    
    var field: some View {
        HStack(spacing: 0) {
            TextField(NSLocalizedString("typeHere", comment: "").capitalized, text: $text)
                .foregroundColor(.neutral0)
                .submitLabel(.next)
                .disableAutocorrection(true)
                .borderlessTextFieldStyle()
        }
    }
    
    func pasteAddress() {
        let pasteboard = NSPasteboard.general
        if let clipboardContent = pasteboard.string(forType: .string) {
            text = clipboardContent
        }
    }
}
#endif
