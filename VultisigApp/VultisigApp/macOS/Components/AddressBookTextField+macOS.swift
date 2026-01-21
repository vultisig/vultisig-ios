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
        CommonTextField(
            text: $text,
            label: title.localized,
            placeholder: "typeHere".localized
        ) {
            if showActions {
                HStack(spacing: 8) {
                    fileButton
                    pasteButton
                }
            }
        }
        .overlay {
            ZStack {
                if isUploading {
                    overlay
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onDrop(of: [.image], isTargeted: $isUploading) { providers -> Bool in
            OnDropQRUtils.handleOnDrop(providers: providers, handleImageQrCode: handleImageQrCode)
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
