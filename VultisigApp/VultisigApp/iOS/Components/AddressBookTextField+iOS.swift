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
        .sheet(isPresented: $showScanner) {
            codeScanner
        }
    }
    
    var textField: some View {
        HStack {
            field
            
            if showActions {
                pasteButton
                scanButton
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
            .keyboardType(.default)
            .textInputAutocapitalization(.never)
            .textContentType(.oneTimeCode)
        }
    }
    
    var codeScanner: some View {
        QRCodeScannerView(showScanner: $showScanner, address: $text, handleScan: handleScan)
    }
    
    func handleScan(result: Result<ScanResult, ScanError>) {
        switch result {
        case .success(let result):
            text = result.string
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
