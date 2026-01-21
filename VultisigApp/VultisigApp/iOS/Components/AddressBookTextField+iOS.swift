//
//  AddressBookTextField+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-24.
//

#if os(iOS)
import SwiftUI
import CodeScanner

extension AddressBookTextField {
    var content: some View {
        CommonTextField(
            text: $text,
            label: title.localized,
            placeholder: "typeHere".localized,
            isScrollable: isScrollable
        ) {
            if showActions {
                HStack(spacing: 8) {
                    scanButton
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
        .crossPlatformSheet(isPresented: $showScanner) {
            codeScanner
        }
    }
    var codeScanner: some View {
        AddressQRCodeScannerView(
            showScanner: $showScanner,
            onAddress: { handleScan(result: $0) }
        )
    }

    func handleScan(result: String) {
        text = Utils.sanitizeAddress(address: result)
        showScanner = false
    }

    func pasteAddress() {
        if let clipboardContent = UIPasteboard.general.string {
            text = clipboardContent
        }
    }
}
#endif
