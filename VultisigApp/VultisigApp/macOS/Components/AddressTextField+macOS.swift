//
//  AddressTextField+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-25.
//

#if os(macOS)
import SwiftUI

extension AddressTextField {
    var content: some View {
        ZStack(alignment: .trailing) {
            field
        }
        .font(.body12Menlo)
        .foregroundColor(.neutral0)
        .frame(height: 48)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .background(Color.blue600)
        .cornerRadius(10)
    }
    
    var field: some View {
        HStack(spacing: 0) {
            TextField(NSLocalizedString("enterContractAddress", comment: "").toFormattedTitleCase(), text: $contractAddress)
                .foregroundColor(.neutral0)
                .submitLabel(.next)
                .disableAutocorrection(true)
                .textContentType(.oneTimeCode)
                .maxLength($contractAddress)
                .onChange(of: contractAddress){oldValue,newValue in
                    validateAddress(newValue)
                }
                .borderlessTextFieldStyle()
            
            pasteButton
            
            if showScanIcon {
                fileButton
            }

            if showAddressBookIcon {
                addressBookButton
            }
        }
    }
    
    func pasteAddress() {
        let pasteboard = NSPasteboard.general
        if let clipboardContent = pasteboard.string(forType: .string) {
            contractAddress = clipboardContent
            validateAddress(clipboardContent)
        }
    }
}
#endif
