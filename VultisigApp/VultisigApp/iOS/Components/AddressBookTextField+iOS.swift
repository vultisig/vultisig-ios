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
            placeholder: "typeHere".localized
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
        .sheet(isPresented: $showScanner) {
            codeScanner
        }
    }
    var codeScanner: some View {
        QRCodeScannerView(showScanner: $showScanner, address: $text, handleScan: handleScan)
    }
    
    func handleScan(result: Result<ScanResult, ScanError>) {
        switch result {
        case .success(let result):
            text = Utils.sanitizeAddress(address: result.string)
            showScanner = false
        case .failure(let err):
            print("fail to scan QR code,error:\(err.localizedDescription)")
        }
    }
    
    func pasteAddress() {
        if let clipboardContent = UIPasteboard.general.string {
            text = clipboardContent
        }
    }
}
#endif
