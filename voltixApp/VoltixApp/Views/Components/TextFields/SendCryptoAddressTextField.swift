//
//  AddressTextField.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-15.
//

import OSLog
import SwiftUI
import CodeScanner

struct SendCryptoAddressTextField: View {
    @ObservedObject var tx: SendTransaction
    @ObservedObject var sendCryptoViewModel: SendCryptoViewModel
    
    @State var showScanner = false
    
    var body: some View {
        ZStack(alignment: .trailing) {
            if tx.toAddress.isEmpty {
                placeholder
            }
            
            field
        }
        .font(.body12Menlo)
        .foregroundColor(.neutral0)
        .frame(height: 48)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .background(Color.blue600)
        .cornerRadius(10)
        .sheet(isPresented: $showScanner, content: {
            codeScanner
        })
    }
    
    var placeholder: some View {
        Text(NSLocalizedString("enterAddress", comment: ""))
            .foregroundColor(Color.neutral0)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    var field: some View {
        HStack(spacing: 0) {
            TextField(NSLocalizedString("enterAddress", comment: "").capitalized, text: Binding<String>(
                get: { tx.toAddress },
                set: { newValue in
                    tx.toAddress = newValue
                    DebounceHelper.shared.debounce {
                        validateAddress(newValue)
                    }
                }
            ))
            .foregroundColor(.neutral0)
            .submitLabel(.next)
            .textInputAutocapitalization(.never)
            .disableAutocorrection(true)
            .keyboardType(.default)
            .textContentType(.oneTimeCode)
            
            pasteButton
            scanButton
        }
    }
    
   var codeScanner: some View {
       QRCodeScannerView(showScanner: $showScanner, handleScan: handleScan)
   }
    
    var pasteButton: some View {
        Button {
            pasteAddress()
        } label: {
            Image(systemName: "doc.on.clipboard")
                .font(.body16Menlo)
                .foregroundColor(.neutral0)
                .frame(width: 40, height: 40)
        }
    }
    
    var scanButton: some View {
        Button {
            showScanner.toggle()
        } label: {
            Image(systemName: "camera")
                .font(.body16Menlo)
                .foregroundColor(.neutral0)
                .frame(width: 40, height: 40)
        }
    }
    
    private func handleScan(result: Result<ScanResult, ScanError>) {
        switch result {
        case .success(let result):
            let qrCodeResult = result.string
            tx.parseCryptoURI(qrCodeResult)
            validateAddress(tx.toAddress)
            showScanner = false
        case .failure(let err):
            sendCryptoViewModel.logger.error("fail to scan QR code,error:\(err.localizedDescription)")
        }
    }
    
    private func validateAddress(_ newValue: String) {
        sendCryptoViewModel.validateAddress(tx: tx, address: newValue)
    }
    
    private func pasteAddress() {
        if let clipboardContent = UIPasteboard.general.string {
            tx.toAddress = clipboardContent
            
            DebounceHelper.shared.debounce {
                validateAddress(clipboardContent)
            }
        }
    }
}

#Preview {
    SendCryptoAddressTextField(tx: SendTransaction(), sendCryptoViewModel: SendCryptoViewModel())
}
