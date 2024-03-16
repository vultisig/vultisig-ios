//
//  AddressTextField.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-15.
//

import OSLog
import SwiftUI
import CodeScanner

struct AddressTextField: View {
    @ObservedObject var tx: SendTransaction
    let logger: Logger
    
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
            TextField(NSLocalizedString("enterAddress", comment: "").capitalized, text: $tx.toAddress)
                .foregroundColor(.neutral0)
                .submitLabel(.next)
            
            scanButton
        }
    }
    
    var codeScanner: some View {
        CodeScannerView(codeTypes: [.qr], completion: self.handleScan)
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
                showScanner = false
            case .failure(let err):
                logger.error("fail to scan QR code,error:\(err.localizedDescription)")
        }
    }
}

#Preview {
    AddressTextField(tx: SendTransaction(), logger: Logger())
}
